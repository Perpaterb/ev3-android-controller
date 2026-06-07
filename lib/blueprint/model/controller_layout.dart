import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'node_def.dart';
import 'pins.dart';

/// The kinds of control a kid can place on their controller.
enum ControlKind {
  button('Button'),
  dpad('D-pad'),
  slider('Slider'),
  toggle('Toggle'),
  light('Light'),
  display('Display');

  const ControlKind(this.label);

  final String label;
}

/// One control on a controller tab. Its pins derive from its kind and the
/// name the user gave it; pin ids embed the control's id (not its name) so
/// renaming never breaks wires.
class ControllerControl {
  ControllerControl({
    required this.id,
    required this.kind,
    required this.name,
    required this.position,
    Map<String, dynamic>? config,
  }) : config = config ?? {};

  final String id;
  final ControlKind kind;
  String name;

  /// Fractional (0-1) centre within the tab area, so the Run-mode renderer
  /// can scale the layout to any screen.
  Offset position;

  final Map<String, dynamic> config;

  /// What this control *emits* — pins on the right of the controller node.
  List<PinSpec> get outputPins => switch (kind) {
        ControlKind.button => [
            PinSpec('$id.pressed', '$name pressed', PinType.power),
            PinSpec('$id.released', '$name released', PinType.power),
          ],
        ControlKind.dpad => [
            PinSpec('$id.up', '$name up', PinType.power),
            PinSpec('$id.down', '$name down', PinType.power),
            PinSpec('$id.left', '$name left', PinType.power),
            PinSpec('$id.right', '$name right', PinType.power),
            PinSpec('$id.released', '$name released', PinType.power),
          ],
        ControlKind.slider => [
            PinSpec('$id.value', name, PinType.integer),
            PinSpec('$id.changed', '$name changed', PinType.power),
          ],
        ControlKind.toggle => [
            PinSpec('$id.state', '$name?', PinType.boolean),
            PinSpec('$id.switched', '$name switched', PinType.power),
          ],
        ControlKind.light => const [],
        ControlKind.display => const [],
      };

  /// What this control *displays* — pins on the left of the controller node.
  List<PinSpec> get inputPins => switch (kind) {
        ControlKind.light => [
            PinSpec('$id.on', '$name on?', PinType.boolean),
          ],
        ControlKind.display => [
            PinSpec('$id.value', '$name value', PinType.integer),
          ],
        _ => const [],
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'x': position.dx,
        'y': position.dy,
        'config': config,
      };

  static ControllerControl? fromJson(Map<String, dynamic> json) {
    final kind = ControlKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    if (kind == null) return null; // control kind from a newer app version
    return ControllerControl(
      id: json['id'] as String,
      kind: kind,
      name: json['name'] as String,
      position: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      config: (json['config'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

/// One page of controls.
class ControllerTab {
  ControllerTab({required this.id, required this.name,
      List<ControllerControl>? controls})
      : controls = controls ?? [];

  final String id;
  String name;
  final List<ControllerControl> controls;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'controls': controls.map((c) => c.toJson()).toList(),
      };

  factory ControllerTab.fromJson(Map<String, dynamic> json) => ControllerTab(
        id: json['id'] as String,
        name: json['name'] as String,
        controls: [
          for (final raw in (json['controls'] as List? ?? const []))
            ?ControllerControl.fromJson((raw as Map).cast<String, dynamic>()),
        ],
      );
}

/// The whole controller design: tabs of controls. Always has at least one
/// tab. Lives in `project.controller` and is the source of truth for the
/// controller node's pins ([buildNodeDef]) and the Run-mode UI.
class ControllerLayout extends ChangeNotifier {
  ControllerLayout() {
    _tabs.add(ControllerTab(id: _newId('t'), name: 'Main'));
  }

  factory ControllerLayout.fromJson(Map<String, dynamic> json) {
    final layout = ControllerLayout();
    final tabs = [
      for (final raw in (json['tabs'] as List? ?? const []))
        ControllerTab.fromJson((raw as Map).cast<String, dynamic>()),
    ];
    if (tabs.isNotEmpty) {
      layout._tabs
        ..clear()
        ..addAll(tabs);
    }
    return layout;
  }

  final List<ControllerTab> _tabs = [];
  int _seq = 0;

  List<ControllerTab> get tabs => List.unmodifiable(_tabs);

  String _newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_seq++}';

  Iterable<ControllerControl> get _allControls =>
      _tabs.expand((t) => t.controls);

  ControllerControl? control(String id) =>
      _allControls.where((c) => c.id == id).firstOrNull;

  /// First unused "Button N"-style name for the new-control dialog.
  String defaultControlName(ControlKind kind) {
    final taken = _allControls.map((c) => c.name).toSet();
    var n = 1;
    while (taken.contains('${kind.label} $n')) {
      n++;
    }
    return '${kind.label} $n';
  }

  // ---- tabs ----

  ControllerTab addTab(String name) {
    final tab = ControllerTab(id: _newId('t'), name: name.trim());
    _tabs.add(tab);
    notifyListeners();
    return tab;
  }

  void renameTab(String id, String name) {
    final tab = _tabs.where((t) => t.id == id).firstOrNull;
    if (tab == null || name.trim().isEmpty) return;
    tab.name = name.trim();
    notifyListeners();
  }

  /// Refuses to remove the last tab — a controller always has one page.
  bool removeTab(String id) {
    if (_tabs.length <= 1) return false;
    final removed = _tabs.where((t) => t.id == id).firstOrNull;
    if (removed == null) return false;
    _tabs.remove(removed);
    notifyListeners();
    return true;
  }

  // ---- controls ----

  ControllerControl addControl({
    required String tabId,
    required ControlKind kind,
    required String name,
    required Offset position,
  }) {
    final tab = _tabs.firstWhere((t) => t.id == tabId);
    final control = ControllerControl(
      id: _newId('c'),
      kind: kind,
      name: name.trim(),
      position: _clampFraction(position),
      config: kind == ControlKind.slider ? {'min': 0, 'max': 100} : null,
    );
    tab.controls.add(control);
    notifyListeners();
    return control;
  }

  void renameControl(String id, String name) {
    final target = control(id);
    if (target == null || name.trim().isEmpty) return;
    target.name = name.trim();
    notifyListeners();
  }

  void removeControl(String id) {
    for (final tab in _tabs) {
      if (tab.controls.any((c) => c.id == id)) {
        tab.controls.removeWhere((c) => c.id == id);
        notifyListeners();
        return;
      }
    }
  }

  void moveControl(String id, Offset fractionalDelta) {
    final target = control(id);
    if (target == null) return;
    target.position = _clampFraction(target.position + fractionalDelta);
    notifyListeners();
  }

  static Offset _clampFraction(Offset p) =>
      Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));

  // ---- derived ----

  /// The controller node's pin set: every control capability across every
  /// tab. Lights (displays) become inputs on the left; everything the kid
  /// can press or move becomes outputs on the right.
  NodeDef buildNodeDef() => NodeDef(
        id: kControllerDefId,
        title: 'Controller',
        category: NodeCategory.controller,
        inputs: [for (final c in _allControls) ...c.inputPins],
        outputs: [for (final c in _allControls) ...c.outputPins],
      );

  Map<String, dynamic> toJson() => {
        'tabs': _tabs.map((t) => t.toJson()).toList(),
      };
}
