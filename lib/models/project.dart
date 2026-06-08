/// A single saved robot controller: its name, blueprint graph and
/// controller layout.
///
/// The graph and controller are stored as raw JSON maps for now; they get
/// real models when the blueprint editor lands. The `version` field in the
/// save format lets us migrate old project files later.
class Project {
  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    Map<String, dynamic>? graph,
    Map<String, dynamic>? controller,
    Map<String, dynamic>? variables,
  })  : graph = graph ?? {},
        controller = controller ?? {},
        variables = variables ?? {};

  static const int formatVersion = 1;

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Blueprint node graph (nodes, wires). Placeholder until the editor exists.
  Map<String, dynamic> graph;

  /// Controller layout (tabs, controls). Placeholder until the designer exists.
  Map<String, dynamic> controller;

  /// Project variables (Get/Set node backing store definitions).
  Map<String, dynamic> variables;

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      graph: (json['graph'] as Map?)?.cast<String, dynamic>(),
      controller: (json['controller'] as Map?)?.cast<String, dynamic>(),
      variables: (json['variables'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': formatVersion,
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'graph': graph,
        'controller': controller,
        'variables': variables,
      };
}
