import 'dart:async';

import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/project_store.dart';
import 'blueprint_canvas.dart';
import 'canvas_viewport.dart';
import 'model/graph.dart';
import 'model/pins.dart';
import 'widgets/add_node_sheet.dart';
import 'widgets/node_widget.dart';
import 'widgets/wire_painter.dart';

/// Build mode: the blueprint editor for one project.
///
/// Owns the editor state — graph, selection, wiring mode, viewport — and
/// autosaves the graph (debounced) plus the viewport so reopening the
/// project restores exactly what was on screen.
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
  String? _selectedNodeId;

  /// The pin a wire is being drawn from while wiring mode is active.
  PinRef? _wiringFrom;

  Timer? _saveTimer;
  bool _graphDirty = false;

  @override
  void initState() {
    super.initState();
    _graph = BlueprintGraph.fromJson(widget.project.graph);
    _graph.addListener(_onGraphChanged);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_graphDirty) _persistGraph();
    _persistViewport();
    _graph.removeListener(_onGraphChanged);
    super.dispose();
  }

  // ---- persistence -------------------------------------------------------

  void _onGraphChanged() {
    setState(() {});
    _graphDirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persistGraph);
  }

  void _persistGraph() {
    _graphDirty = false;
    widget.project.graph.addAll(_graph.toJson());
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Disconnected'),
        duration: Duration(seconds: 1),
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
    final controller = TextEditingController(text: node.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        void submit() {
          final value = controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        }

        return AlertDialog(
          title: const Text('Rename node'),
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
            FilledButton(onPressed: submit, child: const Text('Rename')),
          ],
        );
      },
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
    return Positioned(
      left: screenPosition.dx,
      top: screenPosition.dy,
      child: Transform.scale(
        scale: viewport.scale,
        alignment: Alignment.topLeft,
        child: NodeWidget(
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
        ),
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
