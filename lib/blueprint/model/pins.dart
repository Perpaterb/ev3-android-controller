import 'package:flutter/material.dart';

/// What a pin carries. The colours here are the single source of truth used
/// by pin dots, wires, and the add-node menu (see the colour legend in
/// USER_STORIES.md): power = white, integer = green, boolean = red.
enum PinType {
  power(Color(0xFFFFFFFF)),
  integer(Color(0xFF4CAF50)),
  boolean(Color(0xFFE53935));

  const PinType(this.color);

  final Color color;
}

/// Node families, colour-coding their headers and the add-node menu.
enum NodeCategory {
  motor('Motors', Color(0xFFD97E2B)),
  sensor('Sensors', Color(0xFF3D7BD9)),
  math('Math', Color(0xFF3F9E4D)),
  logic('Logic', Color(0xFF5A6472)),
  flow('Flow', Color(0xFF707C8C)),
  value('Values', Color(0xFF2F8F83)),
  controller('Controller', Color(0xFF7E57C2));

  const NodeCategory(this.label, this.color);

  final String label;
  final Color color;
}

/// One connection point in a node definition.
class PinSpec {
  const PinSpec(this.id, this.label, this.type);

  final String id;
  final String label;
  final PinType type;
}

/// Points at one pin of one node instance on the canvas.
@immutable
class PinRef {
  const PinRef(this.nodeId, this.pinId, {required this.isOutput});

  final String nodeId;
  final String pinId;
  final bool isOutput;

  @override
  bool operator ==(Object other) =>
      other is PinRef &&
      other.nodeId == nodeId &&
      other.pinId == pinId &&
      other.isOutput == isOutput;

  @override
  int get hashCode => Object.hash(nodeId, pinId, isOutput);

  @override
  String toString() => 'PinRef($nodeId.$pinId ${isOutput ? 'out' : 'in'})';
}
