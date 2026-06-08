import 'package:ev3_controller/blueprint/model/graph.dart';
import 'package:ev3_controller/blueprint/model/node_def.dart';
import 'package:ev3_controller/blueprint/model/pins.dart';
import 'package:ev3_controller/blueprint/model/variables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VariableSet', () {
    test('create assigns a type and persists', () {
      final vars = VariableSet();
      final score = vars.create('Score', VarType.integer);
      expect(score.type, VarType.integer);
      expect(vars.variables, hasLength(1));

      final copy = VariableSet.fromJson(vars.toJson());
      expect(copy.variables.single.name, 'Score');
      expect(copy.variables.single.type, VarType.integer);
    });

    test('default names count up per type', () {
      final vars = VariableSet();
      expect(vars.defaultName(VarType.integer), 'Number 1');
      vars.create('Number 1', VarType.integer);
      expect(vars.defaultName(VarType.integer), 'Number 2');
      expect(vars.defaultName(VarType.text), 'Text 1');
    });

    test('get and set defs carry the variable type', () {
      final v = ProjectVariable(
          id: 'v1', name: 'Score', type: VarType.integer);
      expect(varGetDef(v).outputs.single.type, PinType.integer);
      expect(varSetDef(v).inputs[1].type, PinType.integer);
      expect(varSetDef(v).inputs.first.type, PinType.power); // the Set pin
    });
  });

  group('graph variable nodes', () {
    test('applyVariableDefs resolves get/set node pins', () {
      final vars = VariableSet();
      final score = vars.create('Score', VarType.integer);
      final graph = BlueprintGraph();
      final getNode =
          graph.addDynamicNode(varGetDef(score), Offset.zero, {'var': score.id});
      graph.applyVariableDefs(vars);
      expect(graph.node(getNode.id)!.def.outputs.single.type,
          PinType.integer);
    });

    test('deleting a variable removes its nodes and wires', () {
      final vars = VariableSet();
      final score = vars.create('Score', VarType.integer);
      final graph = BlueprintGraph();
      final getNode =
          graph.addDynamicNode(varGetDef(score), Offset.zero, {'var': score.id});
      final add = graph.addNode(nodeDefById('math.add')!, Offset.zero);
      graph.connect(PinRef(getNode.id, 'value', isOutput: true),
          PinRef(add.id, 'a', isOutput: false));
      expect(graph.wires, hasLength(1));

      vars.remove(score.id);
      graph.applyVariableDefs(vars);
      expect(graph.node(getNode.id), isNull);
      expect(graph.wires, isEmpty);
    });

    test('get/set nodes and their wires survive a JSON reload', () {
      final vars = VariableSet();
      final score = vars.create('Score', VarType.integer);
      final graph = BlueprintGraph();
      final setNode =
          graph.addDynamicNode(varSetDef(score), Offset.zero, {'var': score.id});
      final number = graph.addNode(nodeDefById('value.int')!, Offset.zero);
      graph.connect(PinRef(number.id, 'value', isOutput: true),
          PinRef(setNode.id, 'value', isOutput: false));

      final copy = BlueprintGraph.fromJson(graph.toJson(), variables: vars);
      expect(copy.node(setNode.id), isNotNull);
      expect(copy.wires, hasLength(1));
    });

    test('without the variable set, get/set nodes are dropped on load', () {
      final vars = VariableSet();
      final score = vars.create('Score', VarType.integer);
      final graph = BlueprintGraph();
      graph.addDynamicNode(varGetDef(score), Offset.zero, {'var': score.id});

      final copy = BlueprintGraph.fromJson(graph.toJson());
      expect(copy.nodes.where((n) => n.defId == kVarGetDefId), isEmpty);
    });
  });
}
