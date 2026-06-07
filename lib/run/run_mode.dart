import 'package:flutter/material.dart';

import '../blueprint/model/controller_layout.dart';
import '../blueprint/model/graph.dart';
import '../blueprint/model/node_def.dart';
import '../models/project.dart';
import '../services/ev3_brick.dart';
import 'graph_runner.dart';

/// Run mode: the controller the kid designed, full screen and live.
///
/// Control events run through the blueprint graph via [GraphRunner] and out
/// to the brick. For now the brick is always the practice-mode mock; the
/// real Bluetooth brick (Epic 2) will slot into the same field.
///
/// Safety (R-05): every motor is stopped when this screen goes away or the
/// app loses focus.
class RunMode extends StatefulWidget {
  const RunMode({super.key, required this.project, this.brick});

  final Project project;

  /// Injectable for tests; defaults to a fresh [MockEv3Brick].
  final Ev3Brick? brick;

  @override
  State<RunMode> createState() => _RunModeState();
}

class _RunModeState extends State<RunMode> with WidgetsBindingObserver {
  late final ControllerLayout _layout;
  late final Ev3Brick _brick;
  late final GraphRunner _runner;
  int _activeTab = 0;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _layout = ControllerLayout.fromJson(widget.project.controller);
    final graph = BlueprintGraph.fromJson(
      widget.project.graph,
      dynamicDefs: {kControllerDefId: _layout.buildNodeDef()},
    );
    _brick = widget.brick ?? MockEv3Brick();
    _runner = GraphRunner(graph: graph, layout: _layout, brick: _brick);
  }

  @override
  void dispose() {
    _brick.stopAll(); // leaving Run mode must never leave motors running
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _brick.stopAll();
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
                final area = constraints.biggest;
                return ListenableBuilder(
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
                      for (final control in tab.controls)
                        _buildControl(control, area),
                    ],
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
          Chip(
            avatar: const Icon(Icons.smart_toy_outlined, size: 16),
            label: const Text('Practice mode — pretend robot'),
            labelStyle: const TextStyle(fontSize: 12),
            visualDensity: VisualDensity.compact,
          ),
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
    final mock = _brick;
    return Container(
      height: 150,
      width: double.infinity,
      color: Colors.black54,
      padding: const EdgeInsets.all(8),
      child: mock is MockEv3Brick
          ? ListenableBuilder(
              listenable: mock,
              builder: (context, _) => mock.log.isEmpty
                  ? const Text('No commands yet — press something!',
                      style: TextStyle(color: Colors.white38, fontSize: 12))
                  : ListView(
                      reverse: true,
                      children: [
                        for (final entry in mock.log.reversed)
                          Text(entry,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              )),
                      ],
                    ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ---- controls ------------------------------------------------------------

  Widget _buildControl(ControllerControl control, Size area) {
    final size = _controlSize(control.kind);
    final child = switch (control.kind) {
      ControlKind.button => _RunButton(control: control, runner: _runner),
      ControlKind.dpad => _RunDpad(control: control, runner: _runner),
      ControlKind.slider => _RunSlider(control: control, runner: _runner),
      ControlKind.toggle => _RunToggle(control: control, runner: _runner),
      ControlKind.light => _RunLight(control: control, runner: _runner),
    };
    return Positioned(
      left: control.position.dx * area.width - size.width / 2,
      top: control.position.dy * area.height - size.height / 2,
      child: SizedBox(
          width: size.width, height: size.height, child: child),
    );
  }

  static Size _controlSize(ControlKind kind) => switch (kind) {
        ControlKind.button => const Size(120, 64),
        ControlKind.slider => const Size(240, 76),
        ControlKind.toggle => const Size(110, 72),
        ControlKind.dpad => const Size(168, 168),
        ControlKind.light => const Size(80, 76),
      };
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
  bool _pressed = false;

  void _down() {
    setState(() => _pressed = true);
    widget.runner.buttonPressed(widget.control.id);
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.runner.buttonReleased(widget.control.id);
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
          child: Text(
            widget.control.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
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
      onUp: () => runner.dpadReleased(control.id),
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
                child: Text(control.name,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _controlNameStyle),
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

/// Fires onDown when touched and onUp when the pointer lifts or leaves.
class _HoldArea extends StatelessWidget {
  const _HoldArea(
      {super.key,
      required this.onDown,
      required this.onUp,
      required this.child});

  final VoidCallback onDown;
  final VoidCallback onUp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: child,
    );
  }
}

class _RunSlider extends StatelessWidget {
  const _RunSlider({required this.control, required this.runner});

  final ControllerControl control;
  final GraphRunner runner;

  @override
  Widget build(BuildContext context) {
    final min = (control.config['min'] as num?)?.toDouble() ?? 0;
    final max = (control.config['max'] as num?)?.toDouble() ?? 100;
    final value =
        runner.sliderValue(control.id).toDouble().clamp(min, max);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${control.name}: ${value.round()}',
            overflow: TextOverflow.ellipsis, style: _controlNameStyle),
        Slider(
          key: Key('run-control-${control.id}'),
          min: min,
          max: max,
          value: value,
          onChanged: (v) => runner.sliderChanged(control.id, v.round()),
        ),
      ],
    );
  }
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

class _RunLight extends StatelessWidget {
  const _RunLight({required this.control, required this.runner});

  final ControllerControl control;
  final GraphRunner runner;

  @override
  Widget build(BuildContext context) {
    final on = runner.lightOn(control.id);
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
            color: on ? Colors.amber : const Color(0xFF2B313A),
            border: Border.all(color: Colors.white30, width: 2),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.6),
                      blurRadius: 14,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(control.name,
            overflow: TextOverflow.ellipsis, style: _controlNameStyle),
      ],
    );
  }
}
