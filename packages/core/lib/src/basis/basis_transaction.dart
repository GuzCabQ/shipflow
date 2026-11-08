import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'basis_actor.dart';
import 'basis_draft.dart';
import 'basis_enums.dart';

/// `shipflow/local/basis-transaction.json`: la aceptación exacta registrada
/// antes de que cambie la base. Recover sólo completa o aborta lo que dice;
/// nunca convierte un borrador en aceptado.
final class BasisTransaction {
  BasisTransaction({
    required this.projectId,
    required this.operationId,
    required this.phase,
    required this.before,
    required this.after,
    required this.acceptedDraftDigest,
    required this.acceptedAt,
    required this.actor,
    required this.contextProjectDigest,
    required List<BasisSourceReading> sourceReads,
    required this.candidatePath,
    required this.digest,
  }) : sourceReads = List.unmodifiable(sourceReads);

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory BasisTransaction.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'incompatible_version');
    requireSemantic(json['type'] == basisTransactionType, 'invalid_schema');
    return BasisTransaction(
      projectId: json['projectId']! as String,
      operationId: json['operationId']! as String,
      phase: BasisTransactionPhase.fromWireName(json['phase']! as String),
      before: json['before'] as String?,
      after: json['after']! as String,
      acceptedDraftDigest: json['acceptedDraftDigest']! as String,
      acceptedAt: json['acceptedAt']! as String,
      actor: readObject(json['actor'], BasisActor.fromJson),
      contextProjectDigest: json['contextProjectDigest']! as String,
      sourceReads: readObjects(
        json['sourceReads'],
        BasisSourceReading.fromJson,
      ),
      candidatePath: json['candidatePath']! as String,
      digest: json['digest']! as String,
    );
  }

  final int schemaVersion = 1;
  final String type = basisTransactionType;
  final String projectId;
  final String operationId;
  final BasisTransactionPhase phase;

  /// `sha256:<hex>` de los bytes de `basis.json` antes; null si no existía.
  final String? before;
  final String after;
  final String acceptedDraftDigest;
  final String acceptedAt;
  final BasisActor actor;
  final String contextProjectDigest;
  final List<BasisSourceReading> sourceReads;

  /// Siempre la ruta de staging derivada de [operationId].
  final String candidatePath;
  final String digest;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'type': type,
    'projectId': projectId,
    'operationId': operationId,
    'phase': phase.toWireName(),
    'before': before,
    'after': after,
    'acceptedDraftDigest': acceptedDraftDigest,
    'acceptedAt': acceptedAt,
    'actor': actor.toJson(),
    'contextProjectDigest': contextProjectDigest,
    'sourceReads': [for (final r in sourceReads) r.toJson()],
    'candidatePath': candidatePath,
    'digest': digest,
  };
}

const basisTransactionType = 'shipflow.basis.transaction';

/// La única ruta de candidato que un journal de [operationId] puede citar.
String basisCandidatePath(String operationId) =>
    'shipflow/local/basis-staging/$operationId/candidate.json';
