import 'package:ev3_controller/blueprint/blueprint_editor.dart';
import 'package:ev3_controller/main.dart';
import 'package:ev3_controller/services/project_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_project_storage.dart';

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
    expect(find.byType(BlueprintEditor), findsOneWidget);
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
    expect(find.byType(BlueprintEditor), findsOneWidget);
  });

  testWidgets('viewport is saved when leaving Build mode and restored later',
      (tester) async {
    final project = await store.create('Tank Bot');
    await tester.pumpWidget(Ev3ControllerApp(store: store));
    await tester.tap(find.text(project.name));
    await tester.pumpAndSettle();

    // Pan the canvas, then leave Build mode so the editor disposes.
    await tester.drag(find.byType(BlueprintEditor), const Offset(-80, -40));
    await tester.pump();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    final saved = project.graph['viewport'] as Map<String, dynamic>;
    expect(saved['scale'], 1.0);

    // Re-entering Build mode restores the same view.
    await tester.tap(find.text('Build'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(project.graph['viewport'], saved);
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
