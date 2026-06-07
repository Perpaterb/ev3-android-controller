import 'package:flutter/material.dart';

import '../blueprint/blueprint_editor.dart';
import '../models/project.dart';
import '../run/run_mode.dart';
import '../services/brick_connection.dart';
import '../services/project_store.dart';

enum ProjectMode { build, run }

/// Shell for an open project: switches between its two main areas,
/// Build (blueprint editor) and Run (the live controller).
///
/// Both areas are placeholders until their epics land.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen(
      {super.key,
      required this.store,
      required this.project,
      this.connection});

  final ProjectStore store;
  final Project project;
  final BrickConnection? connection;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  ProjectMode _mode = ProjectMode.build;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<ProjectMode>(
              segments: const [
                ButtonSegment(
                  value: ProjectMode.build,
                  icon: Icon(Icons.handyman_outlined),
                  label: Text('Build'),
                ),
                ButtonSegment(
                  value: ProjectMode.run,
                  icon: Icon(Icons.play_arrow),
                  label: Text('Run'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
          ),
        ],
      ),
      body: switch (_mode) {
        ProjectMode.build =>
          BlueprintEditor(store: widget.store, project: widget.project),
        ProjectMode.run => RunMode(
            project: widget.project, connection: widget.connection),
      },
    );
  }
}
