import '../recognition/recognition_json.dart';
import 'context_enums.dart';
import 'context_validation.dart';

/// Las huellas de un destino antes y después: SHA-256 de sus bytes
/// completos, o null si el destino está ausente, nunca «desconocido».
final class TransactionTarget {
  TransactionTarget({
    required this.resource,
    required this.before,
    required this.after,
  }) {
    requireSemantic(
      [before, after].every((h) => h == null || isSha256Hex(h)),
      'targets',
    );
  }

  factory TransactionTarget.fromJson(Map<String, Object?> json) =>
      TransactionTarget(
        resource: TransactionResource.fromWireName(json['resource']! as String),
        before: json['before'] as String?,
        after: json['after'] as String?,
      );

  final TransactionResource resource;
  final String? before;
  final String? after;

  Map<String, Object?> toJson() => {
    'resource': resource.toWireName(),
    'before': before,
    'after': after,
  };
}

/// Los archivos preparados de una operación, relativos a `shipflow/`.
final class TransactionStaging {
  const TransactionStaging({
    required this.project,
    required this.settingsBefore,
    required this.settingsAfter,
  });

  factory TransactionStaging.fromJson(Map<String, Object?> json) =>
      TransactionStaging(
        project: json['project'] as String?,
        settingsBefore: json['settingsBefore'] as String?,
        settingsAfter: json['settingsAfter'] as String?,
      );

  final String? project;
  final String? settingsBefore;
  final String? settingsAfter;

  Map<String, Object?> toJson() => {
    'project': project,
    'settingsBefore': settingsBefore,
    'settingsAfter': settingsAfter,
  };
}

/// El bloque exclude propio antes y después, o su ausencia. Nunca reglas
/// ajenas: el archivo se recompone sobre el before que siga presente.
final class TransactionExclude {
  const TransactionExclude({
    required this.blockId,
    required this.beforeBlock,
    required this.afterBlock,
  });

  factory TransactionExclude.fromJson(Map<String, Object?> json) =>
      TransactionExclude(
        blockId: json['blockId'] as String?,
        beforeBlock: json['beforeBlock'] as String?,
        afterBlock: json['afterBlock'] as String?,
      );

  final String? blockId;
  final String? beforeBlock;
  final String? afterBlock;

  Map<String, Object?> toJson() => {
    'blockId': blockId,
    'beforeBlock': beforeBlock,
    'afterBlock': afterBlock,
  };
}

/// Los nombres de staging que puede usar la operación [operationId].
String stagedProjectPath(String operationId) =>
    'local/staging/$operationId/project.json';
String stagedSettingsBeforePath(String operationId) =>
    'local/staging/$operationId/settings.before.json';
String stagedSettingsAfterPath(String operationId) =>
    'local/staging/$operationId/settings.after.json';

/// `shipflow/local/transaction.json`: el intento en curso. No autoriza
/// rutas: cada destino se recalcula desde raíces comprobadas, y su staging
/// sólo puede nombrar los archivos previstos de su propia operación.
final class ContextTransaction {
  ContextTransaction({
    required this.operationId,
    required this.projectId,
    required this.operation,
    required this.choice,
    required this.phase,
    required List<TransactionTarget> targets,
    required this.staging,
    required this.exclude,
  }) : targets = List.unmodifiable(targets) {
    requireSemantic(isUuidV4(operationId) && isUuidV4(projectId), 'ids');
    final resources = {for (final t in targets) t.resource};
    requireSemantic(
      targets.isNotEmpty && resources.length == targets.length,
      'targets',
    );
    requireSemantic(
      _expected(staging.project, stagedProjectPath(operationId)) &&
          _expected(
            staging.settingsBefore,
            stagedSettingsBeforePath(operationId),
          ) &&
          _expected(
            staging.settingsAfter,
            stagedSettingsAfterPath(operationId),
          ),
      'staging',
    );
    final blockId = exclude.blockId;
    requireSemantic(blockId == null || isSha256Hex(blockId), 'exclude');
  }

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory ContextTransaction.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'schema_version');
    return ContextTransaction(
      operationId: json['operationId']! as String,
      projectId: json['projectId']! as String,
      operation: TransactionOperation.fromWireName(
        json['operation']! as String,
      ),
      choice: SharingChoice.fromWireName(json['choice']! as String),
      phase: TransactionPhase.fromWireName(json['phase']! as String),
      targets: readObjects(json['targets'], TransactionTarget.fromJson),
      staging: readObject(json['staging'], TransactionStaging.fromJson),
      exclude: readObject(json['exclude'], TransactionExclude.fromJson),
    );
  }

  final int schemaVersion = 1;
  final String operationId;
  final String projectId;
  final TransactionOperation operation;
  final SharingChoice choice;
  final TransactionPhase phase;
  final List<TransactionTarget> targets;
  final TransactionStaging staging;
  final TransactionExclude exclude;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'operationId': operationId,
    'projectId': projectId,
    'operation': operation.toWireName(),
    'choice': choice.toWireName(),
    'phase': phase.toWireName(),
    'targets': [for (final t in targets) t.toJson()],
    'staging': staging.toJson(),
    'exclude': exclude.toJson(),
  };
}

bool _expected(String? named, String expected) =>
    named == null || named == expected;
