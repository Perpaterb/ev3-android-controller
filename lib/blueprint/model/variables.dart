import 'package:flutter/foundation.dart';

import 'node_def.dart';
import 'pins.dart';

/// The data type a variable holds, and the pin it produces.
enum VarType {
  integer('Number', PinType.integer),
  boolean('Yes / No', PinType.boolean),
  text('Text', PinType.string);

  const VarType(this.label, this.pinType);

  final String label;
  final PinType pinType;
}

/// A named, typed value a project can store and reuse with Get/Set nodes.
class ProjectVariable {
  ProjectVariable({required this.id, required this.name, required this.type});

  final String id;
  String name;
  final VarType type;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': type.name};

  static ProjectVariable? fromJson(Map<String, dynamic> json) {
    final type =
        VarType.values.where((t) => t.name == json['type']).firstOrNull;
    if (type == null) return null;
    return ProjectVariable(
      id: json['id'] as String,
      name: json['name'] as String,
      type: type,
    );
  }
}

const String kVarGetDefId = 'var.get';
const String kVarSetDefId = 'var.set';

/// The Get node for [v]: one typed output carrying the variable's value.
NodeDef varGetDef(ProjectVariable v) => NodeDef(
      id: kVarGetDefId,
      title: 'Get ${v.name}',
      category: NodeCategory.variable,
      outputs: [PinSpec('value', v.name, v.type.pinType)],
    );

/// The Set node for [v]: power in writes the typed value, power out continues.
NodeDef varSetDef(ProjectVariable v) => NodeDef(
      id: kVarSetDefId,
      title: 'Set ${v.name}',
      category: NodeCategory.variable,
      inputs: [
        PinSpec('set', 'Set', PinType.power),
        PinSpec('value', v.name, v.type.pinType),
      ],
      outputs: [PinSpec('then', 'Then', PinType.power)],
    );

/// The project's variables. Lives in `project.variables`; the source of
/// truth for Get/Set node pins.
class VariableSet extends ChangeNotifier {
  VariableSet();

  factory VariableSet.fromJson(Map<String, dynamic> json) {
    final set = VariableSet();
    for (final raw in (json['variables'] as List? ?? const [])) {
      final v = ProjectVariable.fromJson((raw as Map).cast<String, dynamic>());
      if (v != null) set._variables.add(v);
    }
    return set;
  }

  final List<ProjectVariable> _variables = [];
  int _seq = 0;

  List<ProjectVariable> get variables => List.unmodifiable(_variables);

  ProjectVariable? byId(String id) =>
      _variables.where((v) => v.id == id).firstOrNull;

  String defaultName(VarType type) {
    final taken = _variables.map((v) => v.name).toSet();
    var n = 1;
    while (taken.contains('${type.label} $n')) {
      n++;
    }
    return '${type.label} $n';
  }

  ProjectVariable create(String name, VarType type) {
    final variable = ProjectVariable(
      id: 'v${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '-${_seq++}',
      name: name.trim(),
      type: type,
    );
    _variables.add(variable);
    notifyListeners();
    return variable;
  }

  void rename(String id, String name) {
    final variable = byId(id);
    if (variable == null || name.trim().isEmpty) return;
    variable.name = name.trim();
    notifyListeners();
  }

  void remove(String id) {
    final before = _variables.length;
    _variables.removeWhere((v) => v.id == id);
    if (_variables.length != before) notifyListeners();
  }

  Map<String, dynamic> toJson() =>
      {'variables': _variables.map((v) => v.toJson()).toList()};
}
