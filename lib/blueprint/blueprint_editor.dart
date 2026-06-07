import 'dart:async';

import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/project_store.dart';
import 'blueprint_canvas.dart';
import 'canvas_viewport.dart';
import 'model/controller_layout.dart';
import 'model/graph.dart';
import 'model/node_def.dart';
import 'model/pins.dart';
import 'node_geometry.dart';
import 'widgets/add_control_sheet.dart';
import 'widgets/add_node_sheet.dart';
import 'widgets/controller_node_widget.dart';
import 'widgets/node_widget.dart';
import 'widgets/wire_painter.dart';

/// Build mode: the blueprint editor for one project.
///
/// Owns the editor state — graph, controller layout, selection, wiring mode,
/// viewport — and autosaves everything (debounced) so reopening the project
/// restores exactly what was on screen.
class BlueprintEditor extends StatefulWidget {
  const BlueprintEditor(
      {super.key, required this.store, required this.project});

  final ProjectStore store;
  final Project project;

  @override
  State<BlueprintEditor> createState() => _BlueprintEditorState();
}

class _BlueprintEditorState extends State<BlueprintEditor> {
  // Created lazily in the first layout pass: a brand-new project should open
  // with the canvas origin centred, which needs the screen size.
  CanvasViewport? _viewport;
  Map<String, dynamic>? _savedViewportJson;

  late final BlueprintGraph _graph;
  late final ControllerLayout _layout;
  String? _selectedNodeId;

  /// The pin a wire is being drawn from while wiring mode is active.
  PinRef? _wiringFrom;

  Timer? _saveTimer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _layout = ControllerLayout.fromJson(widget.project.controller);
    final controllerDef = _layout.buildNodeDef();
    _graph = BlueprintGraph.fromJson(
      widget.project.graph,
      dynamicDefs: {kControllerDefId: controllerDef},
    );
    // Every project has its controller front and centre on the canvas.
    _graph.ensureControllerNode(
      controllerDef,
      Offset(-kControllerNodeWidth / 2,
          -controllerNodeSize(controllerDef).height / 2),
    );
    _graph.addListener(_onGraphChanged);
    _layout.addListener(_onLayoutChanged);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) _persist();
    _persistViewport();
    _graph.removeListener(_onGraphChanged);
    _layout.removeListener(_onLayoutChanged);
    super.dispose();
  }

  // ---- persistence -------------------------------------------------------

  void _onGraphChanged() {
    setState(() {});
    _markDirty();
  }

  void _onLayoutChanged() {
    // The layout drives the controller node's pins; rebuilding the def also
    // prunes wires to pins that no longer exist (and notifies the graph,
    // which triggers the rebuild + save).
    _graph.setDynamicDef(kControllerNodeId, _layout.buildNodeDef());
  }

  void _markDirty() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  void _persist() {
    _dirty = false;
    widget.project.graph.addAll(_graph.toJson());
    widget.project.controller
      ..clear()
      ..addAll(_layout.toJson());
    widget.store.save(widget.project);
  }

  void _persistViewport() {
    final viewport = _viewport;
    if (viewport == null) return;
    final json = viewport.toJson();
    if (json.toString() != _savedViewportJson.toString()) {
      widget.project.graph['viewport'] = json;
      widget.store.save(widget.project);
    }
  }

  CanvasViewport _createViewport(Size size) {
    final json = widget.project.graph['viewport'];
    _savedViewportJson = (json as Map?)?.cast<String, dynamic>();
    if (_savedViewportJson != null) {
      return CanvasViewport.fromJson(_savedViewportJson);
    }
    return CanvasViewport(translation: size.center(Offset.zero));
  }

  // ---- wiring mode -------------------------------------------------------

  void _onTapPin(PinRef ref) {
    final from = _wiringFrom;
    if (from == null) {
      setState(() => _wiringFrom = ref);
      return;
    }
    if (ref == from) {
      _cancelWiring(); // tapping the same pin again backs out
      return;
    }
    if (_graph.canConnect(from, ref)) {
      _graph.connect(from, ref);
      setState(() => _wiringFrom = null);
    }
    // Incompatible pin: ignore the tap, stay in wiring mode.
  }

  void _cancelWiring() => setState(() => _wiringFrom = null);

  bool _pinHighlighted(PinRef ref) {
    final from = _wiringFrom;
    return from != null && (ref == from || _graph.canConnect(from, ref));
  }

  bool _nodeDimmed(GraphNode node) {
    final from = _wiringFrom;
    if (from == null || node.id == from.nodeId) return false;
    for (final input in node.def.inputs) {
      if (_graph.canConnect(from, PinRef(node.id, input.id, isOutput: false))) {
        return false;
      }
    }
    for (final output in node.def.outputs) {
      if (_graph.canConnect(from, PinRef(node.id, output.id, isOutput: true))) {
        return false;
      }
    }
    return true;
  }

  void _onDisconnectPin(PinRef ref) {
    final hadWires =
        _graph.wires.any((w) => ref.isOutput ? w.from == ref : w.to == ref);
    if (!hadWires) return;
    _graph.disconnectPin(ref);
    _toast('Disconnected');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ));
  }

  // ---- node actions ------------------------------------------------------

  Future<void> _addNodeAt(Offset canvasPosition) async {
    final def = await showAddNodeSheet(context);
    if (def == null) return;
    final node = _graph.addNode(def, canvasPosition);
    setState(() => _selectedNodeId = node.id);
  }

  Future<void> _renameNode(GraphNode node) async {
    final name = await _promptForText(
      title: 'Rename node',
      initial: node.label,
      confirmLabel: 'Rename',
    );
    if (name != null) _graph.renameNode(node.id, name);
  }

  void _onTapCanvas(Offset _) {
    setState(() {
      _selectedNodeId = null;
      _wiringFrom = null; // tapping empty canvas also backs out of wiring
    });
  }

  void _resetView(Size size) {
    _viewport?.follow(
      screenFocal: size.center(Offset.zero),
      canvasFocal: Offset.zero,
      scale: 1,
    );
  }

  // ---- controller actions ------------------------------------------------

  Future<void> _addControl(String tabId, Offset fraction) async {
    final kind = await showAddControlSheet(context);
    if (kind == null || !mounted) return;
    final name = await _promptForText(
      title: 'Name your ${kind.label.toLowerCase()}',
      initial: _layout.defaultControlName(kind),
      confirmLabel: 'Add',
    );
    if (name == null) return;
    _layout.addControl(
        tabId: tabId, kind: kind, name: name, position: fraction);
  }

  Future<void> _controlMenu(ControllerControl control) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(control.name,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(control.kind.label),
            ),
            ListTile(
              key: const Key('control-rename'),
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              key: const Key('control-delete'),
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        final name = await _promptForText(
          title: 'Rename control',
          initial: control.name,
          confirmLabel: 'Rename',
        );
        if (name != null) _layout.renameControl(control.id, name);
      case 'delete':
        final confirmed = await _confirm(
          title: "Delete '${control.name}'?",
          message: 'Any wires connected to it will be removed.',
        );
        if (confirmed) _layout.removeControl(control.id);
    }
  }

  Future<void> _addTab() async {
    final name = await _promptForText(
      title: 'New tab',
      initial: 'Tab ${_layout.tabs.length + 1}',
      confirmLabel: 'Add',
    );
    if (name != null) _layout.addTab(name);
  }

  Future<void> _tabMenu(ControllerTab tab) async {
    final canDelete = _layout.tabs.length > 1;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(tab.name,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: const Text('Controller tab'),
            ),
            ListTile(
              key: const Key('tab-rename'),
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              key: const Key('tab-delete'),
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              subtitle:
                  canDelete ? null : const Text('Your last tab has to stay'),
              enabled: canDelete,
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        final name = await _promptForText(
          title: 'Rename tab',
          initial: tab.name,
          confirmLabel: 'Rename',
        );
        if (name != null) _layout.renameTab(tab.id, name);
      case 'delete':
        final confirmed = tab.controls.isEmpty ||
            await _confirm(
              title: "Delete '${tab.name}'?",
              message: 'Its ${tab.controls.length} control(s) and their '
                  'wires will be removed.',
            );
        if (confirmed) _layout.removeTab(tab.id);
    }
  }

  // ---- dialogs -----------------------------------------------------------

  Future<String?> _promptForText({
    required String title,
    required String initial,
    required String confirmLabel,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) {
        void submit() {
          final value = controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: Text(confirmLabel)),
          ],
        );
      },
    );
  }

  Future<bool> _confirm(
      {required String title, required String message}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final viewport = _viewport ??= _createViewport(size);
        return Stack(
          children: [
            Positioned.fill(
              child: BlueprintCanvas(
                viewport: viewport,
                onTapCanvas: _onTapCanvas,
                onLongPressCanvas: _addNodeAt,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: WirePainter(
                          graph: _graph,
                          viewport: viewport,
                          faded: _wiringFrom != null,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: viewport,
                      builder: (context, _) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final node in _nodesInPaintOrder())
                            _buildNode(node, viewport),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_wiringFrom != null) _buildWiringBanner(),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'canvas-reset-view',
                tooltip: 'Back to centre',
                onPressed: () => _resetView(size),
                child: const Icon(Icons.filter_center_focus),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Selected node paints last (on top).
  List<GraphNode> _nodesInPaintOrder() {
    final nodes = _graph.nodes.toList();
    final selectedIndex = nodes.indexWhere((n) => n.id == _selectedNodeId);
    if (selectedIndex >= 0) {
      nodes.add(nodes.removeAt(selectedIndex));
    }
    return nodes;
  }

  Widget _buildNode(GraphNode node, CanvasViewport viewport) {
    final screenPosition = viewport.toScreen(node.position);
    final child = node.id == kControllerNodeId
        ? ControllerNodeWidget(
            key: const ValueKey('node-controller'),
            node: node,
            layout: _layout,
            selected: node.id == _selectedNodeId,
            dimmed: _nodeDimmed(node),
            wiringActive: _wiringFrom != null,
            pinHighlighted: _pinHighlighted,
            onSelect: () => setState(() => _selectedNodeId = node.id),
            onMoveBy: (delta) => _graph.moveNode(node.id, delta),
            onRename: () => _renameNode(node),
            onTapPin: _onTapPin,
            onLongPressPin: _onDisconnectPin,
            onAddTab: _addTab,
            onTabMenu: _tabMenu,
            onAddControl: _addControl,
            onControlMenu: _controlMenu,
            onMoveControl: (control, delta) =>
                _layout.moveControl(control.id, delta),
          )
        : NodeWidget(
            key: ValueKey('node-${node.id}'),
            node: node,
            selected: node.id == _selectedNodeId,
            dimmed: _nodeDimmed(node),
            wiringActive: _wiringFrom != null,
            pinHighlighted: _pinHighlighted,
            onSelect: () => setState(() => _selectedNodeId = node.id),
            onMoveBy: (delta) => _graph.moveNode(node.id, delta),
            onRename: () => _renameNode(node),
            onDelete: () {
              _graph.removeNode(node.id);
              setState(() => _selectedNodeId = null);
            },
            onTapPin: _onTapPin,
            onLongPressPin: _onDisconnectPin,
            onConfigChanged: (key, value) =>
                _graph.setConfig(node.id, key, value),
          );
    return Positioned(
      left: screenPosition.dx,
      top: screenPosition.dy,
      child: Transform.scale(
        scale: viewport.scale,
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }

  Widget _buildWiringBanner() {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tap a glowing pin to connect',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(width: 10),
                FloatingActionButton.small(
                  key: const Key('cancel-wiring'),
                  heroTag: 'cancel-wiring',
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  tooltip: 'Cancel',
                  onPressed: _cancelWiring,
                  child: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
