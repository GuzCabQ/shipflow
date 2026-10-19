import 'package:core/core.dart';

import 'evidence_draft.dart';
import 'manifest_evidence.dart';

/// Los nombres que nunca se recorren, en cualquier profundidad.
const baselineExclusions = {
  '.git',
  '.dart_tool',
  'build',
  '.symlinks',
  'Pods',
  'node_modules',
};

/// La ruta exacta del directorio temporal de un paquete Flutter.
const _temporaryDirectory = 'ios/Flutter/ephemeral';

/// Un árbol que no se recorrió, con la evidencia que justifica su regla
/// (ninguna para las exclusiones de base).
final class OmissionDraft {
  OmissionDraft(this.path, this.rule, List<EvidenceDraft> evidence)
    : evidence = List.unmodifiable(evidence);

  /// Relativa a la raíz.
  final String path;
  final OmissionRule rule;
  final List<EvidenceDraft> evidence;
}

/// Lo que [manifest] autoriza a no recorrer dentro de su paquete, por ruta
/// relativa a la raíz: el temporal de Flutter y los directorios de recursos
/// declarados. Sólo un paquete con la dependencia del SDK Flutter concede.
Map<String, OmissionDraft> exclusionsOf(ManifestEvidence manifest) {
  final flutter = manifest.flutterDependency;
  if (flutter == null) return const {};
  final unit = manifest.unitPath;
  String under(String path) => unit == '.' ? path : '$unit/$path';
  final temporary = under(_temporaryDirectory);
  final found = <String, OmissionDraft>{
    temporary: OmissionDraft(temporary, OmissionRule.temporaryDirectory, [
      flutter,
    ]),
  };
  final declared = <String, List<EvidenceDraft>>{};
  for (final (index, path) in manifest.facts.resourceDirectories.indexed) {
    final relative = under(path.substring(0, path.length - 1));
    declared
        .putIfAbsent(relative, () => [])
        .add(manifest.resourceDirectories[index]);
  }
  for (final MapEntry(key: path, value: evidence) in declared.entries) {
    found[path] = OmissionDraft(path, OmissionRule.declaredResource, evidence);
  }
  return found;
}
