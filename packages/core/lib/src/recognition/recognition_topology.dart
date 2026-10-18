import 'recognition_json.dart';

/// Un stack que un plugin propone para la raíz, con la evidencia que lo
/// sostiene.
final class StackCandidate {
  StackCandidate({
    required this.id,
    required this.displayName,
    required this.pluginId,
    required List<String> evidenceIds,
  }) : evidenceIds = List.unmodifiable(evidenceIds);

  factory StackCandidate.fromJson(Map<String, Object?> json) => StackCandidate(
    id: json['id']! as String,
    displayName: json['displayName']! as String,
    pluginId: json['pluginId']! as String,
    evidenceIds: readStrings(json['evidenceIds']),
  );

  final String id;
  final String displayName;
  final String pluginId;
  final List<String> evidenceIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'pluginId': pluginId,
    'evidenceIds': evidenceIds,
  };
}

/// Una unidad tecnológica reconocida, como un paquete.
final class ProjectUnit {
  ProjectUnit({
    required this.id,
    required this.name,
    required this.kind,
    required this.path,
    required List<String> evidenceIds,
  }) : evidenceIds = List.unmodifiable(evidenceIds);

  factory ProjectUnit.fromJson(Map<String, Object?> json) => ProjectUnit(
    id: json['id']! as String,
    name: json['name']! as String,
    kind: json['kind']! as String,
    path: json['path']! as String,
    evidenceIds: readStrings(json['evidenceIds']),
  );

  final String id;
  final String name;
  final String kind;

  /// Relativa a la raíz resuelta.
  final String path;
  final List<String> evidenceIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'path': path,
    'evidenceIds': evidenceIds,
  };
}
