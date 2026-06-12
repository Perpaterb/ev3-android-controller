import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../model/controller_layout.dart';
import '../model/graph.dart';
import '../model/pins.dart';
import '../node_geometry.dart';
import 'node_chrome.dart';

/// The controller node: a live miniature of the controller the kid is
/// designing, sitting on the blueprint canvas like any other node.
///
/// Header drags the node, tabs switch pages, long-press inside the layout
/// area adds a control, tap a control to manage it, drag it to move it.
/// Every control capability shows as a wireable pin on the node's edge —
/// inputs (lights) on the left, outputs (buttons, sliders, …) on the right.
class ControllerNodeWidget extends StatefulWidget {
  const ControllerNodeWidget({
    super.key,
    required this.node,
    required this.layout,
    required this.selected,
    required this.dimmed,
    required this.wiringActive,
    required this.pinHighlighted,
    required this.pinConnected,
    required this.pinLinked,
    required this.onSelect,
    required this.onMoveBy,
    required this.onRename,
    required this.onTapPin,
    required this.onLongPressPin,
    required this.onAddTab,
    required this.onTabMenu,
    required this.onAddControl,
    required this.onControlMenu,
    required this.onMoveControl,
  });

  final GraphNode node;
  final ControllerLayout layout;
  final bool selected;
  final bool dimmed;
  final bool wiringActive;
  final bool Function(PinRef ref) pinHighlighted;
  final bool Function(PinRef ref) pinConnected;
  final bool Function(PinRef ref) pinLinked;

  final VoidCallback onSelect;
  final void Function(Offset canvasDelta) onMoveBy;
  final VoidCallback onRename;
  final void Function(PinRef ref) onTapPin;
  final void Function(PinRef ref) onLongPressPin;

  final VoidCallback onAddTab;
  final void Function(ControllerTab tab) onTabMenu;
  final void Function(String tabId, Offset fractionalPosition) onAddControl;
  final void Function(ControllerControl control) onControlMenu;
  final void Function(ControllerControl control, Offset fractionalDelta)
      onMoveControl;

  @override
  State<ControllerNodeWidget> createState() => _ControllerNodeWidgetState();
}

class _ControllerNodeWidgetState extends State<ControllerNodeWidget> {
  int _activeTab = 0;

  static const Color _bodyColor = Color(0xFF2B313A);
  static const TextStyle _pinLabelStyle =
      TextStyle(color: Colors.white70, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final def = widget.node.def;
    final tabs = widget.layout.tabs;
    final activeTab = tabs[_activeTab.clamp(0, tabs.length - 1)];
    final contentHeight = controllerContentHeight(def);

    return Opacity(
      opacity: widget.dimmed ? 0.3 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: Container(
          width: kControllerNodeWidth,
          decoration: BoxDecoration(
            color: _bodyColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected
                  ? Colors.white
                  : NodeCategory.controller.color,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 6),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              _buildTabBar(tabs),
              SizedBox(
                height: contentHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPinColumn(def.inputs, isOutput: false),
                    Expanded(child: _buildLayoutArea(activeTab)),
                    _buildPinColumn(def.outputs, isOutput: true),
                  ],
                ),
              ),
              const SizedBox(height: kNodeBottomPadding),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return GestureDetector(
      key: Key('node-header-${widget.node.id}'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: widget.onSelect,
      onPanStart: (_) => widget.onSelect(),
      onPanUpdate: (details) => widget.onMoveBy(details.delta),
      child: Container(
        height: kNodeHeaderHeight,
        decoration: BoxDecoration(
          color: NodeCategory.controller.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            const Icon(Icons.sports_esports, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.node.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            if (widget.selected)
              NodeHeaderButton(
                key: const Key('node-edit-controller'),
                icon: Icons.edit,
                onTap: widget.onRename,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(List<ControllerTab> tabs) {
    return SizedBox(
      height: kControllerTabRowHeight,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final (index, tab) in tabs.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: GestureDetector(
                        onLongPress: () => widget.onTabMenu(tab),
                        child: ChoiceChip(
                          key: Key('ctrl-tab-${tab.id}'),
                          label: Text(tab.name,
                              style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          selected: index ==
                              _activeTab.clamp(0, tabs.length - 1),
                          onSelected: (_) =>
                              setState(() => _activeTab = index),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          NodeHeaderButton(
            key: const Key('ctrl-add-tab'),
            icon: Icons.add,
            onTap: widget.onAddTab,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildPinColumn(List<PinSpec> pins, {required bool isOutput}) {
    return SizedBox(
      width: kControllerPinColumnWidth,
      child: Column(
        children: [
          for (final spec in pins)
            SizedBox(
              height: kControllerPinRowHeight,
              child: Row(
                children: [
                  if (!isOutput) _buildPin(spec, isOutput: false),
                  Expanded(
                    child: Text(
                      spec.label,
                      overflow: TextOverflow.ellipsis,
                      textAlign: isOutput ? TextAlign.right : TextAlign.left,
                      style: _pinLabelStyle,
                    ),
                  ),
                  if (isOutput) _buildPin(spec, isOutput: true),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPin(PinSpec spec, {required bool isOutput}) {
    final ref = PinRef(widget.node.id, spec.id, isOutput: isOutput);
    final highlighted = widget.pinHighlighted(ref);
    final linked = widget.pinLinked(ref);
    return PinDot(
      key: Key('pin-${widget.node.id}-${spec.id}-${isOutput ? 'out' : 'in'}'),
      type: spec.type,
      highlighted: highlighted,
      linked: linked,
      connected: widget.pinConnected(ref),
      faded: widget.wiringActive && !highlighted && !linked,
      onTap: () => widget.onTapPin(ref),
      onLongPress: () => widget.onLongPressPin(ref),
      rowHeight: kControllerPinRowHeight,
    );
  }

  Widget _buildLayoutArea(ControllerTab tab) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The stage keeps the same aspect ratio as the Run screen (per the
        // tab's orientation), letterboxed inside the available area, so
        // what you lay out here is exactly what you get when you run it.
        final stage = fitAspect(
          Size(constraints.maxWidth - 8, constraints.maxHeight - 8),
          tab.aspect,
        );
        return Center(
          child: GestureDetector(
            key: const Key('controller-layout-area'),
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (details) => widget.onAddControl(
              tab.id,
              Offset(
                details.localPosition.dx / stage.width,
                details.localPosition.dy / stage.height,
              ),
            ),
            child: Container(
              width: stage.width,
              height: stage.height,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (tab.controls.isEmpty)
                    const Center(
                      child: Text(
                        'Hold here to add\na button, slider…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                    ),
                  for (final control in controlsInPaintOrder(tab.controls))
                    _buildControl(control, stage,
                        stage.width / stageUnitsWidth(tab.landscape)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControl(ControllerControl control, Size stage, double factor) {
    // Stage-unit size scaled to this stage's pixels — identical fraction of
    // the stage as in Run mode. Width and height stretch independently.
    final base = controlBaseSizeFor(control);
    final size = Size(
      base.width * control.scaleX * factor,
      base.height * control.scaleY * factor,
    );
    return Positioned(
      left: control.position.dx * stage.width - size.width / 2,
      top: control.position.dy * stage.height - size.height / 2,
      child: GestureDetector(
        key: Key('control-${control.id}'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTap: () => widget.onControlMenu(control),
        // Also claim long-press, so holding on a control manages it instead
        // of falling through to the area's add-control long-press.
        onLongPress: () => widget.onControlMenu(control),
        onPanUpdate: (details) => widget.onMoveControl(
          control,
          Offset(details.delta.dx / stage.width,
              details.delta.dy / stage.height),
        ),
        child: SizedBox(
          width: size.width,
          height: size.height,
          // Displays render at real size so their text never stretches;
          // everything else scales through a FittedBox.
          child: control.kind == ControlKind.display
              ? _DisplayPreview(control: control, factor: factor)
              : FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: base.width,
                    height: base.height,
                    child: _ControlVisual(control: control),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Designer twin of the Run-mode display: the box fills the control's size,
/// the sample text stays at its configured (unstretched) size.
class _DisplayPreview extends StatelessWidget {
  const _DisplayPreview({required this.control, required this.factor});

  final ControllerControl control;
  final double factor;

  @override
  Widget build(BuildContext context) {
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
                'Abc',
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
        SizedBox(height: 4 * factor),
        Text(control.name,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(color: Colors.white70, fontSize: 12 * factor)),
      ],
    );
  }
}

/// Non-interactive replica of how the control looks on the Run screen,
/// built at the same stage-unit base size — what you design is what you get.
class _ControlVisual extends StatelessWidget {
  const _ControlVisual({required this.control});

  final ControllerControl control;

  static const TextStyle _nameStyle =
      TextStyle(color: Colors.white70, fontSize: 12);
  static const Color _faceColor = Color(0xFF3C4654);

  Widget _dot(Color colour) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      );

  Widget _arrowPad(IconData icon) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _faceColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      );

  @override
  Widget build(BuildContext context) {
    return switch (control.kind) {
      ControlKind.button => Container(
          decoration: BoxDecoration(
            color: _faceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 2),
          ),
          child: Center(
            child: Text(control.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                )),
          ),
        ),
      ControlKind.slider => control.sliderVertical
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${control.name}: 0',
                    overflow: TextOverflow.ellipsis, style: _nameStyle),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ControlKind.toggle => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(control.name,
                overflow: TextOverflow.ellipsis, style: _nameStyle),
            const SizedBox(height: 6),
            Container(
              width: 48,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: CircleAvatar(
                      radius: 12, backgroundColor: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ControlKind.plotter => Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            decoration: control.plotterFramed
                ? BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24, width: 2),
                  )
                : null,
            child: Stack(
              children: [
                Align(
                  alignment: const Alignment(-0.3, 0.4),
                  child: _dot(const Color(0xFFD50000)),
                ),
                Align(
                  alignment: const Alignment(0.4, -0.2),
                  child: _dot(const Color(0xFF2962FF)),
                ),
                Align(
                  alignment: const Alignment(0.1, 0.7),
                  child: _dot(const Color(0xFF00C853)),
                ),
              ],
            ),
          ),
        ),
      ControlKind.joystick => Padding(
          padding: const EdgeInsets.all(8),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2B313A),
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.34,
                  heightFactor: 0.34,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ControlKind.dpad => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _arrowPad(Icons.keyboard_arrow_up),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _arrowPad(Icons.keyboard_arrow_left),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Text(control.name,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: _nameStyle),
                  ),
                ),
                _arrowPad(Icons.keyboard_arrow_right),
              ],
            ),
            _arrowPad(Icons.keyboard_arrow_down),
          ],
        ),
      ControlKind.light => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2B313A),
                border: Border.all(color: Colors.white30, width: 2),
              ),
            ),
            const SizedBox(height: 4),
            Text(control.name,
                overflow: TextOverflow.ellipsis, style: _nameStyle),
          ],
        ),
      ControlKind.display => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: (control.displayTextSize + 16).clamp(44.0, 60.0),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: Center(
                child: Text('Abc',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: PinType.string.color,
                      fontSize: control.displayTextSize,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    )),
              ),
            ),
            const SizedBox(height: 4),
            Text(control.name,
                overflow: TextOverflow.ellipsis, style: _nameStyle),
          ],
        ),
    };
  }
}
