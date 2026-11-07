import 'package:core/core.dart';

/// Las entradas de las publicaciones con staging propio (assess y
/// bootstrap) bajo `shipflow/`. La forma no prueba propiedad: sólo el
/// journal de su publicación la acredita.
enum StagedEntry { temporary, candidate, staging }

/// Los temporales de una publicación de assess.
final assessmentTemporaryPattern = RegExp(
  r'^(?:\.assessment\.json|local/\.assessment-transaction\.json|'
  r'local/assessment-staging/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab]'
  r'[0-9a-f]{3}-[0-9a-f]{12}/\.candidate\.json)\.[0-9a-f]{16}\.tmp$',
);

/// Los temporales de una publicación de bootstrap.
final basisTemporaryPattern = RegExp(
  r'^(?:\.basis\.json|local/\.basis-draft\.json|local/\.basis-transaction\.json|'
  r'local/basis-staging/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab]'
  r'[0-9a-f]{3}-[0-9a-f]{12}/\.candidate\.json)\.[0-9a-f]{16}\.tmp$',
);

/// La clase de [path], relativa a `shipflow/`, para la carpeta de staging
/// [folder] bajo `local/` y sus temporales [temporary]; null si no es suya.
StagedEntry? stagedEntryOf(
  String path, {
  required bool directory,
  required String folder,
  required RegExp temporary,
}) {
  final segments = path.split('/');
  final staging =
      segments.length >= 3 &&
      segments[0] == 'local' &&
      segments[1] == folder &&
      isUuidV4(segments[2]);
  if (directory) {
    return staging && segments.length == 3 ? StagedEntry.staging : null;
  }
  if (temporary.hasMatch(path)) return StagedEntry.temporary;
  return staging && segments.length == 4 && segments[3] == 'candidate.json'
      ? StagedEntry.candidate
      : null;
}
