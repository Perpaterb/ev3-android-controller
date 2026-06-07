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

  /// Fractional (0-1) centre within the tab's stage, so the Run-mode
  /// renderer can scale the layout to any screen.
  Offset position;

  final Map<String, dynamic> config;

  /// Size multipliers, independent per axis (see
  /// [ControllerLayout.setControlScale]). Old saves stored one uniform
  /// 'scale' — it acts as the fallback for both.
  double get scaleX =>
      (config['scaleX'] as num?)?.toDouble() ??
      (config['scale'] as num?)?.toDouble() ??
      1.0;

  double get scaleY =>
      (config['scaleY'] as num?)?.toDouble() ??
      (config['scale'] as num?)?.toDouble() ??
      1.0;

  /// Whether the control's name is drawn on the Run screen.
  bool get showName => config['showName'] != false;

  /// Text size (in stage units) for display controls.
  double get displayTextSize =>
      (config['textSize'] as num?)?.toDouble() ?? 24.0;

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
            PinSpec('$id.value', '$name value', PinType.string),
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
  ControllerTab({
    required this.id,
    required this.name,
    this.landscape = true,
    List<ControllerControl>? controls,
  }) : controls = controls ?? [];

  final String id;
  String name;

  /// Screen orientation this page is designed for.
  bool landscape;

  final List<ControllerControl> controls;

  /// Width-to-height ratio of this tab's stage — shared by the designer
  /// miniature and the Run screen so layouts match exactly.
  double get aspect => landscape ? 16 / 9 : 9 / 16;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'landscape': landscape,
        'controls': controls.map((c) => c.toJson()).toList(),
      };

  factory ControllerTab.fromJson(Map<String, dynamic> json) => ControllerTab(
        id: json['id'] as String,
        name: json['name'] as String,
        landscape: json['landscape'] as bool? ?? true,
        controls: [
          for (final raw in (json['controls'] as List? ?? const []))
            ?ControllerControl.fromJson((raw as Map).cast<String, dynamic>()),
        ],
      );
}

/// Largest size of the given aspect ratio that fits inside [available].
Size fitAspect(Size available, double aspect) {
  var width = available.width;
  var height = width / aspect;
  if (height > available.height) {
    height = available.height;
    width = height * aspect;
  }
  return Size(width, height);
}

/// The virtual stage is 800x450 units (450x800 in portrait). Control sizes
/// are defined in these units and multiplied by `stage.width / unitsWidth`,
/// so a control occupies the SAME fraction of the stage in the designer
/// miniature and on the Run screen, whatever their pixel sizes.
const double kStageUnitsLong = 800;
const double kStageUnitsShort = 450;

double stageUnitsWidth(bool landscape) =>
    landscape ? kStageUnitsLong : kStageUnitsShort;

/// Control footprint in stage units (before the per-control size slider).
Size controlBaseSize(ControlKind kind) => switch (kind) {
      ControlKind.button => const Size(120, 64),
      ControlKind.slider => const Size(240, 76),
      ControlKind.toggle => const Size(110, 72),
      ControlKind.dpad => const Size(168, 168),
      ControlKind.light => const Size(80, 76),
      ControlKind.display => const Size(130, 80),
    };

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

  void setTabOrientation(String id, {required bool landscape}) {
    final tab = _tabs.where((t) => t.id == id).firstOrNull;
    if (tab == null || tab.landscape == landscape) return;
    tab.landscape = landscape;
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

  /// Sets a control's size multipliers, clamped to 50%–200% per axis.
  /// Displays may go much wider — up to 5x (~80% of the stage width).
  void setControlScale(String id, {double? x, double? y}) {
    final target = control(id);
    if (target == null) return;
    final maxX = target.kind == ControlKind.display ? 5.0 : 2.0;
    if (x != null) target.config['scaleX'] = x.clamp(0.5, maxX);
    if (y != null) target.config['scaleY'] = y.clamp(0.5, 2.0);
    notifyListeners();
  }

  /// Text size for a display control, clamped to 12–40 stage units.
  void setDisplayTextSize(String id, double size) {
    final target = control(id);
    if (target == null) return;
    target.config['textSize'] = size.clamp(12.0, 40.0);
    notifyListeners();
  }

  void setControlShowName(String id, bool show) {
    final target = control(id);
    if (target == null) return;
    target.config['showName'] = show;
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
