import 'package:ev3_controller/models/project.dart';
import 'package:ev3_controller/services/project_store.dart';

/// Microtask-only storage for widget tests: real file IO never completes
/// inside the fake-async zone widget tests run in.
class InMemoryProjectStorage implements ProjectStorage {
  final Map<String, Project> _byId = {};

  @override
  Future<List<Project>> loadAll() async => _byId.values.toList();

  @override
  Future<void> write(Project project) async => _byId[project.id] = project;

  @override
  Future<void> delete(String id) async => _byId.remove(id);
}
