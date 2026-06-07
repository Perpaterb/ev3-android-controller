import 'dart:io';

import 'package:ev3_controller/models/project.dart';
import 'package:ev3_controller/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late ProjectStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ev3_store_test');
    store = ProjectStore(FileProjectStorage(tempDir));
    await store.load();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('starts empty', () {
    expect(store.projects, isEmpty);
  });

  test('create persists a project file and lists it', () async {
    final project = await store.create('Tank Bot');
    expect(store.projects.map((p) => p.name), ['Tank Bot']);
    expect(File('${tempDir.path}/${project.id}.json').existsSync(), isTrue);
  });

  test('projects survive a reload', () async {
    await store.create('Tank Bot');
    final reloaded = ProjectStore(FileProjectStorage(tempDir));
    await reloaded.load();
    expect(reloaded.projects.map((p) => p.name), ['Tank Bot']);
  });

  test('rename trims and persists', () async {
    final project = await store.create('Tank Bot');
    await store.rename(project, '  Crane Bot  ');
    final reloaded = ProjectStore(FileProjectStorage(tempDir));
    await reloaded.load();
    expect(reloaded.projects.single.name, 'Crane Bot');
  });

  test('delete removes the file and only that project', () async {
    final keep = await store.create('Keeper');
    final gone = await store.create('Goner');
    await store.delete(gone);
    expect(store.projects, [keep]);
    final reloaded = ProjectStore(FileProjectStorage(tempDir));
    await reloaded.load();
    expect(reloaded.projects.single.name, 'Keeper');
  });

  test('most recently edited project is listed first', () async {
    final older = await store.create('Older');
    await store.create('Newer');
    expect(store.projects.first.name, 'Newer');
    await store.save(older); // editing bumps it back to the top
    expect(store.projects.first.name, 'Older');
  });

  test('a corrupt file is skipped, not fatal', () async {
    await store.create('Good');
    File('${tempDir.path}/broken.json').writeAsStringSync('not json{');
    final reloaded = ProjectStore(FileProjectStorage(tempDir));
    await reloaded.load();
    expect(reloaded.projects.single.name, 'Good');
  });

  test('nextDefaultName skips taken names', () async {
    expect(store.nextDefaultName(), 'My Robot 1');
    await store.create('My Robot 1');
    expect(store.nextDefaultName(), 'My Robot 2');
  });

  test('project JSON round-trips', () {
    final project = Project(
      id: 'abc',
      name: 'Round Trip',
      createdAt: DateTime(2026, 6, 1, 12),
      updatedAt: DateTime(2026, 6, 2, 13),
      graph: {'nodes': []},
      controller: {'tabs': []},
    );
    final copy = Project.fromJson(project.toJson());
    expect(copy.id, project.id);
    expect(copy.name, project.name);
    expect(copy.createdAt, project.createdAt);
    expect(copy.updatedAt, project.updatedAt);
    expect(copy.graph, project.graph);
    expect(copy.controller, project.controller);
  });
}
