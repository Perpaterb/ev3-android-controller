import 'dart:ui' show Size;

import 'package:ev3_controller/blueprint/model/controller_layout.dart';
import 'package:ev3_controller/blueprint/model/pins.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ControllerLayout layout;

  setUp(() => layout = ControllerLayout());

  test('a new layout has one tab and no pins', () {
    expect(layout.tabs, hasLength(1));
    expect(layout.tabs.single.name, 'Main');
    final def = layout.buildNodeDef();
    expect(def.inputs, isEmpty);
    expect(def.outputs, isEmpty);
  });

  test('a button contributes pressed and released power outputs', () {
    layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Forward',
      position: const Offset(0.5, 0.5),
    );
    final def = layout.buildNodeDef();
    expect(def.outputs.map((p) => p.label),
        ['Forward pressed', 'Forward released']);
    expect(def.outputs.every((p) => p.type == PinType.power), isTrue);
    expect(def.inputs, isEmpty);
  });

  test('a slider contributes an int value and a changed power output', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.slider,
      name: 'Speed',
      position: const Offset(0.5, 0.5),
    );
    expect(control.config, {'min': 0, 'max': 100});
    final def = layout.buildNodeDef();
    expect(def.outputs.map((p) => p.type),
        [PinType.integer, PinType.power]);
  });

  test('a toggle contributes a bool state and a switched power output', () {
    layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.toggle,
      name: 'Lights',
      position: const Offset(0.5, 0.5),
    );
    final def = layout.buildNodeDef();
    expect(
        def.outputs.map((p) => p.type), [PinType.boolean, PinType.power]);
  });

  test('a d-pad contributes four directions plus released', () {
    layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.dpad,
      name: 'Drive',
      position: const Offset(0.5, 0.5),
    );
    expect(layout.buildNodeDef().outputs, hasLength(5));
  });

  test('a light is an input on the controller node', () {
    layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.light,
      name: 'Bump',
      position: const Offset(0.5, 0.5),
    );
    final def = layout.buildNodeDef();
    expect(def.outputs, isEmpty);
    expect(def.inputs.single.label, 'Bump on?');
    expect(def.inputs.single.type, PinType.boolean);
  });

  test('a display is a string input on the controller node', () {
    layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.display,
      name: 'Speed',
      position: const Offset(0.5, 0.5),
    );
    final def = layout.buildNodeDef();
    expect(def.outputs, isEmpty);
    expect(def.inputs.single.label, 'Speed value');
    expect(def.inputs.single.type, PinType.string);
  });

  test('showName defaults to true and persists when switched off', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Go',
      position: const Offset(0.5, 0.5),
    );
    expect(control.showName, isTrue);
    layout.setControlShowName(control.id, false);
    expect(control.showName, isFalse);

    final copy = ControllerLayout.fromJson(layout.toJson());
    expect(copy.control(control.id)!.showName, isFalse);
  });

  test('renaming a control changes labels but not pin ids', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Forward',
      position: const Offset(0.5, 0.5),
    );
    final idsBefore = layout.buildNodeDef().outputs.map((p) => p.id).toList();
    layout.renameControl(control.id, 'Go');
    final def = layout.buildNodeDef();
    expect(def.outputs.map((p) => p.id), idsBefore);
    expect(def.outputs.first.label, 'Go pressed');
  });

  test('removing a control removes its pins', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Forward',
      position: const Offset(0.5, 0.5),
    );
    layout.removeControl(control.id);
    expect(layout.buildNodeDef().outputs, isEmpty);
  });

  test('moveControl clamps to the tab area', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Forward',
      position: const Offset(0.9, 0.9),
    );
    layout.moveControl(control.id, const Offset(0.5, -2));
    expect(control.position, const Offset(1, 0));
  });

  test('pins from every tab appear on the node', () {
    layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'A',
      position: const Offset(0.5, 0.5),
    );
    final second = layout.addTab('Arm');
    layout.addControl(
      tabId: second.id,
      kind: ControlKind.button,
      name: 'B',
      position: const Offset(0.5, 0.5),
    );
    expect(layout.buildNodeDef().outputs, hasLength(4));
  });

  test('the last tab cannot be removed', () {
    expect(layout.removeTab(layout.tabs.single.id), isFalse);
    expect(layout.tabs, hasLength(1));

    final second = layout.addTab('Arm');
    expect(layout.removeTab(second.id), isTrue);
    expect(layout.removeTab(layout.tabs.single.id), isFalse);
  });

  test('default control names count up per kind', () {
    expect(layout.defaultControlName(ControlKind.button), 'Button 1');
    layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Button 1',
      position: const Offset(0.5, 0.5),
    );
    expect(layout.defaultControlName(ControlKind.button), 'Button 2');
    expect(layout.defaultControlName(ControlKind.slider), 'Slider 1');
  });

  test('tabs default to landscape; orientation flips and persists', () {
    final tab = layout.tabs.single;
    expect(tab.landscape, isTrue);
    expect(tab.aspect, greaterThan(1));

    layout.setTabOrientation(tab.id, landscape: false);
    expect(tab.landscape, isFalse);
    expect(tab.aspect, lessThan(1));

    final copy = ControllerLayout.fromJson(layout.toJson());
    expect(copy.tabs.single.landscape, isFalse);
  });

  test('control scale defaults to 1, clamps, and persists', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Go',
      position: const Offset(0.5, 0.5),
    );
    expect(control.scale, 1.0);

    layout.setControlScale(control.id, 1.5);
    expect(control.scale, 1.5);
    layout.setControlScale(control.id, 99);
    expect(control.scale, 2.0);
    layout.setControlScale(control.id, 0.1);
    expect(control.scale, 0.5);

    layout.setControlScale(control.id, 1.5);
    final copy = ControllerLayout.fromJson(layout.toJson());
    expect(copy.control(control.id)!.scale, 1.5);
  });

  test('fitAspect letterboxes to the limiting dimension', () {
    expect(fitAspect(const Size(160, 1000), 16 / 9),
        const Size(160, 90)); // width-limited
    expect(fitAspect(const Size(1000, 90), 16 / 9),
        const Size(160, 90)); // height-limited
    final portrait = fitAspect(const Size(1000, 160), 9 / 16);
    expect(portrait.height, 160);
    expect(portrait.width, 90);
  });

  test('JSON round-trips tabs, controls, names and config', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.slider,
      name: 'Speed',
      position: const Offset(0.25, 0.75),
    );
    layout.addTab('Arm');

    final copy = ControllerLayout.fromJson(layout.toJson());
    expect(copy.tabs, hasLength(2));
    expect(copy.tabs[1].name, 'Arm');
    final controlCopy = copy.control(control.id)!;
    expect(controlCopy.kind, ControlKind.slider);
    expect(controlCopy.name, 'Speed');
    expect(controlCopy.position, const Offset(0.25, 0.75));
    expect(controlCopy.config['max'], 100);
  });

  test('fromJson of an empty map gives the default single tab', () {
    final copy = ControllerLayout.fromJson(const {});
    expect(copy.tabs, hasLength(1));
  });
}
