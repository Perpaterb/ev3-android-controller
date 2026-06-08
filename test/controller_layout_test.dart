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

  test('a button contributes touched, released and held power outputs', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Forward',
      position: const Offset(0.5, 0.5),
    );
    final def = layout.buildNodeDef();
    expect(def.outputs.map((p) => p.label),
        ['Forward touched', 'Forward released', 'Forward down']);
    expect(def.outputs.map((p) => p.id), [
      '${control.id}.pressed', // press pin keeps its old id for save-compat
      '${control.id}.released',
      '${control.id}.isDown',
    ]);
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

  test('a d-pad contributes touched, released and held per direction', () {
    layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.dpad,
      name: 'Drive',
      position: const Offset(0.5, 0.5),
    );
    final outputs = layout.buildNodeDef().outputs;
    expect(outputs, hasLength(12)); // 4 directions × 3 pins
    expect(
      outputs.map((p) => p.label),
      containsAll(['Drive left', 'Drive left released', 'Drive left held']),
    );
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

  test('disabling a capability removes its pin and persists', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Go',
      position: const Offset(0.5, 0.5),
    );
    // All three button pins by default.
    expect(layout.buildNodeDef().outputs, hasLength(3));
    expect(control.capabilities.map((c) => c.suffix),
        ['pressed', 'released', 'isDown']);

    layout.setCapabilityEnabled(control.id, 'released', false);
    layout.setCapabilityEnabled(control.id, 'isDown', false);
    final pins = layout.buildNodeDef().outputs;
    expect(pins, hasLength(1));
    expect(pins.single.label, 'Go touched');

    final copy = ControllerLayout.fromJson(layout.toJson());
    expect(copy.control(control.id)!.outputPins, hasLength(1));
    // Re-enabling brings it back.
    copy.setCapabilityEnabled(control.id, 'released', true);
    expect(copy.control(control.id)!.outputPins, hasLength(2));
  });

  test('slider default and show-value persist; default clamps to range', () {
    final slider = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.slider,
      name: 'Speed',
      position: const Offset(0.5, 0.5),
    );
    expect(slider.sliderDefault, 0); // defaults to min
    expect(slider.showValue, isTrue);

    layout.setSliderDefault(slider.id, 50);
    layout.setControlShowValue(slider.id, false);
    layout.setSliderDefault(slider.id, 999); // clamps to max
    expect(slider.sliderDefault, 100);
    layout.setSliderDefault(slider.id, 40);

    final copy = ControllerLayout.fromJson(layout.toJson());
    final copied = copy.control(slider.id)!;
    expect(copied.sliderDefault, 40);
    expect(copied.showValue, isFalse);
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
    expect(def.outputs.first.label, 'Go touched');
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
    expect(layout.buildNodeDef().outputs, hasLength(6)); // 2 buttons × 3
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

  test('control scales default to 1, clamp, set per axis, and persist', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Go',
      position: const Offset(0.5, 0.5),
    );
    expect(control.scaleX, 1.0);
    expect(control.scaleY, 1.0);

    layout.setControlScale(control.id, x: 1.5);
    expect(control.scaleX, 1.5);
    expect(control.scaleY, 1.0); // axes are independent
    layout.setControlScale(control.id, y: 99);
    expect(control.scaleY, 2.0);
    layout.setControlScale(control.id, x: 0.1);
    expect(control.scaleX, 0.5);

    final copy = ControllerLayout.fromJson(layout.toJson());
    expect(copy.control(control.id)!.scaleX, 0.5);
    expect(copy.control(control.id)!.scaleY, 2.0);
  });

  test('a legacy uniform scale feeds both axes', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: 'Go',
      position: const Offset(0.5, 0.5),
    );
    control.config['scale'] = 1.5; // written by an older app version
    expect(control.scaleX, 1.5);
    expect(control.scaleY, 1.5);
  });

  test('display text size defaults, clamps and persists', () {
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.display,
      name: 'Readout',
      position: const Offset(0.5, 0.5),
    );
    expect(control.displayTextSize, 24.0);
    layout.setDisplayTextSize(control.id, 99);
    expect(control.displayTextSize, 40.0);
    layout.setDisplayTextSize(control.id, 32);

    final copy = ControllerLayout.fromJson(layout.toJson());
    expect(copy.control(control.id)!.displayTextSize, 32.0);
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
