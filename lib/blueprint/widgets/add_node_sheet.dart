import 'package:flutter/material.dart';

import '../model/node_def.dart';
import '../model/pins.dart';

/// Bottom sheet listing nodes grouped and colour-coded by category.
/// Returns the chosen [NodeDef], or null if dismissed.
///
/// [defs] narrows the list (e.g. only nodes compatible with the wire being
/// drawn); [hint] explains the narrowing to the user.
Future<NodeDef?> showAddNodeSheet(
  BuildContext context, {
  List<NodeDef>? defs,
  String? hint,
}) {
  final available = defs ?? nodeCatalog;
  return showModalBottomSheet<NodeDef>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('Add a node',
                style: Theme.of(context).textTheme.titleLarge),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            if (available.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Nothing in the toolbox can connect to that pin.'),
              ),
            for (final category in NodeCategory.values)
              ..._buildCategory(context, category, available),
          ],
        ),
      ),
    ),
  );
}

List<Widget> _buildCategory(
    BuildContext context, NodeCategory category, List<NodeDef> available) {
  final defs = available.where((d) => d.category == category).toList();
  if (defs.isEmpty) return const [];
  return [
    Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: category.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(category.label,
              style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    ),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final def in defs)
          ActionChip(
            key: Key('add-node-${def.id}'),
            label: Text(def.title),
            backgroundColor: category.color.withValues(alpha: 0.15),
            side: BorderSide(color: category.color),
            onPressed: () => Navigator.pop(context, def),
          ),
      ],
    ),
  ];
}
