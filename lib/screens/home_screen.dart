import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/project_store.dart';
import 'project_screen.dart';

/// Home screen: the list of projects with create / open / rename / delete.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final ProjectStore store;

  Future<void> _createProject(BuildContext context) async {
    final name = await _promptForName(
      context,
      title: 'New project',
      initial: store.nextDefaultName(),
      confirmLabel: 'Create',
    );
    if (name == null || !context.mounted) return;
    final project = await store.create(name);
    if (!context.mounted) return;
    _openProject(context, project);
  }

  void _openProject(BuildContext context, Project project) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectScreen(store: store, project: project),
    ));
  }

  Future<void> _renameProject(BuildContext context, Project project) async {
    final name = await _promptForName(
      context,
      title: 'Rename project',
      initial: project.name,
      confirmLabel: 'Rename',
    );
    if (name == null) return;
    await store.rename(project, name);
  }

  Future<void> _deleteProject(BuildContext context, Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete '${project.name}'?"),
        content: const Text("This can't be undone."),
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
    if (confirmed == true) await store.delete(project);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Projects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createProject(context),
        icon: const Icon(Icons.add),
        label: const Text('New project'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final projects = store.projects;
          if (projects.isEmpty) return _EmptyState(onCreate: () => _createProject(context));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: const Icon(Icons.smart_toy_outlined, size: 36),
                  title: Text(project.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  subtitle: Text('Edited ${_relativeTime(project.updatedAt)}'),
                  onTap: () => _openProject(context, project),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => switch (action) {
                      'rename' => _renameProject(context, project),
                      _ => _deleteProject(context, project),
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Rename'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.smart_toy_outlined, size: 96),
          const SizedBox(height: 16),
          Text('No projects yet!',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Make a controller for your robot.'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Create my first project'),
          ),
        ],
      ),
    );
  }
}

/// Name prompt shared by create and rename. Returns null on cancel; trims
/// whitespace and refuses to confirm an empty name.
Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  required String initial,
  required String confirmLabel,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final name = controller.text.trim();
        if (name.isNotEmpty) Navigator.pop(context, name);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Project name'),
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

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) {
    return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 30) return '${diff.inDays} days ago';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}'
      '-${time.day.toString().padLeft(2, '0')}';
}
