import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/project_store.dart';

enum ProjectMode { build, run }

/// Shell for an open project: switches between its two main areas,
/// Build (blueprint editor) and Run (the live controller).
///
/// Both areas are placeholders until their epics land.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.store, required this.project});

  final ProjectStore store;
  final Project project;

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
        ProjectMode.build => const _Placeholder(
            icon: Icons.account_tree_outlined,
            label: 'Build mode',
            detail: 'The blueprint editor goes here.',
          ),
        ProjectMode.run => const _Placeholder(
            icon: Icons.sports_esports_outlined,
            label: 'Run mode',
            detail: 'Your controller will appear here.',
          ),
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(
      {required this.icon, required this.label, required this.detail});

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 96),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(detail),
        ],
      ),
    );
  }
}
