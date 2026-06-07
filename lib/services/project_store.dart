import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/project.dart';

/// Persistence backend for [ProjectStore].
///
/// Swappable so widget tests can use an in-memory implementation — real file
/// IO never completes inside the fake-async zone widget tests run in.
abstract class ProjectStorage {
  Future<List<Project>> loadAll();
  Future<void> write(Project project);
  Future<void> delete(String id);
}

/// One JSON file per project inside [directory].
class FileProjectStorage implements ProjectStorage {
  FileProjectStorage(this.directory);

  final Directory directory;

  @override
  Future<List<Project>> loadAll() async {
    await directory.create(recursive: true);
    final projects = <Project>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        projects.add(Project.fromJson(json));
      } catch (e) {
        // A corrupt file should not take down the whole project list.
        debugPrint('Skipping unreadable project file ${entity.path}: $e');
      }
    }
    return projects;
  }

  @override
  Future<void> write(Project project) async {
    await directory.create(recursive: true);
    await _fileFor(project.id).writeAsString(jsonEncode(project.toJson()));
  }

  @override
  Future<void> delete(String id) async {
    final file = _fileFor(id);
    if (await file.exists()) await file.delete();
  }

  File _fileFor(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.json');
}

/// Holds the project list in recency order and persists every change
/// through [ProjectStorage].
class ProjectStore extends ChangeNotifier {
  ProjectStore(this._storage);

  final ProjectStorage _storage;
  final List<Project> _projects = [];

  /// Projects sorted by most recently edited first.
  List<Project> get projects => List.unmodifiable(_projects);

  Future<void> load() async {
    _projects
      ..clear()
      ..addAll(await _storage.loadAll());
    _sort();
    notifyListeners();
  }

  /// First unused "My Robot N" name, used to pre-fill the new-project dialog.
  String nextDefaultName() {
    final taken = _projects.map((p) => p.name).toSet();
    var n = 1;
    while (taken.contains('My Robot $n')) {
      n++;
    }
    return 'My Robot $n';
  }

  Future<Project> create(String name) async {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch.toRadixString(36)}'
        '-${Random().nextInt(0x7fffffff).toRadixString(36)}';
    final project =
        Project(id: id, name: name.trim(), createdAt: now, updatedAt: now);
    await _storage.write(project);
    _projects.insert(0, project);
    notifyListeners();
    return project;
  }

  Future<void> rename(Project project, String newName) async {
    project.name = newName.trim();
    await save(project);
  }

  /// Persists [project] and bumps it to the top of the recency order.
  Future<void> save(Project project) async {
    project.updatedAt = DateTime.now();
    await _storage.write(project);
    _sort();
    notifyListeners();
  }

  Future<void> delete(Project project) async {
    await _storage.delete(project.id);
    _projects.remove(project);
    notifyListeners();
  }

  void _sort() =>
      _projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}
