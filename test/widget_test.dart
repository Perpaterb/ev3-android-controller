import 'package:ev3_controller/main.dart';
import 'package:ev3_controller/models/project.dart';
import 'package:ev3_controller/services/project_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Microtask-only storage: real file IO never completes inside the
/// fake-async zone widget tests run in.
class InMemoryProjectStorage implements ProjectStorage {
  final Map<String, Project> _byId = {};

  @override
  Future<List<Project>> loadAll() async => _byId.values.toList();

  @override
  Future<void> write(Project project) async => _byId[project.id] = project;

  @override
  Future<void> delete(String id) async => _byId.remove(id);
}

void main() {
  late ProjectStore store;

  setUp(() async {
    store = ProjectStore(InMemoryProjectStorage());
    await store.load();
  });

  testWidgets('shows empty state with no projects', (tester) async {
    await tester.pumpWidget(Ev3ControllerApp(store: store));
    expect(find.text('No projects yet!'), findsOneWidget);
  });

  testWidgets('creates a project via the dialog and opens it',
      (tester) async {
    await tester.pumpWidget(Ev3ControllerApp(store: store));

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    expect(find.text('My Robot 1'), findsOneWidget); // pre-filled default

    await tester.enterText(find.byType(TextField), 'Tank Bot');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Lands in the project shell, Build mode selected.
    expect(find.text('Tank Bot'), findsOneWidget);
    expect(find.text('Build mode'), findsOneWidget);
    expect(store.projects.single.name, 'Tank Bot');
  });

  testWidgets('switches between Build and Run', (tester) async {
    final project = await store.create('Tank Bot');
    await tester.pumpWidget(Ev3ControllerApp(store: store));
    await tester.tap(find.text(project.name));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.text('Run mode'), findsOneWidget);

    await tester.tap(find.text('Build'));
    await tester.pumpAndSettle();
    expect(find.text('Build mode'), findsOneWidget);
  });

  testWidgets('renames a project from the list menu', (tester) async {
    await store.create('Tank Bot');
    await tester.pumpWidget(Ev3ControllerApp(store: store));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Crane Bot');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    expect(find.text('Crane Bot'), findsOneWidget);
    expect(store.projects.single.name, 'Crane Bot');
  });

  testWidgets('delete asks for confirmation first', (tester) async {
    await store.create('Tank Bot');
    await tester.pumpWidget(Ev3ControllerApp(store: store));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text("Delete 'Tank Bot'?"), findsOneWidget);

    // Backing out keeps the project.
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(store.projects, hasLength(1));

    // Confirming removes it.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(store.projects, isEmpty);
    expect(find.text('No projects yet!'), findsOneWidget);
  });
}
