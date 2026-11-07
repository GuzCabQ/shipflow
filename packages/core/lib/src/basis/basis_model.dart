import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'basis_enums.dart';
import 'basis_payload.dart';

/// A qué aplica un registro: `project`, prefijos de ruta relativos por
/// segmentos, o `unknown`. El orden de [paths] se conserva tal cual.
final class BasisScope {
  BasisScope({required this.kind, required List<String> paths})
    : paths = List.unmodifiable(paths);

  BasisScope.project() : this(kind: BasisScopeKind.project, paths: const []);

  BasisScope.unknown() : this(kind: BasisScopeKind.unknown, paths: const []);

  factory BasisScope.fromJson(Map<String, Object?> json) => BasisScope(
    kind: BasisScopeKind.fromWireName(json['kind']! as String),
    paths: readStrings(json['paths']),
  );

  final BasisScopeKind kind;
  final List<String> paths;

  /// Si [other] designa el mismo ámbito: mismo tipo y el mismo conjunto de
  /// prefijos, sin importar su orden.
  bool sameAs(BasisScope other) =>
      kind == other.kind &&
      paths.toSet().length == other.paths.toSet().length &&
      paths.toSet().containsAll(other.paths);

  Map<String, Object?> toJson() => {'kind': kind.toWireName(), 'paths': paths};
}

/// Quién declara una aceptación en esta copia. La autoridad es local y
/// declarada: no se autentica que [label] represente a una persona.
final class BasisActor {
  BasisActor({required this.label, required this.role, required this.scope});

  factory BasisActor.fromJson(Map<String, Object?> json) {
    requireSemantic(json['authority'] == 'local_declared', 'invalid_schema');
    return BasisActor(
      label: json['label']! as String,
      role: json['role']! as String,
      scope: readObject(json['scope'], BasisScope.fromJson),
    );
  }

  final String label;
  final String role;
  final String authority = 'local_declared';
  final BasisScope scope;

  Map<String, Object?> toJson() => {
    'label': label,
    'role': role,
    'authority': authority,
    'scope': scope.toJson(),
  };
}

/// Una versión exacta citada: un ID persistido o, sólo en una entrada,
/// `new:<key>` de un registro creado en el mismo lote.
final class BasisReference {
  BasisReference({required this.ref, required this.version});

  factory BasisReference.fromJson(Map<String, Object?> json) => BasisReference(
    ref: json['ref']! as String,
    version: json['version']! as int,
  );

  final String ref;
  final int version;

  Map<String, Object?> toJson() => {'ref': ref, 'version': version};
}

/// La decisión aceptada a la que corresponde un pendiente de revisión: la
/// regla [ref] en su versión [version], y quién revisará si se sabe.
final class BasisDecisionReview {
  BasisDecisionReview({
    required this.ref,
    required this.version,
    required this.reviewer,
  });

  factory BasisDecisionReview.fromJson(Map<String, Object?> json) =>
      BasisDecisionReview(
        ref: json['ref']! as String,
        version: json['version']! as int,
        reviewer: json['reviewer'] as String?,
      );

  final String ref;
  final int version;

  /// Null: responsable por definir.
  final String? reviewer;

  Map<String, Object?> toJson() => {
    'ref': ref,
    'version': version,
    'reviewer': reviewer,
  };
}

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
