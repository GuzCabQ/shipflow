import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'basis_actor.dart';
import 'basis_payload.dart';

/// Una versión completa de un registro: la primera tiene
/// [previousVersion] null y cada siguiente aumenta de a uno.
final class BasisRecordVersion {
  BasisRecordVersion({
    required this.id,
    required this.version,
    required this.previousVersion,
    required this.payload,
  });

  factory BasisRecordVersion.fromJson(Map<String, Object?> json) =>
      BasisRecordVersion(
        id: json['id']! as String,
        version: json['version']! as int,
        previousVersion: json['previousVersion'] as int?,
        payload: readObject(json['payload'], BasisPayload.fromJson),
      );

  final String id;
  final int version;
  final int? previousVersion;
  final BasisPayload payload;

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'previousVersion': previousVersion,
    'payload': payload.toJson(),
  };
}

/// Una aceptación publicada: el actor y el motivo declarados, el borrador
/// exacto aceptado y los registros nuevos que cambió, enlazado al evento
/// anterior por su huella.
final class BasisEvent {
  BasisEvent({
    required this.revision,
    required this.operationId,
    required this.acceptedAt,
    required this.actor,
    required this.reason,
    required this.draftDigest,
    required this.previousEventDigest,
    required List<BasisRecordVersion> changes,
    required this.eventDigest,
  }) : changes = List.unmodifiable(changes);

  factory BasisEvent.fromJson(Map<String, Object?> json) => BasisEvent(
    revision: json['revision']! as int,
    operationId: json['operationId']! as String,
    acceptedAt: json['acceptedAt']! as String,
    actor: readObject(json['actor'], BasisActor.fromJson),
    reason: json['reason']! as String,
    draftDigest: json['draftDigest']! as String,
    previousEventDigest: json['previousEventDigest'] as String?,
    changes: readObjects(json['changes'], BasisRecordVersion.fromJson),
    eventDigest: json['eventDigest']! as String,
  );

  final int revision;
  final String operationId;

  /// Informativa: la autoridad no depende de la fecha.
  final String acceptedAt;
  final BasisActor actor;
  final String reason;
  final String draftDigest;
  final String? previousEventDigest;
  final List<BasisRecordVersion> changes;
  final String eventDigest;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'operationId': operationId,
    'acceptedAt': acceptedAt,
    'actor': actor.toJson(),
    'reason': reason,
    'draftDigest': draftDigest,
    'previousEventDigest': previousEventDigest,
    'changes': [for (final c in changes) c.toJson()],
    'eventDigest': eventDigest,
  };
}

/// `shipflow/basis.json`: la historia completa de aceptaciones, desde la
/// revisión 1 y sin huecos. El estado actual se deriva de ella.
final class BasisDocument {
  BasisDocument({
    required this.projectId,
    required this.revision,
    required this.producerVersion,
    required List<BasisEvent> events,
    required this.digest,
  }) : events = List.unmodifiable(events);

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory BasisDocument.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'incompatible_version');
    requireSemantic(json['type'] == basisType, 'invalid_schema');
    requireSemantic(
      json['validatorVersion'] == 1 && json['queryVersion'] == 1,
      'incompatible_version',
    );
    return BasisDocument(
      projectId: json['projectId']! as String,
      revision: json['revision']! as int,
      producerVersion: json['producerVersion']! as String,
      events: readObjects(json['events'], BasisEvent.fromJson),
      digest: json['digest']! as String,
    );
  }

  final int schemaVersion = 1;
  final String type = basisType;
  final String projectId;
  final int revision;
  final String producerVersion;
  final int validatorVersion = 1;
  final int queryVersion = 1;
  final List<BasisEvent> events;
  final String digest;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'type': type,
    'projectId': projectId,
    'revision': revision,
    'producerVersion': producerVersion,
    'validatorVersion': validatorVersion,
    'queryVersion': queryVersion,
    'events': [for (final e in events) e.toJson()],
    'digest': digest,
  };
}

const basisType = 'shipflow.basis';
