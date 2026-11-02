import 'dart:io';

import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import 'assessment_decisions.dart';

/// La vigencia comprobada de un snapshot y lo que la explica.
typedef AssessmentFreshnessCheck = ({
  AssessmentFreshness freshness,
  List<AssessmentDiagnostic> diagnostics,
});

const _unsealed = {AssessmentInputState.unreadable, AssessmentInputState.limit};

/// Si [snapshot] corresponde a sus insumos de ahora: el contexto citado por
/// la huella de sus bytes ([contextDigest]) y el inventario que vuelve a
/// sellar [reobserveInputs], sin parser. Un cambio demostrado es stale y
/// nombra sus rutas; lo que no se pudo volver a leer, o ya no se leyó al
/// observar, es unverified, nunca current. Un inventario cortado ahora no
/// cuenta como desaparición. No es un snapshot atómico del sistema de
/// archivos: son lecturas acotadas y revalidadas.
Future<AssessmentFreshnessCheck> checkAssessmentFreshness(
  Directory root,
  AssessmentSnapshot snapshot,
  AssessmentLimits limits, {
  required String? contextDigest,
  required Future<List<AssessmentInput>> Function() reobserveInputs,
}) async {
  final now = await _reobserved(reobserveInputs);
  if (now == null) return _unverified(const []);
  final before = [
    for (final i in snapshot.inputs)
      if (i.kind != AssessmentInputKind.context) i,
  ];
  final changed = [
    if (contextDigest != snapshot.contextDigest) assessmentContextPath,
    ...changedInputs(before, now),
  ];
  if (changed.isNotEmpty) return _stale(changed);
  final unknown = [
    for (final i in [...before, ...now])
      if (_unsealed.contains(i.state)) i.path,
  ];
  return unknown.isEmpty
      ? (
          freshness: AssessmentFreshness.current,
          diagnostics: const <AssessmentDiagnostic>[],
        )
      : _unverified(unknown);
}

/// El inventario de ahora, o null si no se pudo volver a mirar.
Future<List<AssessmentInput>?> _reobserved(
  Future<List<AssessmentInput>> Function() reobserveInputs,
) async {
  try {
    return await reobserveInputs();
  } on FileSystemException {
    return null;
  } on ContextStoreFailure {
    return null;
  }
}

AssessmentFreshnessCheck _stale(List<String> changed) => (
  freshness: AssessmentFreshness.stale,
  diagnostics: [
    assessmentDiagnostic(
      'assessment_stale',
      examples: changed,
      count: changed.length,
    ),
  ],
);

AssessmentFreshnessCheck _unverified(List<String> paths) => (
  freshness: AssessmentFreshness.unverified,
  diagnostics: [
    assessmentDiagnostic(
      'assessment_unverified',
      examples: paths,
      count: paths.isEmpty ? 1 : paths.toSet().length,
    ),
  ],
);

/// Las rutas cuyo sellado difiere de forma demostrable: la misma entrada
/// leída a ambos lados con otra huella u otro estado y, sólo si los dos
/// inventarios están completos, las altas y las bajas.
List<String> changedInputs(
  List<AssessmentInput> before,
  List<AssessmentInput> now,
) {
  String key(AssessmentInput i) => '${i.kind.toWireName()}\u0000${i.path}';
  final old = {for (final i in before) key(i): i};
  final current = {for (final i in now) key(i): i};
  bool cut(AssessmentInput i) =>
      i.kind == AssessmentInputKind.directory && _unsealed.contains(i.state);
  final complete = !now.any(cut) && !before.any(cut);
  final changed = <String>{};
  for (final MapEntry(:key, :value) in current.entries) {
    final was = old[key];
    if (was == null) {
      if (complete) changed.add(value.path);
    } else if (!_unsealed.contains(value.state) &&
        (was.state != value.state || was.sha256 != value.sha256)) {
      changed.add(value.path);
    }
  }
  if (complete) {
    changed.addAll([
      for (final MapEntry(:key, :value) in old.entries)
        if (!current.containsKey(key)) value.path,
    ]);
  }
  return changed.toList()..sort();
}
