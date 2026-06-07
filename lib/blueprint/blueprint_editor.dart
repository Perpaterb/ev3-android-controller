import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/project_store.dart';
import 'blueprint_canvas.dart';
import 'canvas_viewport.dart';

/// Build mode: hosts the blueprint canvas for one project and keeps the
/// project's viewport (zoom/pan position) saved so reopening the project
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

  CanvasViewport _createViewport(Size size) {
    final json = widget.project.graph['viewport'];
    _savedViewportJson = (json as Map?)?.cast<String, dynamic>();
    if (_savedViewportJson != null) {
      return CanvasViewport.fromJson(_savedViewportJson);
    }
    return CanvasViewport(translation: size.center(Offset.zero));
  }

  void _resetView(Size size) {
    _viewport?.follow(
      screenFocal: size.center(Offset.zero),
      canvasFocal: Offset.zero,
      scale: 1,
    );
  }

  @override
  void dispose() {
    final viewport = _viewport;
    if (viewport != null) {
      final json = viewport.toJson();
      if (json.toString() != _savedViewportJson.toString()) {
        widget.project.graph['viewport'] = json;
        widget.store.save(widget.project);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final viewport = _viewport ??= _createViewport(size);
        return Stack(
          children: [
            Positioned.fill(child: BlueprintCanvas(viewport: viewport)),
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
}
