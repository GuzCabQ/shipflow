import '../context/context_validation.dart';
import 'assessment_enums.dart';

const assessmentTransactionKind = 'shipflow.assessment-transaction';

/// La única ruta de candidato que puede nombrar la operación [operationId].
String assessmentCandidatePath(String operationId) =>
    'shipflow/local/assessment-staging/$operationId/candidate.json';

/// `shipflow/local/assessment-transaction.json`: la publicación en curso.
/// Sus huellas son de bytes completos de disco; su ruta de candidato no
/// autoriza nada: se recalcula y se coteja.
final class AssessmentTransaction {
  AssessmentTransaction({
    required this.projectId,
    required this.operationId,
    required this.before,
    required this.after,
    required this.state,
    required this.baseContextDigest,
    required this.snapshotId,
  }) : candidatePath = assessmentCandidatePath(operationId) {
    requireSemantic(isUuidV4(projectId) && isUuidV4(operationId), 'ids');
    requireSemantic(
      (before == null || isSha256Hex(before!)) &&
          [after, baseContextDigest, snapshotId].every(isSha256Hex),
      'digest_form',
    );
  }

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory AssessmentTransaction.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'schema_version');
    requireSemantic(json['kind'] == assessmentTransactionKind, 'kind');
    final operationId = json['operationId']! as String;
    requireSemantic(
      json['candidatePath'] == assessmentCandidatePath(operationId),
      'candidate_path',
    );
    return AssessmentTransaction(
      projectId: json['projectId']! as String,
      operationId: operationId,
      before: json['before'] as String?,
      after: json['after']! as String,
      state: AssessmentTransactionState.fromWireName(json['state']! as String),
      baseContextDigest: json['baseContextDigest']! as String,
      snapshotId: json['snapshotId']! as String,
    );
  }

  final int schemaVersion = 1;
  final String kind = assessmentTransactionKind;
  final String projectId;
  final String operationId;

  /// SHA-256 del documento antes, o null si no existía.
  final String? before;

  /// SHA-256 del documento que la operación publica.
  final String after;
  final String candidatePath;
  final AssessmentTransactionState state;
  final String baseContextDigest;
  final String snapshotId;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'kind': kind,
    'projectId': projectId,
    'operationId': operationId,
    'before': before,
    'after': after,
    'candidatePath': candidatePath,
    'state': state.toWireName(),
    'baseContextDigest': baseContextDigest,
    'snapshotId': snapshotId,
  };
}
