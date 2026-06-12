import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../blueprint/model/controller_layout.dart';
import '../blueprint/model/graph.dart';
import '../blueprint/model/node_def.dart';
import '../blueprint/model/pins.dart';
import '../blueprint/model/variables.dart';
import '../models/project.dart';
import '../services/brick_connection.dart';
import '../services/ev3_brick.dart';
import 'connect_sheet.dart';
import 'graph_runner.dart';

/// Run mode: the controller the kid designed, full screen and live.
///
/// Control events run through the blueprint graph via [GraphRunner] and out
/// to whichever brick is active: the real EV3 when [connection] is
/// connected, the practice-mode mock otherwise.
///
/// Safety (R-05): every motor is stopped when this screen goes away or the
/// app loses focus.
class RunMode extends StatefulWidget {
  const RunMode(
      {super.key, required this.project, this.brick, this.connection});

  final Project project;

  /// Test override; takes precedence over [connection].
  final Ev3Brick? brick;

  /// The app-wide Bluetooth connection, if this platform has one.
  final BrickConnection? connection;

  @override
  State<RunMode> createState() => _RunModeState();
}

class _RunModeState extends State<RunMode>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final ControllerLayout _layout;
  late final GraphRunner _runner;
  final MockEv3Brick _practice = MockEv3Brick();
  late final Ticker _ticker;
  int _activeTab = 0;
  bool _showLog = false;
  bool _lossShown = false;

  Ev3Brick get _activeBrick =>
      widget.brick ?? widget.connection?.brick ?? _practice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.connection?.addListener(_onConnectionChanged);
    _layout = ControllerLayout.fromJson(widget.project.controller);
    final variables = VariableSet.fromJson(widget.project.variables);
    final graph = BlueprintGraph.fromJson(
      widget.project.graph,
      dynamicDefs: {kControllerDefId: _layout.buildNodeDef()},
      variables: variables,
    );
    _runner = GraphRunner(
        graph: graph,
        layout: _layout,
        brick: _activeBrick,
        variables: variables);
    _runner.start(); // fire On Start nodes
    // The UE5-style game loop: one runner tick per rendered frame. A
    // free-running ticker never lets the widget tree "settle", so it only
    // runs under the real app binding — tick logic is unit-tested on
    // GraphRunner directly.
    _ticker = createTicker((_) => _runner.tick());
    if (WidgetsBinding.instance is WidgetsFlutterBinding) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _activeBrick.stopAll(); // never leave motors running behind us
    _runner.dispose();
    widget.connection?.removeListener(_onConnectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    setState(() => _runner.brick = _activeBrick);
    final connection = widget.connection!;
    if (connection.connectionWasLost && !_lossShown) {
      _lossShown = true;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Lost the robot! Back to practice mode.'),
      ));
    }
    if (connection.state == BrickConnectionState.connected) {
      _lossShown = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _activeBrick.stopAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _layout.tabs;
    final tab = tabs[_activeTab.clamp(0, tabs.length - 1)];
    return Container(
      color: const Color(0xFF14181E),
      child: Column(
        children: [
          _buildStatusBar(),
          if (tabs.length > 1) _buildTabBar(tabs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Same aspect-ratio stage as the designer miniature, so the
                // layout lands exactly where it was designed.
                final stage = fitAspect(
                  Size(constraints.maxWidth - 16, constraints.maxHeight - 16),
                  tab.aspect,
                );
                return Center(
                  child: Container(
                    key: const Key('run-stage'),
                    width: stage.width,
                    height: stage.height,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2028),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListenableBuilder(
                      listenable: _runner,
                      builder: (context, _) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (tab.controls.isEmpty)
                            const Center(
                              child: Text(
                                'No controls yet — add some in Build!',
                                style: TextStyle(color: Colors.white38),
                              ),
                            ),
                          for (final control
                              in controlsInPaintOrder(tab.controls))
                            _buildControl(control, stage,
                                stage.width / stageUnitsWidth(tab.landscape)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_showLog) _buildLogPanel(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          _buildConnectionChip(),
          const Spacer(),
          IconButton(
            key: const Key('toggle-log'),
            tooltip: 'Robot commands',
            icon: Icon(
              Icons.receipt_long,
              color: _showLog ? Colors.amber : Colors.white54,
            ),
            onPressed: () => setState(() => _showLog = !_showLog),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionChip() {
    final connection = widget.connection;
    final (icon, color, label) = switch (connection?.state) {
      BrickConnectionState.connected => (
          Icons.bluetooth_connected,
          Colors.green,
          'Connected to ${connection!.deviceName}',
        ),
      BrickConnectionState.connecting => (
          Icons.bluetooth_searching,
          Colors.amber,
          'Connecting…',
        ),
      _ => (
          Icons.smart_toy_outlined,
          null,
          connection != null && connection.supported
              ? 'Practice mode — tap to connect'
              : 'Practice mode — pretend robot',
        ),
    };
    final chipLabel = Text(label, style: const TextStyle(fontSize: 12));
    final avatar = Icon(icon, size: 16, color: color as Color?);
    if (connection == null || !connection.supported) {
      return Chip(
        avatar: avatar,
        label: chipLabel,
        visualDensity: VisualDensity.compact,
      );
    }
    return ActionChip(
      key: const Key('connection-chip'),
      avatar: avatar,
      label: chipLabel,
      visualDensity: VisualDensity.compact,
      onPressed: () => showConnectSheet(context, connection),
    );
  }

  Widget _buildTabBar(List<ControllerTab> tabs) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (index, tab) in tabs.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('run-tab-${tab.id}'),
                label: Text(tab.name),
                selected: index == _activeTab.clamp(0, tabs.length - 1),
                onSelected: (_) => setState(() => _activeTab = index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    final brick = _activeBrick;
    return Container(
      height: 150,
      width: double.infinity,
      color: Colors.black54,
      padding: const EdgeInsets.all(8),
      child: brick is MockEv3Brick
          ? ListenableBuilder(
              listenable: brick,
              builder: (context, _) => brick.log.isEmpty
                  ? const Text('No commands yet — press something!',
                      style: TextStyle(color: Colors.white38, fontSize: 12))
                  : ListView(
                      reverse: true,
                      children: [
                        for (final entry in brick.log.reversed)
                          Text(entry,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              )),
                      ],
                    ),
            )
          : const Text('Connected — commands go to your real EV3!',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
    );
  }

  // ---- controls ------------------------------------------------------------

  Widget _buildControl(ControllerControl control, Size stage, double factor) {
    final base = controlBaseSizeFor(control);
    // Stage-unit size scaled to this stage's pixels — identical fraction of
    // the stage as in the designer miniature. Width and height stretch
    // independently.
    final size = Size(
      base.width * control.scaleX * factor,
      base.height * control.scaleY * factor,
    );
    // Displays and plotters are laid out at their real size instead of being
    // scaled through a FittedBox, so their text / dots stay crisp at any
    // control size.
    final sized = control.kind == ControlKind.display
        ? SizedBox(
            width: size.width,
            height: size.height,
            child: _RunDisplay(
                control: control, runner: _runner, factor: factor),
          )
        : control.kind == ControlKind.plotter
            ? SizedBox(
                width: size.width,
                height: size.height,
                child: _RunPlotter(
                    control: control, runner: _runner, factor: factor),
              )
            : SizedBox(
            width: size.width,
            height: size.height,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: base.width,
                height: base.height,
                child: switch (control.kind) {
                  ControlKind.button =>
                    _RunButton(control: control, runner: _runner),
                  ControlKind.dpad =>
                    _RunDpad(control: control, runner: _runner),
                  ControlKind.slider =>
                    _RunSlider(control: control, runner: _runner),
                  ControlKind.toggle =>
                    _RunToggle(control: control, runner: _runner),
                  ControlKind.joystick =>
                    _RunJoystick(control: control, runner: _runner),
                  ControlKind.light =>
                    _RunLight(control: control, runner: _runner),
                  ControlKind.plotter => const SizedBox.shrink(), // above
                  ControlKind.display => const SizedBox.shrink(), // above
                },
              ),
            ),
          );
    // Output-only controls must never swallow a touch meant for whatever is
    // underneath them.
    final passive = control.kind == ControlKind.light ||
        control.kind == ControlKind.plotter ||
        control.kind == ControlKind.display;
    return Positioned(
      left: control.position.dx * stage.width - size.width / 2,
      top: control.position.dy * stage.height - size.height / 2,
      child: passive ? IgnorePointer(child: sized) : sized,
    );
  }

}

const TextStyle _controlNameStyle =
    TextStyle(color: Colors.white70, fontSize: 12);

class _RunButton extends StatefulWidget {
  const _RunButton({required this.control, required this.runner});

  final ControllerControl control;
  final GraphRunner runner;

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton> {
  // Counted, not boolean: a second finger on the same button must not
  // re-fire pressed, and released only fires when the last finger lifts.
  int _pointers = 0;

  bool get _pressed => _pointers > 0;

  void _down() {
    _pointers++;
    if (_pointers == 1) {
      setState(() {});
      widget.runner.buttonPressed(widget.control.id);
    }
  }

  void _up() {
    if (_pointers == 0) return;
    _pointers--;
    if (_pointers == 0) {
      setState(() {});
      widget.runner.buttonReleased(widget.control.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      key: Key('run-control-${widget.control.id}'),
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        decoration: BoxDecoration(
          color: _pressed ? scheme.primary : const Color(0xFF3C4654),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Center(
          child: widget.control.showName
              ? Text(
                  widget.control.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _RunDpad extends StatelessWidget {
  const _RunDpad({required this.control, required this.runner});

  final ControllerControl control;
  final GraphRunner runner;

  Widget _arrow(String direction, IconData icon) {
    return _HoldArea(
      key: Key('run-dpad-${control.id}-$direction'),
      onDown: () => runner.dpadPressed(control.id, direction),
      onUp: () => runner.dpadReleased(control.id, direction),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF3C4654),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _arrow('up', Icons.keyboard_arrow_up),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _arrow('left', Icons.keyboard_arrow_left),
            SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: control.showName
                    ? Text(control.name,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: _controlNameStyle)
                    : null,
              ),
            ),
            _arrow('right', Icons.keyboard_arrow_right),
          ],
        ),
        _arrow('down', Icons.keyboard_arrow_down),
      ],
    );
  }
}

/// Fires onDown when the first pointer touches and onUp when the last one
/// lifts — extra fingers on the same area don't re-fire.
class _HoldArea extends StatefulWidget {
  const _HoldArea(
      {super.key,
      required this.onDown,
      required this.onUp,
      required this.child});

  final VoidCallback onDown;
  final VoidCallback onUp;
  final Widget child;

  @override
  State<_HoldArea> createState() => _HoldAreaState();
}

class _HoldAreaState extends State<_HoldArea> {
  int _pointers = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (++_pointers == 1) widget.onDown();
      },
      onPointerUp: (_) {
        if (_pointers > 0 && --_pointers == 0) widget.onUp();
      },
      onPointerCancel: (_) {
        if (_pointers > 0 && --_pointers == 0) widget.onUp();
      },
      child: widget.child,
    );
  }
}

/// A snap-to-touch slider: touching anywhere on the track jumps the value to
/// that point and holds while the finger is down, even if the finger drags
/// outside the control (the value just clamps). Renders horizontally or
/// vertically and reflects the runner's value live (so spring-return
/// animates).
class _RunSlider extends StatelessWidget {
  const _RunSlider({required this.control, required this.runner});

  final ControllerControl control;
  final GraphRunner runner;

  void _setFromLocal(Offset local, Size size) {
    final frac = control.sliderVertical
        ? 1 - (local.dy / size.height) // top = max
        : local.dx / size.width;
    final min = control.sliderMin;
    final max = control.sliderMax;
    final value = (min + frac.clamp(0.0, 1.0) * (max - min)).round();
    runner.sliderChanged(control.id, value);
  }

  @override
  Widget build(BuildContext context) {
    final min = control.sliderMin.toDouble();
    final max = control.sliderMax.toDouble();
    final value =
        runner.sliderValue(control.id).toDouble().clamp(min, max);
    final frac = (max > min) ? (value - min) / (max - min) : 0.0;
    final label = [
      if (control.showName) control.name,
      if (control.showValue) '${value.round()}',
    ].join(': ');

    final track = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          onPointerDown: (e) {
            runner.sliderTouchStart(control.id);
            _setFromLocal(e.localPosition, size);
          },
          onPointerMove: (e) => _setFromLocal(e.localPosition, size),
          onPointerUp: (_) => runner.sliderTouchEnd(control.id),
          onPointerCancel: (_) => runner.sliderTouchEnd(control.id),
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            key: Key('run-control-${control.id}'),
            size: Size.infinite,
            painter: _SliderPainter(
              fraction: frac,
              vertical: control.sliderVertical,
              fill: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );

    if (control.sliderVertical) {
      return Row(
        children: [
          Expanded(child: track),
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(label,
                  overflow: TextOverflow.ellipsis, style: _controlNameStyle),
            ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (label.isNotEmpty)
          Text(label,
              overflow: TextOverflow.ellipsis, style: _controlNameStyle),
        Expanded(child: track),
      ],
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(
      {required this.fraction, required this.vertical, required this.fill});

  final double fraction;
  final bool vertical;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const trackThickness = 8.0;
    const knobRadius = 14.0;
    final rrect = vertical
        ? RRect.fromLTRBR(
            size.width / 2 - trackThickness / 2, 0,
            size.width / 2 + trackThickness / 2, size.height,
            const Radius.circular(trackThickness / 2))
        : RRect.fromLTRBR(0, size.height / 2 - trackThickness / 2,
            size.width, size.height / 2 + trackThickness / 2,
            const Radius.circular(trackThickness / 2));
    canvas.drawRRect(rrect, Paint()..color = Colors.white24);

    final knob = vertical
        ? Offset(size.width / 2, size.height * (1 - fraction))
        : Offset(size.width * fraction, size.height / 2);
    canvas.drawCircle(knob, knobRadius, Paint()..color = fill);
    canvas.drawCircle(
        knob,
        knobRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.fraction != fraction || old.vertical != vertical || old.fill != fill;
}

/// A 2-axis joystick. Touch anywhere to move the stick there (clamped inside
/// the circle); tracks the finger even outside the pad, and springs back to
/// centre when released if powered. Reflects the runner's position live.
class _RunJoystick extends StatelessWidget {
  const _RunJoystick({required this.control, required this.runner});

  final ControllerControl control;
  final GraphRunner runner;

  void _moveFromLocal(Offset local, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy);
    final vx = (local.dx - cx) / radius * 50;
    final vy = -(local.dy - cy) / radius * 50; // up = positive
    runner.joystickMoved(control.id, vx, vy);
  }

  @override
  Widget build(BuildContext context) {
    final pos = runner.joystickPos(control.id);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          onPointerDown: (e) {
            runner.joystickTouchStart(control.id);
            _moveFromLocal(e.localPosition, size);
          },
          onPointerMove: (e) => _moveFromLocal(e.localPosition, size),
          onPointerUp: (_) => runner.joystickTouchEnd(control.id),
          onPointerCancel: (_) => runner.joystickTouchEnd(control.id),
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            key: Key('run-control-${control.id}'),
            size: Size.infinite,
            painter: _JoystickPainter(
              x: pos.x,
              y: pos.y,
              knob: Theme.of(context).colorScheme.primary,
              label: control.showName ? control.name : null,
            ),
          ),
        );
      },
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter(
      {required this.x,
      required this.y,
      required this.knob,
      required this.label});

  final double x;
  final double y;
  final Color knob;
  final String? label;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    // Pad
    canvas.drawCircle(centre, radius, Paint()..color = const Color(0xFF2B313A));
    canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white24);
    // Stick
    final knobPos = centre + Offset(x / 50 * radius, -y / 50 * radius);
    canvas.drawCircle(knobPos, radius * 0.32, Paint()..color = knob);
    canvas.drawCircle(
        knobPos,
        radius * 0.32,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
    if (label != null) {
      final tp = TextPainter(
        text: TextSpan(
            text: label, style: const TextStyle(color: Colors.white70)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(canvas,
          Offset(centre.dx - tp.width / 2, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.x != x || old.y != y || old.knob != knob || old.label != label;
}

/// Plots the runner's stored dots, mapping each dot's (x,y) from the
/// plotter's configured range to the box.
class _RunPlotter extends StatelessWidget {
  const _RunPlotter(
      {required this.control, required this.runner, required this.factor});

  final ControllerControl control;
  final GraphRunner runner;
  final double factor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (control.showName)
          Text(control.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white70, fontSize: 12 * factor)),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: control.plotterFramed
                ? BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24, width: 2),
                  )
                : null,
            child: CustomPaint(
              key: Key('run-control-${control.id}'),
              size: Size.infinite,
              painter: _PlotterPainter(
                dots: runner.plotDots(control.id),
                minX: control.plotterMinX,
                maxX: control.plotterMaxX,
                minY: control.plotterMinY,
                maxY: control.plotterMaxY,
                dotRadius: control.plotterDotSize * factor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlotterPainter extends CustomPainter {
  _PlotterPainter({
    required this.dots,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.dotRadius,
  });

  final List<PlotDot> dots;
  final int minX, maxX, minY, maxY;
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final spanX = (maxX - minX) == 0 ? 1 : (maxX - minX);
    final spanY = (maxY - minY) == 0 ? 1 : (maxY - minY);
    final r = dotRadius;
    for (final dot in dots) {
      final colour = (dot.colour >= 1 && dot.colour < kEv3Palette.length)
          ? kEv3Palette[dot.colour]
          : null;
      if (colour == null) continue; // 0 = no colour → don't draw
      final fx = ((dot.x - minX) / spanX).clamp(0.0, 1.0);
      final fy = ((dot.y - minY) / spanY).clamp(0.0, 1.0);
      final p = Offset(fx * size.width, (1 - fy) * size.height); // y up
      canvas.drawCircle(p, r, Paint()..color = colour);
    }
  }

  @override
  bool shouldRepaint(_PlotterPainter old) => true; // dots change each draw
}

class _RunToggle extends StatelessWidget {
  const _RunToggle({required this.control, required this.runner});

  final ControllerControl control;
  final GraphRunner runner;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (control.showName)
          Text(control.name,
              overflow: TextOverflow.ellipsis, style: _controlNameStyle),
        Switch(
          key: Key('run-control-${control.id}'),
          value: runner.toggleValue(control.id),
          onChanged: (v) => runner.toggleChanged(control.id, v),
        ),
      ],
    );
  }
}

/// Fills the box it's given; only the box scales with the size sliders —
/// the text renders at its configured size (times the stage factor) and is
/// never stretched or distorted.
class _RunDisplay extends StatelessWidget {
  const _RunDisplay(
      {required this.control, required this.runner, required this.factor});

  final ControllerControl control;
  final GraphRunner runner;
  final double factor;

  @override
  Widget build(BuildContext context) {
    final value = runner.displayValue(control.id);
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: control.displayFramed
                ? BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24, width: 2),
                  )
                : null,
            child: Center(
              child: Text(
                value ?? '--',
                key: Key('run-display-${control.id}'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: PinType.string.color,
                  fontSize: control.displayTextSize * factor,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        if (control.showName) ...[
          SizedBox(height: 4 * factor),
          Text(control.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white70, fontSize: 12 * factor)),
        ],
      ],
    );
  }
}

/// The EV3 colour palette: index 0 is off, 1-7 follow the brick's colour
/// codes (Black, Blue, Green, Yellow, Red, White, Brown).
const List<Color?> kEv3Palette = [
  null, // 0 = No Colour (off)
  Color(0xFF000000), // 1 Black
  Color(0xFF2962FF), // 2 Blue
  Color(0xFF00C853), // 3 Green
  Color(0xFFFFEB3B), // 4 Yellow
  Color(0xFFD50000), // 5 Red
  Color(0xFFFFFFFF), // 6 White
  Color(0xFF8D6E63), // 7 Brown
];

class _RunLight extends StatelessWidget {
  const _RunLight({required this.control, required this.runner});

  final ControllerControl control;
  final GraphRunner runner;

  @override
  Widget build(BuildContext context) {
    final colour = runner.lightColour(control.id);
    final brightness = runner.lightBrightness(control.id);
    final base = (colour >= 0 && colour < kEv3Palette.length)
        ? kEv3Palette[colour]
        : null;
    final on = base != null && brightness > 0;
    // Brightness dims the colour toward black; off shows the dark socket.
    final shown = on
        ? Color.lerp(Colors.black, base, brightness / 100)!
        : const Color(0xFF2B313A);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          key: Key('run-light-${control.id}'),
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: shown,
            border: Border.all(color: Colors.white30, width: 2),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: shown.withValues(alpha: 0.6),
                      blurRadius: 14,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
        ),
        if (control.showName) ...[
          const SizedBox(height: 4),
          Text(control.name,
              overflow: TextOverflow.ellipsis, style: _controlNameStyle),
        ],
      ],
    );
  }
}
