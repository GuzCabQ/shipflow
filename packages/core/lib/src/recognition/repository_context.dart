import 'recognition_enums.dart';

/// El repositorio que contiene a la raíz, sólo como contexto: nunca la
/// reemplaza.
final class RepositoryContext {
  const RepositoryContext({
    required this.status,
    required this.root,
    required this.relation,
  });

  factory RepositoryContext.fromJson(Map<String, Object?> json) =>
      RepositoryContext(
        status: RepositoryStatus.fromWireName(json['status']! as String),
        root: json['root'] as String?,
        relation: RepositoryRelation.fromWireName(json['relation']! as String),
      );

  final RepositoryStatus status;
  final String? root;
  final RepositoryRelation relation;

  Map<String, Object?> toJson() => {
    'status': status.toWireName(),
    'root': root,
    'relation': relation.toWireName(),
  };
}
