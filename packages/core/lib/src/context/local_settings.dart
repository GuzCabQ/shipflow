import '../recognition/recognition_json.dart';
import 'context_enums.dart';
import 'context_validation.dart';

/// La identidad local del repositorio al que se vinculó una elección. No es
/// portable: otra copia tiene otras rutas y otro vínculo.
final class GitBinding {
  GitBinding({
    required this.repositoryRoot,
    required this.gitDir,
    required this.commonDir,
    required this.prefix,
  }) {
    final absolute = [repositoryRoot, gitDir, commonDir];
    requireSemantic(
      absolute.every((p) => p.startsWith('/') && !p.contains('\u0000')) &&
          !prefix.startsWith('/') &&
          !prefix.contains('\u0000'),
      'binding',
    );
  }

  factory GitBinding.fromJson(Map<String, Object?> json) => GitBinding(
    repositoryRoot: json['repositoryRoot']! as String,
    gitDir: json['gitDir']! as String,
    commonDir: json['commonDir']! as String,
    prefix: json['prefix']! as String,
  );

  final String repositoryRoot;
  final String gitDir;
  final String commonDir;

  /// Desde la raíz Git hasta la raíz tecnológica; vacío si coinciden.
  final String prefix;

  Map<String, Object?> toJson() => {
    'repositoryRoot': repositoryRoot,
    'gitDir': gitDir,
    'commonDir': commonDir,
    'prefix': prefix,
  };
}

/// El bloque propio en el exclude local: dónde está, cuál es y su huella.
final class ManagedExcludeRecord {
  ManagedExcludeRecord({
    required this.path,
    required this.blockId,
    required this.sha256,
  }) {
    requireSemantic(
      path.startsWith('/') && isSha256Hex(blockId) && isSha256Hex(sha256),
      'managed_exclude',
    );
  }

  factory ManagedExcludeRecord.fromJson(Map<String, Object?> json) =>
      ManagedExcludeRecord(
        path: json['path']! as String,
        blockId: json['blockId']! as String,
        sha256: json['sha256']! as String,
      );

  final String path;
  final String blockId;

  /// SHA-256 del bloque propio normalizado, no del archivo entero.
  final String sha256;

  Map<String, Object?> toJson() => {
    'path': path,
    'blockId': blockId,
    'sha256': sha256,
  };
}

/// `shipflow/local/settings.json`: la intención de conservación de esta
/// copia y lo que se aplicó. Es evidencia previa, nunca prueba suficiente
/// del estado presente.
final class LocalSettings {
  LocalSettings({
    required this.projectId,
    required this.choice,
    required this.binding,
    required this.applied,
    required this.managedExclude,
  }) {
    requireSemantic(isUuidV4(projectId), 'project_id');
    requireSemantic(
      choice != SharingChoice.pending || (!applied && managedExclude == null),
      'settings_pending',
    );
    requireSemantic(
      choice != SharingChoice.local ||
          !applied ||
          (binding != null && managedExclude != null),
      'settings_local',
    );
  }

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory LocalSettings.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'schema_version');
    return LocalSettings(
      projectId: json['projectId']! as String,
      choice: SharingChoice.fromWireName(json['choice']! as String),
      binding: _optional(json['binding'], GitBinding.fromJson),
      applied: json['applied']! as bool,
      managedExclude: _optional(
        json['managedExclude'],
        ManagedExcludeRecord.fromJson,
      ),
    );
  }

  final int schemaVersion = 1;
  final String projectId;
  final SharingChoice choice;
  final GitBinding? binding;
  final bool applied;
  final ManagedExcludeRecord? managedExclude;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'projectId': projectId,
    'choice': choice.toWireName(),
    'binding': binding?.toJson(),
    'applied': applied,
    'managedExclude': managedExclude?.toJson(),
  };
}

T? _optional<T>(Object? json, T Function(Map<String, Object?>) read) =>
    json == null ? null : readObject(json, read);
