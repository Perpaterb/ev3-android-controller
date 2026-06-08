import 'dart:math' as math;
import 'dart:ui';

import 'model/graph.dart';
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

/// Controller node metrics: pin label columns flank a central layout area
/// showing the controller's controls. Sized so a landscape stage renders at
/// roughly 1:1 with its virtual 800x450 units — the designer miniature is
/// then near-actual-size. The pin columns are generous so labels like
/// "Steer left released" aren't clipped.
const double kControllerNodeWidth = 1280;
const double kControllerPinColumnWidth = 190;
const double kControllerTabRowHeight = 36;
const double kControllerMinContentHeight = 458;
const double kControllerPinRowHeight = 26;

double controllerContentHeight(NodeDef def) => math.max(
      kControllerMinContentHeight,
      math.max(def.inputs.length, def.outputs.length) *
          kControllerPinRowHeight,
    );

Size controllerNodeSize(NodeDef def) => Size(
      kControllerNodeWidth,
      kNodeHeaderHeight +
          kControllerTabRowHeight +
          controllerContentHeight(def) +
          kNodeBottomPadding,
    );

Offset controllerPinOffset(NodeDef def, String pinId,
    {required bool isOutput}) {
  final pins = isOutput ? def.outputs : def.inputs;
  final index = pins.indexWhere((p) => p.id == pinId);
  assert(index >= 0, 'Unknown controller pin $pinId');
  return Offset(
    isOutput ? kControllerNodeWidth - kPinInset : kPinInset,
    kNodeHeaderHeight +
        kControllerTabRowHeight +
        index * kControllerPinRowHeight +
        kControllerPinRowHeight / 2,
  );
}

/// Pin offset for any node instance — dispatches to the controller layout
/// for the controller node, the standard layout otherwise.
Offset nodePinOffset(GraphNode node, String pinId, {required bool isOutput}) =>
    node.id == kControllerNodeId
        ? controllerPinOffset(node.def, pinId, isOutput: isOutput)
        : pinOffset(node.def, pinId, isOutput: isOutput);
