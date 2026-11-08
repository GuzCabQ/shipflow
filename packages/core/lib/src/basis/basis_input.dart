import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'basis_actor.dart';
import 'basis_payload.dart';

/// Un cambio propuesto: crea (sin [targetId] ni [expectedVersion]) o
/// revisa la versión actual exacta de un registro. [key] lo identifica
/// dentro del lote; otros cambios lo citan como `new:<key>`.
final class BasisChange {
  BasisChange({
    required this.key,
    required this.targetId,
    required this.expectedVersion,
    required this.payload,
  });

  factory BasisChange.fromJson(Map<String, Object?> json) => BasisChange(
    key: json['key']! as String,
    targetId: json['targetId'] as String?,
    expectedVersion: json['expectedVersion'] as int?,
    payload: readObject(json['payload'], BasisPayload.fromJson),
  );

  final String key;
  final String? targetId;
  final int? expectedVersion;
  final BasisPayload payload;

  bool get creates => targetId == null;

  Map<String, Object?> toJson() => {
    'key': key,
    'targetId': targetId,
    'expectedVersion': expectedVersion,
    'payload': payload.toJson(),
  };
}

/// Lo que una persona o una automatización propone: cambios, actor local
/// declarado, motivo y la base esperada. No concede IDs, aprobaciones ni
/// observaciones de fuentes.
final class BasisInput {
  BasisInput({
    required this.projectId,
    required this.expectedBasisDigest,
    required this.actor,
    required this.reason,
    required List<BasisChange> changes,
  }) : changes = List.unmodifiable(changes);

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory BasisInput.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'incompatible_version');
    requireSemantic(json['type'] == basisInputType, 'invalid_schema');
    return BasisInput(
      projectId: json['projectId']! as String,
      expectedBasisDigest: json['expectedBasisDigest'] as String?,
      actor: readObject(json['actor'], BasisActor.fromJson),
      reason: json['reason']! as String,
      changes: readObjects(json['changes'], BasisChange.fromJson),
    );
  }

  final int schemaVersion = 1;
  final String type = basisInputType;
  final String projectId;

  /// La huella de `basis.json` esperada; null sólo si no existe.
  final String? expectedBasisDigest;
  final BasisActor actor;
  final String reason;
  final List<BasisChange> changes;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'type': type,
    'projectId': projectId,
    'expectedBasisDigest': expectedBasisDigest,
    'actor': actor.toJson(),
    'reason': reason,
    'changes': [for (final c in changes) c.toJson()],
  };
}

const basisInputType = 'shipflow.basis.input';
