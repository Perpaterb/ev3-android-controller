import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../model/graph.dart';
import '../model/node_def.dart';
import '../model/pins.dart';
import '../node_geometry.dart';
import 'node_chrome.dart';

/// One node on the canvas: category-coloured header (drag handle + label),
/// pin rows (inputs left, outputs right), and an optional config row (EV3
/// port picker or constant value).
///
/// Purely presentational — selection, wiring state and all mutations live in
/// the editor and arrive via callbacks.
class NodeWidget extends StatelessWidget {
  const NodeWidget({
    super.key,
    required this.node,
    required this.selected,
    required this.dimmed,
    required this.wiringActive,
    required this.pinHighlighted,
    required this.pinConnected,
    required this.pinLinked,
    required this.onSelect,
    required this.onMoveBy,
    required this.onRename,
    required this.onDelete,
    required this.onTapPin,
    required this.onLongPressPin,
    required this.onConfigChanged,
  });

  final GraphNode node;
  final bool selected;

  /// Greyed out during wiring mode when no pin here can take the wire.
  final bool dimmed;
  final bool wiringActive;
  final bool Function(PinRef ref) pinHighlighted;
  final bool Function(PinRef ref) pinConnected;
  final bool Function(PinRef ref) pinLinked;

  final VoidCallback onSelect;
  final void Function(Offset canvasDelta) onMoveBy;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(PinRef ref) onTapPin;
  final void Function(PinRef ref) onLongPressPin;
  final void Function(String key, Object value) onConfigChanged;

  static const Color _bodyColor = Color(0xFF2B313A);
  static const TextStyle _pinLabelStyle =
      TextStyle(color: Colors.white70, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final def = node.def;
    return Opacity(
      opacity: dimmed ? 0.3 : 1,
      child: GestureDetector(
        // Absorb taps so tapping a node never falls through to the canvas
        // (which would clear selection / cancel wiring).
        behavior: HitTestBehavior.opaque,
        onTap: onSelect,
        child: Container(
          width: kNodeWidth,
          decoration: BoxDecoration(
            color: _bodyColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.white : Colors.black45,
              width: selected ? 2 : 1,
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 6),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(def),
              for (var i = 0; i < pinRowCount(def); i++) _buildPinRow(def, i),
              if (def.configKind != NodeConfigKind.none)
                _buildConfigRow(context, def),
              const SizedBox(height: kNodeBottomPadding),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(NodeDef def) {
    return GestureDetector(
      key: Key('node-header-${node.id}'),
      behavior: HitTestBehavior.opaque,
      // Deltas count from finger-down, so the node tracks the finger from
      // the first pixel instead of jumping after the slop distance.
      dragStartBehavior: DragStartBehavior.down,
      onTap: onSelect,
      onPanStart: (_) => onSelect(),
      onPanUpdate: (details) => onMoveBy(details.delta),
      child: Container(
        height: kNodeHeaderHeight,
        decoration: BoxDecoration(
          color: def.category.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                node.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            if (selected) ...[
              NodeHeaderButton(
                key: Key('node-edit-${node.id}'),
                icon: Icons.edit,
                onTap: onRename,
              ),
              const SizedBox(width: 2),
              NodeHeaderButton(
                key: Key('node-delete-${node.id}'),
                icon: Icons.delete,
                onTap: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPinRow(NodeDef def, int index) {
    final input = index < def.inputs.length ? def.inputs[index] : null;
    final output = index < def.outputs.length ? def.outputs[index] : null;
    return SizedBox(
      height: kPinRowHeight,
      child: Row(
        children: [
          if (input != null)
            _buildPin(input, isOutput: false)
          else
            const SizedBox(width: 2 * kPinInset),
          if (input != null)
            Expanded(child: Text(input.label, style: _pinLabelStyle))
          else
            const Spacer(),
          if (output != null)
            Expanded(
              child: Text(output.label,
                  textAlign: TextAlign.right, style: _pinLabelStyle),
            ),
          if (output != null)
            _buildPin(output, isOutput: true)
          else
            const SizedBox(width: 2 * kPinInset),
        ],
      ),
    );
  }

  Widget _buildPin(PinSpec spec, {required bool isOutput}) {
    final ref = PinRef(node.id, spec.id, isOutput: isOutput);
    final highlighted = pinHighlighted(ref);
    final linked = pinLinked(ref);
    return PinDot(
      key: Key('pin-${node.id}-${spec.id}-${isOutput ? 'out' : 'in'}'),
      type: spec.type,
      highlighted: highlighted,
      linked: linked,
      connected: pinConnected(ref),
      faded: wiringActive && !highlighted && !linked,
      onTap: () => onTapPin(ref),
      onLongPress: () => onLongPressPin(ref),
    );
  }

  Widget _buildConfigRow(BuildContext context, NodeDef def) {
    final child = switch (def.configKind) {
      NodeConfigKind.motorPort ||
      NodeConfigKind.sensorPort =>
        _buildPortPicker(def),
      NodeConfigKind.intValue => _buildIntValue(context),
      NodeConfigKind.boolValue => _buildBoolValue(),
      NodeConfigKind.stringValue => _buildStringValue(context),
      NodeConfigKind.none => const SizedBox.shrink(),
    };
    return SizedBox(
      height: kNodeConfigHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      ),
    );
  }

  Widget _buildPortPicker(NodeDef def) {
    final choices = def.portChoices!;
    final current = node.config['port'] as String? ?? choices.first;
    return Row(
      children: [
        const Text('Port', style: _pinLabelStyle),
        const Spacer(),
        DropdownButton<String>(
          key: Key('node-port-${node.id}'),
          value: choices.contains(current) ? current : choices.first,
          dropdownColor: _bodyColor,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          underline: const SizedBox.shrink(),
          isDense: true,
          items: [
            for (final choice in choices)
              DropdownMenuItem(value: choice, child: Text(choice)),
          ],
          onChanged: (value) {
            if (value != null) onConfigChanged('port', value);
          },
        ),
      ],
    );
  }

  Widget _buildIntValue(BuildContext context) {
    final value = node.config['value'] as int? ?? 0;
    return Row(
      children: [
        Text(node.def.configLabel ?? 'Value', style: _pinLabelStyle),
        const Spacer(),
        GestureDetector(
          key: Key('node-value-${node.id}'),
          onTap: () => _editIntValue(context, value),
          child: Text(
            '$value',
            style: TextStyle(
              color: PinType.integer.color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editIntValue(BuildContext context, int current) async {
    final controller = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        void submit() {
          final parsed = int.tryParse(controller.text.trim());
          if (parsed != null) Navigator.pop(context, parsed);
        }

        return AlertDialog(
          title: const Text('Set number'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: const Text('Set')),
          ],
        );
      },
    );
    if (result != null) onConfigChanged('value', result);
  }

  Widget _buildStringValue(BuildContext context) {
    final value = node.config['value'] as String? ?? '';
    return Row(
      children: [
        const Text('Text', style: _pinLabelStyle),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            key: Key('node-value-${node.id}'),
            onTap: () => _editStringValue(context, value),
            child: Text(
              value.isEmpty ? 'tap to type…' : '"$value"',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: value.isEmpty
                    ? Colors.white38
                    : PinType.string.color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editStringValue(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        void submit() => Navigator.pop(context, controller.text);

        return AlertDialog(
          title: const Text('Set text'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: const Text('Set')),
          ],
        );
      },
    );
    if (result != null) onConfigChanged('value', result);
  }

  Widget _buildBoolValue() {
    final value = node.config['value'] == true;
    return Row(
      children: [
        Text(node.def.configLabel ?? 'Value', style: _pinLabelStyle),
        const Spacer(),
        Switch(
          key: Key('node-value-${node.id}'),
          value: value,
          activeTrackColor: PinType.boolean.color,
          onChanged: (v) => onConfigChanged('value', v),
        ),
      ],
    );
  }
}

