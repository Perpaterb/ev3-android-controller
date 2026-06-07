import 'dart:math' as math;
import 'dart:ui';

import 'model/node_def.dart';

/// Node layout metrics, fixed so pin positions are computable without
/// measuring widgets — the wire painter and the node widget must agree on
/// exactly where each pin sits.
const double kNodeWidth = 180;
const double kNodeHeaderHeight = 34;
const double kPinRowHeight = 30;
const double kNodeConfigHeight = 40;
const double kNodeBottomPadding = 6;

/// Pin dots sit this far inside the node's edge; wires vanish under the node
/// body so they appear to start exactly at the edge.
const double kPinInset = 10;

int pinRowCount(NodeDef def) =>
    math.max(def.inputs.length, def.outputs.length);

Size nodeSize(NodeDef def) => Size(
      kNodeWidth,
      kNodeHeaderHeight +
          pinRowCount(def) * kPinRowHeight +
          (def.configKind == NodeConfigKind.none ? 0 : kNodeConfigHeight) +
          kNodeBottomPadding,
    );

/// Offset of a pin's centre from the node's top-left corner, in canvas units.
Offset pinOffset(NodeDef def, String pinId, {required bool isOutput}) {
  final pins = isOutput ? def.outputs : def.inputs;
  final index = pins.indexWhere((p) => p.id == pinId);
  assert(index >= 0, 'Unknown pin $pinId on ${def.id}');
  return Offset(
    isOutput ? kNodeWidth - kPinInset : kPinInset,
    kNodeHeaderHeight + index * kPinRowHeight + kPinRowHeight / 2,
  );
}
