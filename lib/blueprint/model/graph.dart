import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'node_def.dart';
import 'pins.dart';

/// Node id of the one controller node every project has.
const String kControllerNodeId = 'controller';

/// One node placed on the blueprint canvas.
class GraphNode {
  GraphNode({
    required this.id,
    required this.defId,
    required this.label,
    required this.position,
    Map<String, dynamic>? config,
  }) : config = config ?? {};

  final String id;
  final String defId;

  /// User-editable display name; cosmetic only, never affects behaviour.
  String label;

  /// Canvas coordinates of the node's top-left corner.
  Offset position;

  /// Per-node settings (EV3 port, constant value, …).
  final Map<String, dynamic> config;

  /// Set for nodes whose pins aren't fixed by the catalog — the controller
  /// node, whose def is rebuilt whenever the controller layout changes.
  NodeDef? dynamicDef;

  NodeDef get def => dynamicDef ?? nodeDefById(defId)!;

  Map<String, dynamic> toJson() => {
        'id': id,
        'def': defId,
        'label': label,
        'x': position.dx,
        'y': position.dy,
        'config': config,
      };

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
        id: json['id'] as String,
        defId: json['def'] as String,
        label: json['label'] as String,
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
        config: (json['config'] as Map?)?.cast<String, dynamic>(),
      );
}

/// A connection from an output pin to an input pin.
class Wire {
  const Wire({
    required this.fromNode,
    required this.fromPin,
    required this.toNode,
    required this.toPin,
  });

  final String fromNode; // output side
  final String fromPin;
  final String toNode; // input side
  final String toPin;

  PinRef get from => PinRef(fromNode, fromPin, isOutput: true);
  PinRef get to => PinRef(toNode, toPin, isOutput: false);

  Map<String, dynamic> toJson() => {
        'fromNode': fromNode,
        'fromPin': fromPin,
        'toNode': toNode,
        'toPin': toPin,
      };

  factory Wire.fromJson(Map<String, dynamic> json) => Wire(
        fromNode: json['fromNode'] as String,
        fromPin: json['fromPin'] as String,
        toNode: json['toNode'] as String,
        toPin: json['toPin'] as String,
      );
}

/// The blueprint: nodes plus the wires between their pins, with the
/// connection rules (UE5-style) enforced at the model level so the UI can't
/// create an invalid graph:
///
/// * only output → input, matching pin type, different nodes;
/// * an input pin holds at most one wire (a new one replaces it);
/// * a power *output* drives at most one target (use Sequence for more);
/// * data outputs may fan out to any number of inputs.
class BlueprintGraph extends ChangeNotifier {
  BlueprintGraph();

  final Map<String, GraphNode> _nodes = {};
  final List<Wire> _wires = [];
  int _seq = 0;

  List<GraphNode> get nodes => List.unmodifiable(_nodes.values);
  List<Wire> get wires => List.unmodifiable(_wires);

  GraphNode? node(String id) => _nodes[id];

  GraphNode addNode(NodeDef def, Offset position) {
    final node = GraphNode(
      id: 'n${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '-${_seq++}',
      defId: def.id,
      label: def.title,
      position: position,
      config: def.defaultConfig(),
    );
    _nodes[node.id] = node;
    notifyListeners();
    return node;
  }

  void moveNode(String id, Offset delta) {
    final node = _nodes[id];
    if (node == null) return;
    node.position += delta;
    notifyListeners();
  }

  void renameNode(String id, String label) {
    final node = _nodes[id];
    if (node == null || label.trim().isEmpty) return;
    node.label = label.trim();
    notifyListeners();
  }

  void setConfig(String id, String key, Object value) {
    final node = _nodes[id];
    if (node == null) return;
    node.config[key] = value;
    notifyListeners();
  }

  void removeNode(String id) {
    if (id == kControllerNodeId) return; // the controller can't be deleted
    if (_nodes.remove(id) == null) return;
    _wires.removeWhere((w) => w.fromNode == id || w.toNode == id);
    _refreshSequenceNodes();
    notifyListeners();
  }

  /// Inserts the project's controller node if it doesn't exist yet, and
  /// (re)applies its dynamic definition. Called once when the editor opens.
  ///
  /// The controller goes FIRST in iteration order so it paints underneath —
  /// it's by far the biggest node, and smaller nodes dragged over it must
  /// stay visible and tappable.
  GraphNode ensureControllerNode(NodeDef def, Offset position) {
    var node = _nodes[kControllerNodeId];
    if (node == null) {
      node = GraphNode(
        id: kControllerNodeId,
        defId: kControllerDefId,
        label: 'Controller',
        position: position,
      );
      final others = Map<String, GraphNode>.of(_nodes);
      _nodes
        ..clear()
        ..[kControllerNodeId] = node
        ..addAll(others);
    }
    node.dynamicDef = def;
    return node;
  }

  /// Swaps in a rebuilt dynamic definition (the controller layout changed)
  /// and prunes any wires whose pins no longer exist.
  void setDynamicDef(String nodeId, NodeDef def) {
    final node = _nodes[nodeId];
    if (node == null) return;
    node.dynamicDef = def;
    _wires.removeWhere(
        (w) => pinType(w.from) == null || pinType(w.to) == null);
    notifyListeners();
  }

  PinType? pinType(PinRef ref) =>
      _nodes[ref.nodeId]?.def.pin(ref.pinId, isOutput: ref.isOutput)?.type;

  /// True when a wire between these two pins would be valid, in either
  /// tap order.
  ///
  /// Self-wiring is rejected except on the controller node: wiring a toggle
  /// straight to a light (both controller pins) is natural and safe — the
  /// runner guards against evaluation cycles.
  bool canConnect(PinRef a, PinRef b) {
    if (a.isOutput == b.isOutput) return false;
    if (a.nodeId == b.nodeId && a.nodeId != kControllerNodeId) return false;
    final typeA = pinType(a);
    return typeA != null && typeA == pinType(b);
  }

  /// Connects two pins (tap order doesn't matter). Returns false if the
  /// connection is invalid.
  bool connect(PinRef a, PinRef b) {
    if (!canConnect(a, b)) return false;
    final output = a.isOutput ? a : b;
    final input = a.isOutput ? b : a;

    // An input holds one wire; a power output drives one target.
    _wires.removeWhere(
        (w) => w.toNode == input.nodeId && w.toPin == input.pinId);
    if (pinType(output) == PinType.power) {
      _wires.removeWhere(
          (w) => w.fromNode == output.nodeId && w.fromPin == output.pinId);
    }

    _wires.add(Wire(
      fromNode: output.nodeId,
      fromPin: output.pinId,
      toNode: input.nodeId,
      toPin: input.pinId,
    ));
    _refreshSequenceNodes();
    notifyListeners();
    return true;
  }

  /// Sequence nodes always keep one spare output: wiring the last `then`
  /// grows a new one; freeing trailing ones shrinks back (never below 2).
  void _refreshSequenceNodes() {
    for (final node in _nodes.values) {
      if (node.defId != 'flow.sequence') continue;
      var highestWired = 0;
      for (final wire in _wires) {
        if (wire.fromNode != node.id || !wire.fromPin.startsWith('then')) {
          continue;
        }
        final index = int.tryParse(wire.fromPin.substring(4)) ?? 0;
        if (index > highestWired) highestWired = index;
      }
      final outs = math.max(2, highestWired + 1);
      if (node.def.outputs.length != outs) {
        node.dynamicDef = sequenceDef(outs);
      }
    }
  }

  /// Removes every wire attached to [ref]'s side of the connection.
  void disconnectPin(PinRef ref) {
    final before = _wires.length;
    _wires.removeWhere((w) => ref.isOutput
        ? w.fromNode == ref.nodeId && w.fromPin == ref.pinId
        : w.toNode == ref.nodeId && w.toPin == ref.pinId);
    if (_wires.length != before) {
      _refreshSequenceNodes();
      notifyListeners();
    }
  }

  Map<String, dynamic> toJson() => {
        'nodes': _nodes.values.map((n) => n.toJson()).toList(),
        'wires': _wires.map((w) => w.toJson()).toList(),
      };

  /// Reads the graph out of a project's `graph` map. Nodes whose definition
  /// no longer exists (an old save after a catalog change) are skipped, as
  /// are wires that lost an endpoint — a stale file must never crash the app.
  ///
  /// [dynamicDefs] supplies definitions that aren't in the catalog, keyed by
  /// defId — the controller node's layout-derived def.
  factory BlueprintGraph.fromJson(
    Map<String, dynamic> json, {
    Map<String, NodeDef> dynamicDefs = const {},
  }) {
    final graph = BlueprintGraph();
    for (final raw in (json['nodes'] as List? ?? const [])) {
      final node = GraphNode.fromJson((raw as Map).cast<String, dynamic>());
      final dynamicDef = dynamicDefs[node.defId];
      if (dynamicDef != null) {
        node.dynamicDef = dynamicDef;
      } else if (nodeDefById(node.defId) == null) {
        debugPrint('Skipping node with unknown def ${node.defId}');
        continue;
      }
      graph._nodes[node.id] = node;
    }
    // Load all wires first and grow sequence nodes to cover them — a wire
    // into a grown `then3` is only valid once the def has grown — then drop
    // any wire that still has a missing endpoint.
    for (final raw in (json['wires'] as List? ?? const [])) {
      graph._wires.add(Wire.fromJson((raw as Map).cast<String, dynamic>()));
    }
    graph._refreshSequenceNodes();
    graph._wires.removeWhere((w) =>
        graph.pinType(w.from) == null || graph.pinType(w.to) == null);
    graph._refreshSequenceNodes();
    return graph;
  }
}
