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
      TextStyle(color: Colors.white70, fontSize: 10);

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
    return PinDot(
      key: Key('pin-${widget.node.id}-${spec.id}-${isOutput ? 'out' : 'in'}'),
      type: spec.type,
      highlighted: highlighted,
      faded: widget.wiringActive && !highlighted,
      onTap: () => widget.onTapPin(ref),
      onLongPress: () => widget.onLongPressPin(ref),
      rowHeight: kControllerPinRowHeight,
    );
  }

  Widget _buildLayoutArea(ControllerTab tab) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        return GestureDetector(
          key: const Key('controller-layout-area'),
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (details) => widget.onAddControl(
            tab.id,
            Offset(
              details.localPosition.dx / area.width,
              details.localPosition.dy / area.height,
            ),
          ),
          child: Container(
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
                for (final control in tab.controls)
                  _buildControl(control, area),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControl(ControllerControl control, Size area) {
    final size = _controlSize(control.kind);
    return Positioned(
      left: control.position.dx * area.width - size.width / 2,
      top: control.position.dy * area.height - size.height / 2,
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
          Offset(details.delta.dx / area.width,
              details.delta.dy / area.height),
        ),
        child: _ControlVisual(control: control),
      ),
    );
  }

  static Size _controlSize(ControlKind kind) => switch (kind) {
        ControlKind.button => const Size(72, 34),
        ControlKind.slider => const Size(100, 38),
        ControlKind.toggle => const Size(64, 38),
        ControlKind.dpad => const Size(64, 58),
        ControlKind.light => const Size(48, 42),
      };
}

/// Miniature, non-interactive rendering of a control for the designer.
class _ControlVisual extends StatelessWidget {
  const _ControlVisual({required this.control});

  final ControllerControl control;

  static const TextStyle _nameStyle =
      TextStyle(color: Colors.white70, fontSize: 10);

  @override
  Widget build(BuildContext context) {
    return switch (control.kind) {
      ControlKind.button => Container(
          width: 72,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF3C4654),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Center(
            child: Text(control.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
      ControlKind.slider => SizedBox(
          width: 100,
          height: 38,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(control.name,
                  overflow: TextOverflow.ellipsis, style: _nameStyle),
              const SizedBox(height: 4),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: PinType.integer.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ControlKind.toggle => SizedBox(
          width: 64,
          height: 38,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(control.name,
                  overflow: TextOverflow.ellipsis, style: _nameStyle),
              const SizedBox(height: 3),
              Container(
                width: 30,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.all(1.5),
                    child: CircleAvatar(
                        radius: 5.5, backgroundColor: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ControlKind.dpad => SizedBox(
          width: 64,
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.control_camera,
                  size: 36, color: Colors.white54),
              Text(control.name,
                  overflow: TextOverflow.ellipsis, style: _nameStyle),
            ],
          ),
        ),
      ControlKind.light => SizedBox(
          width: 48,
          height: 42,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white12,
                  border: Border.all(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 2),
              Text(control.name,
                  overflow: TextOverflow.ellipsis, style: _nameStyle),
            ],
          ),
        ),
    };
  }
}
