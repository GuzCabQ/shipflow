import 'dart:convert';

import 'assessment_snapshot.dart';

/// Los prefijos de cada identidad derivada.
const unitIdPrefix = 'u_';
const fileIdPrefix = 'f_';
const groupIdPrefix = 'g_';
const claimIdPrefix = 'c_';
const candidateIdPrefix = 's_';

/// [value] como JSON canónico compacto: claves en orden ordinal de unidades
/// UTF-16, listas en el orden dado, escapes mínimos y sin espacios. Quien
/// tiene SHA-256 calcula la huella de estos bytes; core no la calcula.
String canonicalAssessmentJson(Object? value) => switch (value) {
  Map<String, Object?>() =>
    '{${[for (final key in value.keys.toList()..sort()) '${jsonEncode(key)}:${canonicalAssessmentJson(value[key])}'].join(',')}}',
  List<Object?>() => '[${value.map(canonicalAssessmentJson).join(',')}]',
  _ => jsonEncode(value),
};

/// Los bytes UTF-8 de la forma canónica de [tuple].
List<int> identityBytes(List<Object?> tuple) =>
    utf8.encode(canonicalAssessmentJson(tuple));

List<Object?> unitTuple(String path) => ['unit', path];

List<Object?> fileTuple(String path) => ['file', path];

List<Object?> groupTuple(String sourcePath, int offset) => [
  'group',
  sourcePath,
  offset,
];

/// La identidad de una afirmación: ubicación, tipo, destino y condición.
List<Object?> claimTuple({
  required String sourcePath,
  required int offset,
  required String relation,
  required String directive,
  required String? targetFileId,
  required String? targetLabel,
  required String resolution,
  required String condition,
  required String? conditionText,
}) => [
  'claim',
  sourcePath,
  offset,
  relation,
  directive,
  targetFileId,
  targetLabel,
  resolution,
  condition,
  conditionText,
];

/// La clave V3 de una fuente candidata del contexto citado, que no tiene ID
/// propio: alcance, ruta y tipo.
List<Object?> candidateTuple(String scopePath, String path, String kind) => [
  'candidate_source',
  scopePath,
  path,
  kind,
];

/// Los bytes que cubre `snapshotId`: el snapshot canónico sin su propia
/// identidad ni el instante de observación.
List<int> snapshotIdentityBytes(AssessmentSnapshot snapshot) {
  final json = snapshot.toJson()
    ..remove('snapshotId')
    ..remove('observedAt');
  return utf8.encode(canonicalAssessmentJson(json));
}
