import 'dart:convert';

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';

import '../context/strict_json.dart';
import 'assessment_response_shape.dart';
import 'assessment_journal_shape.dart';
import 'assessment_shape.dart';

/// El documento portable del levantamiento, junto al contexto V2.
const assessmentPath = 'shipflow/assessment.json';

/// El journal propio de una publicación de assess: local, no portable.
const assessmentJournalPath = 'shipflow/local/assessment-transaction.json';

/// SHA-256 hexadecimal de [bytes].
String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

/// [prefix] y la huella de la forma canónica de [tuple].
String assessmentIdOf(String prefix, List<Object?> tuple) =>
    '$prefix${sha256Of(identityBytes(tuple))}';

/// La identidad de [snapshot]: su forma canónica sin identidad ni fecha.
String snapshotIdOf(AssessmentSnapshot snapshot) =>
    sha256Of(snapshotIdentityBytes(snapshot));

/// `shipflow/assessment.json`, o un candidato sellado: JSON estricto, la
/// forma del schema, las reglas semánticas y después cada identidad
/// derivada, sin casts tolerantes.
AssessmentDocument decodeAssessment(
  List<int> bytes, {
  int maxBytes = maxAssessmentDocumentBytes,
}) {
  final json = decodeStrictJson(
    bytes,
    maxBytes: maxBytes,
    maxDepth: maxAssessmentJsonDepth,
  );
  shapeAssessmentDocument(json);
  final document = _semantic(
    () => AssessmentDocument.fromJson(json! as Map<String, Object?>),
  );
  verifyIdentities(document.current);
  if (document.previous case final previous?) verifyIdentities(previous);
  return document;
}

/// El documento legible de disco, o un rechazo si no cabe entero: nunca
/// se escribe truncado.
List<int> encodeAssessment(AssessmentDocument document) =>
    _readable(document.toJson(), maxAssessmentDocumentBytes);

AssessmentTransaction decodeAssessmentTransaction(List<int> bytes) {
  final json = decodeStrictJson(bytes, maxBytes: maxAssessmentJournalBytes);
  shapeAssessmentTransaction(json);
  return _semantic(
    () => AssessmentTransaction.fromJson(json! as Map<String, Object?>),
  );
}

List<int> encodeAssessmentTransaction(AssessmentTransaction transaction) =>
    _readable(transaction.toJson(), maxAssessmentJournalBytes);

/// Una respuesta de assess, con su snapshot y sus identidades comprobadas.
AssessmentResult decodeAssessmentResponse(List<int> bytes) {
  final json = decodeStrictJson(
    bytes,
    maxBytes: maxAssessmentResponseBytes,
    maxDepth: maxAssessmentJsonDepth,
  );
  shapeAssessmentResponse(json);
  final result = _semantic(
    () => AssessmentResult.fromJson(json! as Map<String, Object?>),
  );
  if (result.snapshot case final snapshot?) verifyIdentities(snapshot);
  return result;
}

/// Que `snapshotId` y los IDs de unidades, archivos y afirmaciones sean los
/// derivados de su contenido. Los grupos y las fuentes candidatas citan
/// datos que el snapshot no guarda: se cotejan con su contexto.
void verifyIdentities(AssessmentSnapshot snapshot) {
  requireSemantic(snapshotIdOf(snapshot) == snapshot.snapshotId, 'digest');
  for (final unit in snapshot.units) {
    requireSemantic(
      unit.id == assessmentIdOf(unitIdPrefix, unitTuple(unit.path)),
      'unit_id',
    );
  }
  final paths = <String, String>{};
  for (final file in snapshot.files) {
    requireSemantic(
      file.id == assessmentIdOf(fileIdPrefix, fileTuple(file.path)),
      'file_id',
    );
    paths[file.id] = file.path;
  }
  for (final claim in snapshot.claims) {
    requireSemantic(
      claim.id == assessmentIdOf(claimIdPrefix, claimTupleOf(claim, paths)),
      'claim_id',
    );
  }
}

/// La tupla de identidad de [claim], con la ruta de su archivo de origen.
List<Object?> claimTupleOf(AssessmentClaim claim, Map<String, String> paths) =>
    claimTuple(
      sourcePath: paths[claim.sourceFileId]!,
      offset: claim.evidence.offset,
      relation: claim.relation.toWireName(),
      directive: claim.sourceMetadata.directive,
      targetFileId: claim.targetFileId,
      targetLabel: claim.targetLabel,
      resolution: claim.resolution.toWireName(),
      condition: claim.condition.toWireName(),
      conditionText: claim.sourceMetadata.conditionText,
    );

/// Dos espacios y salto final; las huellas no dependen de esta forma.
List<int> _readable(Map<String, Object?> json, int maxBytes) {
  final bytes = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  requireSemantic(bytes.length <= maxBytes, 'too_large');
  return bytes;
}

/// [build], con cualquier invariante incumplida como rechazo semántico.
T _semantic<T>(T Function() build) {
  try {
    return build();
  } on ArgumentError {
    throw const ContextFormatException(
      ContextFormatLayer.semantic,
      'invalid_value',
    );
  } on FormatException {
    throw const ContextFormatException(
      ContextFormatLayer.semantic,
      'invalid_value',
    );
  }
}
