import 'dart:async';

import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/project_store.dart';
import 'blueprint_canvas.dart';
import 'canvas_viewport.dart';
import 'model/controller_layout.dart';
import 'model/graph.dart';
import 'model/node_def.dart';
import 'model/pins.dart';
import 'model/variables.dart';
import 'node_geometry.dart';
import 'widgets/add_control_sheet.dart';
import 'widgets/add_node_sheet.dart';
import 'widgets/controller_node_widget.dart';
import 'widgets/node_widget.dart';
import 'widgets/wire_painter.dart';

/// Build mode: the blueprint editor for one project.
///
/// Owns the editor state — graph, controller layout, selection, wiring mode,
/// viewport — and autosaves everything (debounced) so reopening the project
/// restores exactly what was on screen.
class BlueprintEditor extends StatefulWidget {
  const BlueprintEditor(
      {super.key, required this.store, required this.project});

  final ProjectStore store;
  final Project project;

  @override
  State<BlueprintEditor> createState() => _BlueprintEditorState();
}

class _BlueprintEditorState extends State<BlueprintEditor> {
  // Created lazily in the first layout pass: a brand-new project should open
  // with the canvas origin centred, which needs the screen size.
  CanvasViewport? _viewport;
  Map<String, dynamic>? _savedViewportJson;

  late final BlueprintGraph _graph;
  late final ControllerLayout _layout;
  late final VariableSet _variables;
  String? _selectedNodeId;

  /// The pin a wire is being drawn from while wiring mode is active.
  PinRef? _wiringFrom;

  Timer? _saveTimer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _layout = ControllerLayout.fromJson(widget.project.controller);
    _variables = VariableSet.fromJson(widget.project.variables);
    final controllerDef = _layout.buildNodeDef();
    _graph = BlueprintGraph.fromJson(
      widget.project.graph,
      dynamicDefs: {kControllerDefId: controllerDef},
      variables: _variables,
    );
    // Every project has its controller front and centre on the canvas.
    _graph.ensureControllerNode(
      controllerDef,
      Offset(-kControllerNodeWidth / 2,
          -controllerNodeSize(controllerDef).height / 2),
    );
    _graph.addListener(_onGraphChanged);
    _layout.addListener(_onLayoutChanged);
    _variables.addListener(_onVariablesChanged);
  }

  @override
  void deactivate() {
    // Flush pending saves here rather than in dispose: when the user flips
    // Build → Run, the new RunMode subtree initialises *before* this editor
    // is disposed, and it must read the freshest graph from the project.
    _saveTimer?.cancel();
    if (_dirty) _persist();
    _persistViewport();
    super.deactivate();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) _persist();
    _graph.removeListener(_onGraphChanged);
    _layout.removeListener(_onLayoutChanged);
    _variables.removeListener(_onVariablesChanged);
    super.dispose();
  }

  // ---- persistence -------------------------------------------------------

  void _onGraphChanged() {
    setState(() {});
    _markDirty();
  }

  void _onLayoutChanged() {
    // The layout drives the controller node's pins; rebuilding the def also
    // prunes wires to pins that no longer exist (and notifies the graph,
    // which triggers the rebuild + save).
    _graph.setDynamicDef(kControllerNodeId, _layout.buildNodeDef());
  }

  void _onVariablesChanged() {
    // A renamed variable relabels its Get/Set nodes; a deleted one removes
    // them and their wires.
    _graph.applyVariableDefs(_variables);
    setState(() {});
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  void _persist() {
    _dirty = false;
    widget.project.graph.addAll(_graph.toJson());
    widget.project.controller
      ..clear()
      ..addAll(_layout.toJson());
    widget.project.variables
      ..clear()
      ..addAll(_variables.toJson());
    widget.store.save(widget.project);
  }

  void _persistViewport() {
    final viewport = _viewport;
    if (viewport == null) return;
    final json = viewport.toJson();
    if (json.toString() != _savedViewportJson.toString()) {
      widget.project.graph['viewport'] = json;
      widget.store.save(widget.project);
    }
  }

  CanvasViewport _createViewport(Size size) {
    final json = widget.project.graph['viewport'];
    _savedViewportJson = (json as Map?)?.cast<String, dynamic>();
    if (_savedViewportJson != null) {
      return CanvasViewport.fromJson(_savedViewportJson);
    }
    return CanvasViewport(translation: size.center(Offset.zero));
  }

  // ---- wiring mode -------------------------------------------------------

  void _onTapPin(PinRef ref) {
    final from = _wiringFrom;
    if (from == null) {
      setState(() => _wiringFrom = ref);
      return;
    }
    if (ref == from) {
      _cancelWiring(); // tapping the same pin again backs out
      return;
    }
    if (_graph.canConnect(from, ref)) {
      _graph.connect(from, ref);
      setState(() => _wiringFrom = null);
    } else if (_autoConverterId(from, ref) != null) {
      _insertConverter(from, ref);
      setState(() => _wiringFrom = null);
    }
    // Incompatible pin: ignore the tap, stay in wiring mode.
  }

  void _cancelWiring() => setState(() => _wiringFrom = null);

  /// Connectable directly, or via an auto-inserted converter.
  bool _canLink(PinRef from, PinRef target) =>
      _graph.canConnect(from, target) ||
      _autoConverterId(from, target) != null;

  /// "Plug anything into a string": when the target pin is a string input
  /// and the source is int/bool/power, the matching X → String node can be
  /// dropped in automatically. Returns its defId, or null.
  String? _autoConverterId(PinRef a, PinRef b) {
    if (a.isOutput == b.isOutput) return null;
    final output = a.isOutput ? a : b;
    final input = a.isOutput ? b : a;
    if (_graph.pinType(input) != PinType.string) return null;
    return switch (_graph.pinType(output)) {
      PinType.integer => 'text.fromInt',
      PinType.boolean => 'text.fromBool',
      PinType.power => 'text.fromPower',
      _ => null,
    };
  }

  /// Creates the converter halfway along where the wire would run and wires
  /// both halves up.
  void _insertConverter(PinRef a, PinRef b) {
    final output = a.isOutput ? a : b;
    final input = a.isOutput ? b : a;
    final defId = _autoConverterId(a, b)!;
    final converterInput = switch (defId) {
      'text.fromInt' => 'number',
      'text.fromBool' => 'value',
      _ => 'power', // text.fromPower
    };
    final fromNode = _graph.node(output.nodeId);
    final toNode = _graph.node(input.nodeId);
    if (fromNode == null || toNode == null) return;
    final def = nodeDefById(defId)!;

    final start = fromNode.position +
        nodePinOffset(fromNode, output.pinId, isOutput: true);
    final end =
        toNode.position + nodePinOffset(toNode, input.pinId, isOutput: false);
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final size = nodeSize(def);
    final converter = _graph.addNode(
        def, mid - Offset(size.width / 2, size.height / 2));

    _graph.connect(output, PinRef(converter.id, converterInput, isOutput: false));
    _graph.connect(PinRef(converter.id, 'result', isOutput: true), input);
  }

  bool _pinHighlighted(PinRef ref) {
    final from = _wiringFrom;
    return from != null && (ref == from || _canLink(from, ref));
  }

  bool _nodeDimmed(GraphNode node) {
    final from = _wiringFrom;
    if (from == null || node.id == from.nodeId) return false;
    for (final input in node.def.inputs) {
      if (_canLink(from, PinRef(node.id, input.id, isOutput: false))) {
        return false;
      }
    }
    for (final output in node.def.outputs) {
      if (_canLink(from, PinRef(node.id, output.id, isOutput: true))) {
        return false;
      }
    }
    return true;
  }

  void _onDisconnectPin(PinRef ref) {
    final hadWires =
        _graph.wires.any((w) => ref.isOutput ? w.from == ref : w.to == ref);
    if (!hadWires) return;
    _graph.disconnectPin(ref);
    _toast('Disconnected');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ));
  }

  // ---- node actions ------------------------------------------------------

  /// Long-press on empty canvas. Normally shows the whole catalog; while
  /// wiring it shows only nodes that can take the wire, and auto-connects
  /// the one placed — so "hardcode a value into this pin" is: tap the pin,
  /// hold empty space, pick Number.
  Future<void> _addNodeAt(Offset canvasPosition) async {
    final from = _wiringFrom;
    final defs = from == null
        ? null
        : nodeCatalog.where((d) => _defConnectsTo(d, from)).toList();
    final choice = await showAddNodeSheet(
      context,
      defs: defs,
      variables: _variables,
      hint: from == null
          ? null
          : 'Showing nodes that can connect to your wire — '
              'it will hook up automatically.',
    );
    if (choice == null || !mounted) return;

    final GraphNode node;
    switch (choice) {
      case CatalogChoice(:final def):
        node = _graph.addNode(def, canvasPosition);
      case VariableChoice(:final variableId, :final isSetter):
        final added = _addVarNode(variableId, isSetter, canvasPosition);
        if (added == null) return;
        node = added;
      case NewVariableChoice():
        final created = await _createVariable();
        if (created == null || !mounted) return;
        node = _addVarNode(created, false, canvasPosition)!;
    }

    if (from != null) {
      final target = _firstCompatiblePin(node, from);
      if (target != null) _graph.connect(from, target);
    }
    setState(() {
      _selectedNodeId = node.id;
      _wiringFrom = null;
    });
  }

  GraphNode? _addVarNode(String variableId, bool isSetter, Offset position) {
    final variable = _variables.byId(variableId);
    if (variable == null) return null;
    final def = isSetter ? varSetDef(variable) : varGetDef(variable);
    return _graph.addDynamicNode(def, position, {'var': variableId});
  }

  /// Prompts for a name and type, creates the variable, returns its id.
  Future<String?> _createVariable() async {
    final type = await showModalBottomSheet<VarType>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
                title: Text('What kind of variable?',
                    style: Theme.of(context).textTheme.titleMedium)),
            for (final t in VarType.values)
              ListTile(
                key: Key('new-var-${t.name}'),
                leading: Icon(switch (t) {
                  VarType.integer => Icons.pin_outlined,
                  VarType.boolean => Icons.toggle_on_outlined,
                  VarType.text => Icons.text_fields,
                }),
                title: Text(t.label),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return null;
    final name = await _promptForText(
      title: 'Name your variable',
      initial: _variables.defaultName(type),
      confirmLabel: 'Create',
    );
    if (name == null) return null;
    return _variables.create(name, type).id;
  }

  bool _defConnectsTo(NodeDef def, PinRef from) {
    final fromType = _graph.pinType(from);
    final pins = from.isOutput ? def.inputs : def.outputs;
    return pins.any((p) => p.type == fromType);
  }

  PinRef? _firstCompatiblePin(GraphNode node, PinRef from) {
    final wantOutput = !from.isOutput;
    for (final spec in wantOutput ? node.def.outputs : node.def.inputs) {
      final ref = PinRef(node.id, spec.id, isOutput: wantOutput);
      if (_graph.canConnect(from, ref)) return ref;
    }
    return null;
  }

  Future<void> _renameNode(GraphNode node) async {
    final name = await _promptForText(
      title: 'Rename node',
      initial: node.label,
      confirmLabel: 'Rename',
    );
    if (name != null) _graph.renameNode(node.id, name);
  }

  void _onTapCanvas(Offset _) {
    setState(() {
      _selectedNodeId = null;
      _wiringFrom = null; // tapping empty canvas also backs out of wiring
    });
  }

  void _resetView(Size size) {
    _viewport?.follow(
      screenFocal: size.center(Offset.zero),
      canvasFocal: Offset.zero,
      scale: 1,
    );
  }

  // ---- controller actions ------------------------------------------------

  Future<void> _addControl(String tabId, Offset fraction) async {
    final kind = await showAddControlSheet(context);
    if (kind == null || !mounted) return;
    final name = await _promptForText(
      title: 'Name your ${kind.label.toLowerCase()}',
      initial: _layout.defaultControlName(kind),
      confirmLabel: 'Add',
    );
    if (name == null) return;
    _layout.addControl(
        tabId: tabId, kind: kind, name: name, position: fraction);
  }

  Future<void> _controlMenu(ControllerControl control) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) => ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(control.name,
                    style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text('${control.kind.label} — '
                    '${control.kind.rangeBlurb}'),
              ),
              // Live size sliders — the control resizes behind the sheet.
              // Displays grow wide; plotters grow wide AND tall (to fill the
              // screen).
              () {
                final wide = control.kind == ControlKind.display ||
                    control.kind == ControlKind.plotter;
                final tall = control.kind == ControlKind.plotter;
                return Column(children: [
                  _sheetSlider(
                    key: const Key('control-size-x'),
                    icon: Icons.swap_horiz,
                    label: 'Width',
                    value: control.scaleX,
                    min: 0.5,
                    max: wide ? 5.0 : 2.0,
                    divisions: wide ? 18 : 6,
                    display: '${(control.scaleX * 100).round()}%',
                    onChanged: (value) {
                      _layout.setControlScale(control.id, x: value);
                      setSheetState(() {});
                    },
                  ),
                  _sheetSlider(
                    key: const Key('control-size-y'),
                    icon: Icons.swap_vert,
                    label: 'Height',
                    value: control.scaleY,
                    min: 0.5,
                    max: tall ? 5.0 : 2.0,
                    divisions: tall ? 18 : 6,
                    display: '${(control.scaleY * 100).round()}%',
                    onChanged: (value) {
                      _layout.setControlScale(control.id, y: value);
                      setSheetState(() {});
                    },
                  ),
                ]);
              }(),
              if (control.kind == ControlKind.display) ...[
                _sheetSlider(
                  key: const Key('control-text-size'),
                  icon: Icons.text_fields,
                  label: 'Text size',
                  value: control.displayTextSize,
                  min: 12,
                  max: 40,
                  divisions: 7,
                  display: '${control.displayTextSize.round()}',
                  onChanged: (value) {
                    _layout.setDisplayTextSize(control.id, value);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  key: const Key('control-display-framed'),
                  secondary: const Icon(Icons.crop_square),
                  title: const Text('Show background box'),
                  value: control.displayFramed,
                  onChanged: (value) {
                    _layout.setDisplayFramed(control.id, value);
                    setSheetState(() {});
                  },
                ),
              ],
              if (control.kind == ControlKind.slider) ...[
                SwitchListTile(
                  key: const Key('control-slider-vertical'),
                  secondary: const Icon(Icons.straighten),
                  title: const Text('Up-and-down (vertical)'),
                  value: control.sliderVertical,
                  onChanged: (value) {
                    _layout.setSliderConfig(control.id, 'vertical', value);
                    setSheetState(() {});
                  },
                ),
                _sheetSlider(
                  key: const Key('control-slider-default'),
                  icon: Icons.flag_outlined,
                  label: 'Start at',
                  value: control.sliderDefault.toDouble(),
                  min: control.sliderMin.toDouble(),
                  max: control.sliderMax.toDouble(),
                  divisions: control.sliderMax - control.sliderMin,
                  display: '${control.sliderDefault}',
                  onChanged: (value) {
                    _layout.setSliderDefault(control.id, value.round());
                    setSheetState(() {});
                  },
                ),
                _sheetSlider(
                  key: const Key('control-slider-home'),
                  icon: Icons.home_outlined,
                  label: 'Home',
                  value: control.sliderHome.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  display: '${control.sliderHome}',
                  onChanged: (value) {
                    _layout.setSliderConfig(
                        control.id, 'home', value.round());
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  key: const Key('control-slider-powered'),
                  secondary: const Icon(Icons.bolt),
                  title: const Text('Springs back to home'),
                  subtitle: const Text('Off = stays where you leave it'),
                  value: control.sliderPowered,
                  onChanged: (value) {
                    _layout.setSliderConfig(control.id, 'powered', value);
                    setSheetState(() {});
                  },
                ),
                if (control.sliderPowered) ...[
                  _sheetSlider(
                    key: const Key('control-slider-strength'),
                    icon: Icons.speed,
                    label: 'Spring speed',
                    value: control.sliderStrength.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    display: '${control.sliderStrength}',
                    onChanged: (value) {
                      _layout.setSliderConfig(
                          control.id, 'strength', value.round());
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    key: const Key('control-slider-sprung'),
                    secondary: const Icon(Icons.waves),
                    title: const Text('Sprung (stronger further out)'),
                    subtitle: const Text('Off = steady speed'),
                    value: control.sliderSprung,
                    onChanged: (value) {
                      _layout.setSliderConfig(control.id, 'sprung', value);
                      setSheetState(() {});
                    },
                  ),
                ],
              ],
              if (control.kind == ControlKind.plotter) ...[
                _sheetSlider(
                  key: const Key('control-plotter-dots'),
                  icon: Icons.scatter_plot,
                  label: 'Dots per draw',
                  value: control.plotterDots.toDouble(),
                  min: 1,
                  max: kPlotterMaxDots.toDouble(),
                  divisions: kPlotterMaxDots - 1,
                  display: '${control.plotterDots}',
                  onChanged: (value) {
                    _layout.setPlotterConfig(control.id, 'dots', value.round());
                    setSheetState(() {});
                  },
                ),
                _sheetSlider(
                  key: const Key('control-plotter-dotsize'),
                  icon: Icons.brightness_1,
                  label: 'Dot size',
                  value: control.plotterDotSize,
                  min: 1,
                  max: 30,
                  divisions: 29,
                  display: '${control.plotterDotSize.round()}',
                  onChanged: (value) {
                    _layout.setPlotterConfig(
                        control.id, 'dotSize', value.round());
                    setSheetState(() {});
                  },
                ),
                _sheetSlider(
                  key: const Key('control-plotter-clear'),
                  icon: Icons.layers,
                  label: 'Keep draws',
                  value: control.plotterClearAfter
                      .toDouble()
                      .clamp(1, 100),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  display: '${control.plotterClearAfter}',
                  onChanged: (value) {
                    _layout.setPlotterConfig(
                        control.id, 'clearAfter', value.round());
                    setSheetState(() {});
                  },
                ),
                ListTile(
                  key: const Key('control-plotter-range'),
                  leading: const Icon(Icons.crop_free),
                  title: const Text('Grid range'),
                  subtitle: Text(
                      'X ${control.plotterMinX}–${control.plotterMaxX},  '
                      'Y ${control.plotterMinY}–${control.plotterMaxY}'),
                  onTap: () async {
                    await _editPlotterRange(control);
                    setSheetState(() {});
                  },
                ),
              ],
              if (control.kind == ControlKind.joystick) ...[
                SwitchListTile(
                  key: const Key('control-joystick-powered'),
                  secondary: const Icon(Icons.bolt),
                  title: const Text('Springs back to centre'),
                  subtitle: const Text('Off = stays where you leave it'),
                  value: control.joystickPowered,
                  onChanged: (value) {
                    _layout.setSliderConfig(control.id, 'powered', value);
                    setSheetState(() {});
                  },
                ),
                if (control.joystickPowered) ...[
                  _sheetSlider(
                    key: const Key('control-joystick-strength'),
                    icon: Icons.speed,
                    label: 'Spring speed',
                    value: control.joystickStrength.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    display: '${control.joystickStrength}',
                    onChanged: (value) {
                      _layout.setSliderConfig(
                          control.id, 'strength', value.round());
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    key: const Key('control-joystick-sprung'),
                    secondary: const Icon(Icons.waves),
                    title: const Text('Sprung (stronger further out)'),
                    subtitle: const Text('Off = steady speed'),
                    value: control.joystickSprung,
                    onChanged: (value) {
                      _layout.setSliderConfig(control.id, 'sprung', value);
                      setSheetState(() {});
                    },
                  ),
                ],
              ],
              SwitchListTile(
                key: const Key('control-show-name'),
                secondary: const Icon(Icons.label_outline),
                title: const Text('Show name when running'),
                value: control.showName,
                onChanged: (value) {
                  _layout.setControlShowName(control.id, value);
                  setSheetState(() {});
                },
              ),
              if (control.kind == ControlKind.slider)
                SwitchListTile(
                  key: const Key('control-show-value'),
                  secondary: const Icon(Icons.onetwothree),
                  title: const Text('Show value when running'),
                  value: control.showValue,
                  onChanged: (value) {
                    _layout.setControlShowValue(control.id, value);
                    setSheetState(() {});
                  },
                ),
              if (control.capabilities.length > 1) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Pins on the controller node',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final cap in control.capabilities)
                  SwitchListTile(
                    key: Key('control-cap-${cap.suffix}'),
                    dense: true,
                    secondary: Icon(cap.isInput
                        ? Icons.login
                        : Icons.logout),
                    title: Text(cap.label),
                    value: control.capabilityEnabled(cap.suffix),
                    onChanged: (value) {
                      _layout.setCapabilityEnabled(
                          control.id, cap.suffix, value);
                      setSheetState(() {});
                    },
                  ),
              ],
              ListTile(
                key: const Key('control-rename'),
                leading: const Icon(Icons.edit),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                key: const Key('control-delete'),
                leading: const Icon(Icons.delete),
                title: const Text('Delete'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        final name = await _promptForText(
          title: 'Rename control',
          initial: control.name,
          confirmLabel: 'Rename',
        );
        if (name != null) _layout.renameControl(control.id, name);
      case 'delete':
        final confirmed = await _confirm(
          title: "Delete '${control.name}'?",
          message: 'Any wires connected to it will be removed.',
        );
        if (confirmed) _layout.removeControl(control.id);
    }
  }

  Future<void> _addTab() async {
    final name = await _promptForText(
      title: 'New tab',
      initial: 'Tab ${_layout.tabs.length + 1}',
      confirmLabel: 'Add',
    );
    if (name != null) _layout.addTab(name);
  }

  Future<void> _tabMenu(ControllerTab tab) async {
    final canDelete = _layout.tabs.length > 1;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(tab.name,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: const Text('Controller tab'),
            ),
            ListTile(
              key: const Key('tab-rotate'),
              leading: const Icon(Icons.screen_rotation),
              title: Text(tab.landscape ? 'Make portrait' : 'Make landscape'),
              subtitle: Text(tab.landscape
                  ? 'Hold the phone upright for this page'
                  : 'Hold the phone sideways for this page'),
              onTap: () => Navigator.pop(context, 'rotate'),
            ),
            ListTile(
              key: const Key('tab-rename'),
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              key: const Key('tab-delete'),
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              subtitle:
                  canDelete ? null : const Text('Your last tab has to stay'),
              enabled: canDelete,
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rotate':
        _layout.setTabOrientation(tab.id, landscape: !tab.landscape);
      case 'rename':
        final name = await _promptForText(
          title: 'Rename tab',
          initial: tab.name,
          confirmLabel: 'Rename',
        );
        if (name != null) _layout.renameTab(tab.id, name);
      case 'delete':
        final confirmed = tab.controls.isEmpty ||
            await _confirm(
              title: "Delete '${tab.name}'?",
              message: 'Its ${tab.controls.length} control(s) and their '
                  'wires will be removed.',
            );
        if (confirmed) _layout.removeTab(tab.id);
    }
  }

  /// One labelled slider row inside the control sheet.
  Widget _sheetSlider({
    required Key key,
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          SizedBox(width: 64, child: Text(label)),
          Expanded(
            child: Slider(
              key: key,
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              value: value.clamp(min, max),
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 44, child: Text(display)),
        ],
      ),
    );
  }

  // ---- dialogs -----------------------------------------------------------

  /// Lets the user type the plotter's four grid bounds.
  Future<void> _editPlotterRange(ControllerControl control) async {
    final minX = await _promptForInt('Grid: smallest X', control.plotterMinX);
    if (minX == null || !mounted) return;
    final maxX = await _promptForInt('Grid: largest X', control.plotterMaxX);
    if (maxX == null || !mounted) return;
    final minY = await _promptForInt('Grid: smallest Y', control.plotterMinY);
    if (minY == null || !mounted) return;
    final maxY = await _promptForInt('Grid: largest Y', control.plotterMaxY);
    if (maxY == null) return;
    _layout.setPlotterConfig(control.id, 'minX', minX);
    _layout.setPlotterConfig(control.id, 'maxX', maxX);
    _layout.setPlotterConfig(control.id, 'minY', minY);
    _layout.setPlotterConfig(control.id, 'maxY', maxY);
  }

  Future<int?> _promptForInt(String title, int initial) {
    final controller = TextEditingController(text: '$initial');
    return showDialog<int>(
      context: context,
      builder: (context) {
        void submit() {
          final value = int.tryParse(controller.text.trim());
          if (value != null) Navigator.pop(context, value);
        }

        return AlertDialog(
          title: Text(title),
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
            FilledButton(onPressed: submit, child: const Text('OK')),
          ],
        );
      },
    );
  }

  Future<String?> _promptForText({
    required String title,
    required String initial,
    required String confirmLabel,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) {
        void submit() {
          final value = controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: Text(confirmLabel)),
          ],
        );
      },
    );
  }

  Future<bool> _confirm(
      {required String title, required String message}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final viewport = _viewport ??= _createViewport(size);
        return Stack(
          children: [
            Positioned.fill(
              child: BlueprintCanvas(
                viewport: viewport,
                onTapCanvas: _onTapCanvas,
                onLongPressCanvas: _addNodeAt,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: WirePainter(
                          graph: _graph,
                          viewport: viewport,
                          faded: _wiringFrom != null,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: viewport,
                      builder: (context, _) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final node in _nodesInPaintOrder())
                            _buildNode(node, viewport),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_wiringFrom != null) _buildWiringBanner(),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'canvas-reset-view',
                tooltip: 'Back to centre',
                onPressed: () => _resetView(size),
                child: const Icon(Icons.filter_center_focus),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Selected node paints last (on top).
  List<GraphNode> _nodesInPaintOrder() {
    final nodes = _graph.nodes.toList();
    final selectedIndex = nodes.indexWhere((n) => n.id == _selectedNodeId);
    if (selectedIndex >= 0) {
      nodes.add(nodes.removeAt(selectedIndex));
    }
    return nodes;
  }

  Widget _buildNode(GraphNode node, CanvasViewport viewport) {
    final screenPosition = viewport.toScreen(node.position);
    final child = node.id == kControllerNodeId
        ? ControllerNodeWidget(
            key: const ValueKey('node-controller'),
            node: node,
            layout: _layout,
            selected: node.id == _selectedNodeId,
            dimmed: _nodeDimmed(node),
            wiringActive: _wiringFrom != null,
            pinHighlighted: _pinHighlighted,
            onSelect: () => setState(() => _selectedNodeId = node.id),
            onMoveBy: (delta) => _graph.moveNode(node.id, delta),
            onRename: () => _renameNode(node),
            onTapPin: _onTapPin,
            onLongPressPin: _onDisconnectPin,
            onAddTab: _addTab,
            onTabMenu: _tabMenu,
            onAddControl: _addControl,
            onControlMenu: _controlMenu,
            onMoveControl: (control, delta) =>
                _layout.moveControl(control.id, delta),
          )
        : NodeWidget(
            key: ValueKey('node-${node.id}'),
            node: node,
            selected: node.id == _selectedNodeId,
            dimmed: _nodeDimmed(node),
            wiringActive: _wiringFrom != null,
            pinHighlighted: _pinHighlighted,
            onSelect: () => setState(() => _selectedNodeId = node.id),
            onMoveBy: (delta) => _graph.moveNode(node.id, delta),
            onRename: () => _renameNode(node),
            onDelete: () {
              _graph.removeNode(node.id);
              setState(() => _selectedNodeId = null);
            },
            onTapPin: _onTapPin,
            onLongPressPin: _onDisconnectPin,
            onConfigChanged: (key, value) =>
                _graph.setConfig(node.id, key, value),
          );
    return Positioned(
      left: screenPosition.dx,
      top: screenPosition.dy,
      child: Transform.scale(
        scale: viewport.scale,
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }

  Widget _buildWiringBanner() {
    final from = _wiringFrom!;
    final hasWires = _graph.wires
        .any((w) => from.isOutput ? w.from == from : w.to == from);
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tap a glowing pin — or hold empty space to add a node',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(width: 10),
                if (hasWires) ...[
                  FloatingActionButton.small(
                    key: const Key('disconnect-pin'),
                    heroTag: 'disconnect-pin',
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    tooltip: 'Disconnect this pin',
                    onPressed: () {
                      _onDisconnectPin(from);
                      _cancelWiring();
                    },
                    child: const Icon(Icons.link_off),
                  ),
                  const SizedBox(width: 6),
                ],
                FloatingActionButton.small(
                  key: const Key('cancel-wiring'),
                  heroTag: 'cancel-wiring',
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  tooltip: 'Cancel',
                  onPressed: _cancelWiring,
                  child: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
