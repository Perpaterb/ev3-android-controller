import 'package:flutter/material.dart';

import '../model/pins.dart';
import '../node_geometry.dart';

/// Tappable pin dot, colour-coded by type. Shared by regular nodes and the
/// controller node so wiring looks and behaves identically everywhere.
class PinDot extends StatelessWidget {
  const PinDot({
    super.key,
    required this.type,
    required this.highlighted,
    required this.faded,
    required this.onTap,
    required this.onLongPress,
    this.rowHeight = kPinRowHeight,
  });

  final PinType type;
  final bool highlighted;
  final bool faded;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
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
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: type.color,
                border: Border.all(
                  color: highlighted ? Colors.white : Colors.black54,
                  width: highlighted ? 2.5 : 1,
                ),
                boxShadow: highlighted
                    ? [
                        BoxShadow(
                          color: type.color.withValues(alpha: 0.8),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
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
