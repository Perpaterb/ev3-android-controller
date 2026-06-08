import 'package:flutter/material.dart';

import '../model/node_def.dart';
import '../model/pins.dart';
import '../model/variables.dart';

/// What the user picked from the add-node sheet.
sealed class AddNodeChoice {
  const AddNodeChoice();
}

/// A normal catalog node.
class CatalogChoice extends AddNodeChoice {
  const CatalogChoice(this.def);
  final NodeDef def;
}

/// A Get or Set node for an existing variable.
class VariableChoice extends AddNodeChoice {
  const VariableChoice(this.variableId, {required this.isSetter});
  final String variableId;
  final bool isSetter;
}

/// "Make a new variable…".
class NewVariableChoice extends AddNodeChoice {
  const NewVariableChoice();
}

/// Bottom sheet listing nodes grouped and colour-coded by category.
///
/// [defs] narrows the catalog list (e.g. only nodes compatible with the wire
/// being drawn); [hint] explains the narrowing. When [defs] is null the
/// Variables section (Get/Set per variable + "make new") is shown too.
Future<AddNodeChoice?> showAddNodeSheet(
  BuildContext context, {
  List<NodeDef>? defs,
  String? hint,
  VariableSet? variables,
}) {
  final available = defs ?? nodeCatalog;
  final showVariables = defs == null;
  return showModalBottomSheet<AddNodeChoice>(
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
            if (showVariables)
              ..._buildVariables(context, variables),
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
    _header(context, category.color, category.label),
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
            onPressed: () => Navigator.pop(context, CatalogChoice(def)),
          ),
      ],
    ),
  ];
}

List<Widget> _buildVariables(BuildContext context, VariableSet? variables) {
  const color = Color(0xFFC79A2E); // NodeCategory.variable
  return [
    _header(context, color, 'Variables'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in variables?.variables ?? const []) ...[
          ActionChip(
            key: Key('add-get-${v.id}'),
            avatar: const Icon(Icons.south_west, size: 16),
            label: Text('Get ${v.name}'),
            backgroundColor: color.withValues(alpha: 0.15),
            side: const BorderSide(color: color),
            onPressed: () => Navigator.pop(
                context, VariableChoice(v.id, isSetter: false)),
          ),
          ActionChip(
            key: Key('add-set-${v.id}'),
            avatar: const Icon(Icons.north_east, size: 16),
            label: Text('Set ${v.name}'),
            backgroundColor: color.withValues(alpha: 0.15),
            side: const BorderSide(color: color),
            onPressed: () => Navigator.pop(
                context, VariableChoice(v.id, isSetter: true)),
          ),
        ],
        ActionChip(
          key: const Key('add-new-variable'),
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('New variable…'),
          onPressed: () => Navigator.pop(context, const NewVariableChoice()),
        ),
      ],
    ),
  ];
}

Widget _header(BuildContext context, Color color, String label) {
  return Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}
