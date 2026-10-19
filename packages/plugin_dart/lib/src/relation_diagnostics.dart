import 'package:core/core.dart';

import 'evidence_draft.dart';
import 'path_dependency_boundary.dart';
import 'recognition_codes.dart';

/// Una relación tal como la declara un manifiesto.
final class Declaration {
  const Declaration(this.kind, this.shown, this.name, this.path, this.evidence);

  final RelationKind kind;

  /// Su evidencia, `<sección>.<nombre>: <ruta>` o `workspace: <miembro>`.
  final String shown;

  /// El nombre con que se declara; null en un miembro del workspace o si su
  /// evidencia se truncó.
  final String? name;

  /// La ruta declarada; null si se truncó: entonces no se interpreta.
  final String? path;
  final EvidenceDraft evidence;
}

const _globCharacters = ['*', '?', '[', ']', '{', '}'];

/// Por qué [path] no es una ruta literal que este corte interprete, o null.
/// Un miembro del workspace, además, es relativo y descendiente.
String? unsupportedForm(RelationKind kind, String path) {
  if (path.isEmpty) return 'declara una ruta vacía';
  if (path.contains(':')) return 'declara una URI';
  if (_globCharacters.any(path.contains)) return 'declara un patrón';
  if (kind == RelationKind.workspaceMember &&
      (path.startsWith('/') || path.split('/').contains('..'))) {
    return 'no es un miembro relativo descendiente';
  }
  return null;
}

/// La limitación bloqueante que ubica una relación sin destino observable:
/// nombra la declaración, la causa, el efecto y la alternativa real.
(String, String)? relationProblem(
  Declaration declaration,
  ReferencePlacement placement, {
  required bool unitFound,
  required String root,
}) {
  if (placement is ReferenceInside && unitFound) return null;
  final (code, cause, alternative) = _cause(placement, root);
  return (
    code,
    '${_subject(declaration.kind)} «${declaration.shown}» $cause; la relación '
        'queda sin corroborar y la propuesta no es elegible. $alternative',
  );
}

/// El código, la causa y la alternativa de cada ubicación sin unidad.
(String, String, String) _cause(ReferencePlacement placement, String root) =>
    switch (placement) {
      ReferenceUnsupported(:final reason) => (
        LimitationCode.unsupportedLocalReference,
        reason,
        'Esta versión sólo interpreta rutas literales.',
      ),
      ReferenceOutside() => (
        LimitationCode.pathDependencyOutsideRoot,
        'sale de la raíz y no se atraviesa',
        'Para corroborarla, inspecciona una raíz que contenga ambos paquetes.',
      ),
      ReferenceUnresolved() => (
        LimitationCode.pathDependencyUnresolved,
        'no se pudo resolver y no se atraviesa',
        'Comprueba que la ruta exista y se pueda leer.',
      ),
      ReferenceLinked(:final link) => (
        LimitationCode.unsupportedLocalReference,
        'pasa por el enlace «${_relative(link, root)}», que no se sigue',
        'Esta versión no sigue enlaces para corroborar relaciones.',
      ),
      ReferenceExcluded() || ReferenceInside() => _withinRoot(placement),
    };

/// Las causas de un destino dentro de la raíz que no se puede corroborar.
(String, String, String) _withinRoot(ReferencePlacement placement) =>
    switch (placement) {
      ReferenceExcluded(:final tree) => (
        LimitationCode.requiredPathExcluded,
        'apunta dentro de «$tree», que no se recorre por las reglas de alcance',
        'No se reabre ese árbol; una inspección separada desde esa ruta puede '
            'aportar otra ficha.',
      ),
      ReferenceInside(:final path) => (
        LimitationCode.requiredManifestMissing,
        'apunta a «$path», donde no se observó un manifiesto con nombre',
        'Esta versión sólo corrobora destinos con un manifiesto válido.',
      ),
      _ => throw StateError('no es un destino dentro de la raíz'),
    };

/// El conflicto entre el nombre declarado y el del manifiesto destino.
String nameMismatch(Declaration declaration, String target, String actual) =>
    '${_subject(declaration.kind)} «${declaration.shown}» declara '
    '«${declaration.name}», pero el manifiesto de «$target» se llama '
    '«$actual»';

String _subject(RelationKind kind) => kind == RelationKind.localDependency
    ? 'la dependencia local'
    : 'el miembro del workspace';

String _relative(String path, String root) =>
    path.startsWith('$root/') ? path.substring(root.length + 1) : path;
