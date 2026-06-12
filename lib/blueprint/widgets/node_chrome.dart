import 'package:flutter/material.dart';

import '../model/pins.dart';
import '../node_geometry.dart';

/// Tappable pin dot, colour-coded by type. Shared by regular nodes and the
/// controller node so wiring looks and behaves identically everywhere.
///
/// A pin with no wire is drawn as a hollow ring; a connected pin is a filled
/// disc. [highlighted] is the white "you can connect here" glow during
/// wiring; [linked] is the orange glow on pins already joined to the pin
/// you've selected.
class PinDot extends StatelessWidget {
  const PinDot({
    super.key,
    required this.type,
    required this.highlighted,
    required this.faded,
    required this.connected,
    required this.onTap,
    required this.onLongPress,
    this.linked = false,
    this.rowHeight = kPinRowHeight,
  });

  /// Orange used for the "already linked to the selected pin" glow.
  static const Color linkColor = Color(0xFFFFA726);

  final PinType type;
  final bool highlighted;
  final bool faded;
  final bool connected;
  final bool linked;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    const dotSize = 18.0; // ~50% bigger than before
    final glow = linked
        ? linkColor
        : (highlighted ? type.color.withValues(alpha: 0.8) : null);
    final borderColor = linked
        ? linkColor
        : (highlighted ? Colors.white : Colors.black54);
    return GestureDetector(
      // Absorb the tap even when faded: a mis-tap on an incompatible pin
      // shouldn't fall through and cancel wiring mode.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        // Centre of the dot lands exactly kPinInset inside the node edge,
        // matching the pin offsets in node_geometry.dart.
        width: 2 * kPinInset,
        height: rowHeight,
        child: Center(
          child: Opacity(
            opacity: faded ? 0.25 : 1,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Filled when connected; hollow (ring) when unconnected.
                color: connected ? type.color : const Color(0xFF2B313A),
                border: Border.all(
                  color: connected ? borderColor : type.color,
                  width: (linked || highlighted) ? 3 : (connected ? 1.5 : 2.5),
                ),
                boxShadow: glow != null
                    ? [BoxShadow(color: glow, blurRadius: 9, spreadRadius: 2)]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small icon button that fits inside a node header.
class NodeHeaderButton extends StatelessWidget {
  const NodeHeaderButton(
      {super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
