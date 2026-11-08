import '../recognition/recognition_json.dart';
import 'basis_enums.dart';

/// A qué aplica un registro: `project`, prefijos de ruta relativos por
/// segmentos, o `unknown`. El orden de [paths] se conserva tal cual.
final class BasisScope {
  BasisScope({required this.kind, required List<String> paths})
    : paths = List.unmodifiable(paths);

  BasisScope.project() : this(kind: BasisScopeKind.project, paths: const []);

  BasisScope.unknown() : this(kind: BasisScopeKind.unknown, paths: const []);

  factory BasisScope.fromJson(Map<String, Object?> json) => BasisScope(
    kind: BasisScopeKind.fromWireName(json['kind']! as String),
    paths: readStrings(json['paths']),
  );

  final BasisScopeKind kind;
  final List<String> paths;

  /// Si [other] designa el mismo ámbito: mismo tipo y el mismo conjunto de
  /// prefijos, sin importar su orden.
  bool sameAs(BasisScope other) =>
      kind == other.kind &&
      paths.toSet().length == other.paths.toSet().length &&
      paths.toSet().containsAll(other.paths);

  Map<String, Object?> toJson() => {'kind': kind.toWireName(), 'paths': paths};
}
