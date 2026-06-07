import 'package:flutter/material.dart';

import '../model/controller_layout.dart';

/// Bottom sheet asking which kind of control to add to the controller.
/// Returns the chosen [ControlKind], or null if dismissed.
Future<ControlKind?> showAddControlSheet(BuildContext context) {
  return showModalBottomSheet<ControlKind>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text('Add a control',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final kind in ControlKind.values)
            ListTile(
              key: Key('add-control-${kind.name}'),
              leading: Icon(_iconFor(kind)),
              title: Text(kind.label),
              subtitle: Text(_describe(kind)),
              onTap: () => Navigator.pop(context, kind),
            ),
        ],
      ),
    ),
  );
}

IconData _iconFor(ControlKind kind) => switch (kind) {
      ControlKind.button => Icons.radio_button_checked,
      ControlKind.dpad => Icons.control_camera,
      ControlKind.slider => Icons.tune,
      ControlKind.toggle => Icons.toggle_on,
      ControlKind.light => Icons.lightbulb_outline,
      ControlKind.display => Icons.pin_outlined,
    };

String _describe(ControlKind kind) => switch (kind) {
      ControlKind.button => 'Fires power while held',
      ControlKind.dpad => 'Four direction buttons in one',
      ControlKind.slider => 'Picks a number (0–100)',
      ControlKind.toggle => 'Switches between yes and no',
      ControlKind.light => 'Shows a yes/no from your robot',
      ControlKind.display => 'Shows a number from your robot',
    };
