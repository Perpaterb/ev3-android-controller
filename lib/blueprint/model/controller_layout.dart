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
  joystick('Joystick'),
  light('Light'),
  display('Display'),
  plotter('Plotter');

  const ControlKind(this.label);

  final String label;

  /// One-line summary of what this control sends/receives and its ranges,
  /// shown in the control's settings.
  String get rangeBlurb => switch (this) {
        ControlKind.button => 'Sends power when touched, held and released.',
        ControlKind.dpad => 'Each direction sends power (touched/held/released).',
        ControlKind.slider => 'Sends a number 0–100.',
        ControlKind.toggle => 'Sends yes / no, and power when switched.',
        ControlKind.joystick =>
          'Sends X and Y (−50 to +50), angle (0–359°) and distance (0–100).',
        ControlKind.light => 'Shows a colour (0–7) at a brightness (0–100).',
        ControlKind.display => 'Shows text.',
        ControlKind.plotter =>
          'Draws coloured dots (0–7) at X,Y points when given power.',
      };
}

/// Most dots a plotter may draw per render pulse.
const int kPlotterMaxDots = 10;

/// Total stored dots cap, to keep painting smooth.
const int kPlotterMaxStored = 2000;

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

  /// Whether a slider shows its current number on the Run screen.
  bool get showValue => config['showValue'] != false;

  // Slider range and starting value.
  int get sliderMin => (config['min'] as num?)?.toInt() ?? 0;
  int get sliderMax => (config['max'] as num?)?.toInt() ?? 100;
  int get sliderDefault =>
      (config['default'] as num?)?.toInt() ?? sliderHome;

  // Slider behaviour. Each of these is the *default* used when the matching
  // input pin isn't wired; the runner reads the wired pin first.
  bool get sliderVertical => config['vertical'] == true;
  int get sliderHome => (config['home'] as num?)?.toInt() ?? 50;
  bool get sliderPowered => config['powered'] == true;
  int get sliderStrength => (config['strength'] as num?)?.toInt() ?? 50;
  bool get sliderSprung => config['sprung'] == true;

  // Joysticks share the power options but default to powered + sprung (they
  // spring back to centre, 0,0).
  bool get joystickPowered => config['powered'] != false;
  int get joystickStrength => (config['strength'] as num?)?.toInt() ?? 50;
  bool get joystickSprung => config['sprung'] != false;

  /// Capability suffixes the user has switched off, so they make no pin on
  /// the controller node (declutter). e.g. {'isDown', 'released'}.
  Set<String> get hiddenCapabilities =>
      ((config['hidden'] as List?)?.cast<String>() ?? const []).toSet();

  bool capabilityEnabled(String suffix) =>
      !hiddenCapabilities.contains(suffix);

  /// Text size (in stage units) for display controls.
  double get displayTextSize =>
      (config['textSize'] as num?)?.toDouble() ?? 24.0;

  /// Whether a display draws its background box and border (off = just text).
  bool get displayFramed => config['framed'] != false;

  // Plotter settings. Dots-per-draw grows the X/Y/colour input pins; the
  // coordinate range is fixed (not auto-scaled).
  int get plotterDots =>
      ((config['dots'] as num?)?.toInt() ?? 1).clamp(1, kPlotterMaxDots);
  int get plotterClearAfter {
    final max = (kPlotterMaxStored ~/ plotterDots).clamp(1, kPlotterMaxStored);
    return ((config['clearAfter'] as num?)?.toInt() ?? 1).clamp(1, max);
  }

  int get plotterMinX => (config['minX'] as num?)?.toInt() ?? 0;
  int get plotterMaxX => (config['maxX'] as num?)?.toInt() ?? 100;
  int get plotterMinY => (config['minY'] as num?)?.toInt() ?? 0;
  int get plotterMaxY => (config['maxY'] as num?)?.toInt() ?? 100;

  /// Dot radius in stage units.
  double get plotterDotSize =>
      (config['dotSize'] as num?)?.toDouble() ?? 5.0;

  /// Every pin this control could emit, before the user's declutter
  /// choices. Momentary controls expose three power pins: `touched` fires
  /// once on press, `released` once on release, and `held` (pin id `isDown`)
  /// every tick while held — the UE5 model. (The press pin keeps its old id
  /// `pressed` so existing saved wires survive.)
  List<PinSpec> get _allOutputPins => switch (kind) {
        ControlKind.button => [
            PinSpec('$id.pressed', '$name touched', PinType.power),
            PinSpec('$id.released', '$name released', PinType.power),
            PinSpec('$id.isDown', '$name down', PinType.power),
          ],
        // Each direction is an independent button with its own touched,
        // released and held — hold "up" to drive while tapping left/right.
        // (The continuous pin stays "held" here, since "down" is also a
        // direction — "Drive down held" reads clearer than "Drive down down".)
        ControlKind.dpad => [
            for (final direction in const ['up', 'down', 'left', 'right']) ...[
              PinSpec('$id.$direction', '$name $direction', PinType.power),
              PinSpec('$id.${direction}Released',
                  '$name $direction released', PinType.power),
              PinSpec('$id.${direction}IsDown',
                  '$name $direction held', PinType.power),
            ],
          ],
        ControlKind.slider => [
            PinSpec('$id.value', name, PinType.integer),
            PinSpec('$id.changed', '$name changed', PinType.power),
          ],
        ControlKind.toggle => [
            PinSpec('$id.state', '$name?', PinType.boolean),
            PinSpec('$id.switched', '$name switched', PinType.power),
          ],
        // X/Y are −50..+50 (centre 0); angle 0-359° (0 at top, clockwise);
        // distance 0-100 from centre.
        ControlKind.joystick => [
            PinSpec('$id.x', '$name X', PinType.integer),
            PinSpec('$id.y', '$name Y', PinType.integer),
            PinSpec('$id.angle', '$name angle', PinType.integer),
            PinSpec('$id.distance', '$name distance', PinType.integer),
            PinSpec('$id.moved', '$name moved', PinType.power),
          ],
        ControlKind.light => const [],
        ControlKind.display => const [],
        ControlKind.plotter => const [],
      };

  List<PinSpec> get _allInputPins => switch (kind) {
        // Each slider setting can be driven by a pin or left to its option
        // default; "set" + "set to" jump the slider to a position on power.
        ControlKind.slider => [
            PinSpec('$id.home', '$name home', PinType.integer),
            PinSpec('$id.setPos', '$name set', PinType.power),
            PinSpec('$id.setValue', '$name set to', PinType.integer),
            PinSpec('$id.powered', '$name powered?', PinType.boolean),
            PinSpec('$id.strength', '$name strength', PinType.integer),
            PinSpec('$id.sprung', '$name sprung?', PinType.boolean),
          ],
        ControlKind.joystick => [
            PinSpec('$id.setPos', '$name set', PinType.power),
            PinSpec('$id.setX', '$name set X', PinType.integer),
            PinSpec('$id.setY', '$name set Y', PinType.integer),
            PinSpec('$id.powered', '$name powered?', PinType.boolean),
            PinSpec('$id.strength', '$name strength', PinType.integer),
            PinSpec('$id.sprung', '$name sprung?', PinType.boolean),
          ],
        // Colour follows the EV3 palette: 0 = off, 1 black, 2 blue, 3 green,
        // 4 yellow, 5 red, 6 white, 7 brown — so a colour sensor's reading
        // can wire straight in. Brightness is 0-100.
        ControlKind.light => [
            PinSpec('$id.colour', '$name colour', PinType.integer),
            PinSpec('$id.brightness', '$name brightness', PinType.integer),
          ],
        ControlKind.display => [
            PinSpec('$id.value', '$name value', PinType.string),
          ],
        // Render/clear power plus an X/Y/colour trio per dot. With one dot
        // the labels drop the number.
        ControlKind.plotter => [
            PinSpec('$id.render', '$name draw', PinType.power),
            PinSpec('$id.clear', '$name clear', PinType.power),
            for (var i = 0; i < plotterDots; i++) ...[
              PinSpec('$id.x$i',
                  plotterDots == 1 ? '$name X' : '$name X${i + 1}',
                  PinType.integer),
              PinSpec('$id.y$i',
                  plotterDots == 1 ? '$name Y' : '$name Y${i + 1}',
                  PinType.integer),
              PinSpec('$id.colour$i',
                  plotterDots == 1 ? '$name colour' : '$name colour${i + 1}',
                  PinType.integer),
            ],
          ],
        _ => const [],
      };

  String _suffix(String pinId) => pinId.substring(id.length + 1);

  /// Outputs the control actually exposes (hidden capabilities removed).
  List<PinSpec> get outputPins => _allOutputPins
      .where((p) => capabilityEnabled(_suffix(p.id)))
      .toList();

  /// Inputs the control actually exposes (hidden capabilities removed).
  List<PinSpec> get inputPins => _allInputPins
      .where((p) => capabilityEnabled(_suffix(p.id)))
      .toList();

  /// All capabilities (suffix + label + side) for the declutter menu, before
  /// filtering — so the user can toggle each one.
  List<({String suffix, String label, bool isInput})> get capabilities => [
        for (final p in _allOutputPins)
          (suffix: _suffix(p.id), label: p.label, isInput: false),
        for (final p in _allInputPins)
          (suffix: _suffix(p.id), label: p.label, isInput: true),
      ];

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
      ControlKind.joystick => const Size(180, 180),
      ControlKind.light => const Size(80, 76),
      ControlKind.display => const Size(130, 80),
      ControlKind.plotter => const Size(170, 170),
    };

/// Footprint for a specific control — vertical sliders stand tall.
Size controlBaseSizeFor(ControllerControl control) {
  final base = controlBaseSize(control.kind);
  if (control.kind == ControlKind.slider && control.sliderVertical) {
    return Size(base.height, base.width); // rotate to portrait
  }
  return base;
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
  /// Displays may go much wider, and plotters much wider AND taller, so they
  /// can fill most of the screen.
  void setControlScale(String id, {double? x, double? y}) {
    final target = control(id);
    if (target == null) return;
    final wide =
        target.kind == ControlKind.display || target.kind == ControlKind.plotter;
    final tall = target.kind == ControlKind.plotter;
    if (x != null) target.config['scaleX'] = x.clamp(0.5, wide ? 5.0 : 2.0);
    if (y != null) target.config['scaleY'] = y.clamp(0.5, tall ? 5.0 : 2.0);
    notifyListeners();
  }

  /// Text size for a display control, clamped to 12–40 stage units.
  void setDisplayTextSize(String id, double size) {
    final target = control(id);
    if (target == null) return;
    target.config['textSize'] = size.clamp(12.0, 40.0);
    notifyListeners();
  }

  void setDisplayFramed(String id, bool framed) {
    final target = control(id);
    if (target == null) return;
    target.config['framed'] = framed;
    notifyListeners();
  }

  void setControlShowName(String id, bool show) {
    final target = control(id);
    if (target == null) return;
    target.config['showName'] = show;
    notifyListeners();
  }

  void setControlShowValue(String id, bool show) {
    final target = control(id);
    if (target == null) return;
    target.config['showValue'] = show;
    notifyListeners();
  }

  /// Sets a slider's starting value, clamped to its range.
  void setSliderDefault(String id, int value) {
    final target = control(id);
    if (target == null) return;
    target.config['default'] =
        value.clamp(target.sliderMin, target.sliderMax);
    notifyListeners();
  }

  /// Sets a plotter config key (dots/clearAfter/minX/maxX/minY/maxY).
  void setPlotterConfig(String id, String key, int value) {
    final target = control(id);
    if (target == null) return;
    target.config[key] = switch (key) {
      'dots' => value.clamp(1, kPlotterMaxDots),
      'clearAfter' => value.clamp(1, kPlotterMaxStored),
      'dotSize' => value.clamp(1, 30),
      _ => value,
    };
    notifyListeners();
  }

  /// Sets any slider config key (vertical/home/powered/strength/sprung).
  void setSliderConfig(String id, String key, Object value) {
    final target = control(id);
    if (target == null) return;
    if ((key == 'home' || key == 'strength') && value is int) {
      target.config[key] = value.clamp(0, 100);
    } else {
      target.config[key] = value;
    }
    notifyListeners();
  }

  /// Turns one of a control's output/input capabilities on or off. Off ones
  /// produce no pin on the controller node; the graph prunes their wires.
  void setCapabilityEnabled(String id, String suffix, bool enabled) {
    final target = control(id);
    if (target == null) return;
    final hidden = target.hiddenCapabilities;
    if (enabled) {
      hidden.remove(suffix);
    } else {
      hidden.add(suffix);
    }
    target.config['hidden'] = hidden.toList();
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
