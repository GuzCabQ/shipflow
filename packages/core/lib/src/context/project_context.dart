import '../recognition/recognition_json.dart';
import 'context_validation.dart';
import 'portable_recognition.dart';

/// El único `kind` de un documento de contexto.
const projectContextKind = 'shipflow.project-context';

/// Quién produjo las observaciones guardadas. Los IDs de plugin son opacos.
final class ContextProducer {
  ContextProducer({
    required this.version,
    required this.recognitionContract,
    required List<String> pluginIds,
  }) : pluginIds = List.unmodifiable(pluginIds);

  factory ContextProducer.fromJson(Map<String, Object?> json) =>
      ContextProducer(
        version: json['version']! as String,
        recognitionContract: json['recognitionContract']! as String,
        pluginIds: readStrings(json['pluginIds']),
      );

  final String version;

  /// Cambia cuando cambia la semántica del detector o del alcance, no por
  /// texto humano ni versión de distribución.
  final String recognitionContract;
  final List<String> pluginIds;

  Map<String, Object?> toJson() => {
    'version': version,
    'recognitionContract': recognitionContract,
    'pluginIds': pluginIds,
  };
}

/// `shipflow/project.json`: el contexto inicial portable, el único documento
/// autoritativo de este corte. Sus rutas se leen desde la carpeta que
/// contiene `shipflow`; ninguna ruta absoluta, Git ni efecto viaja en él.
///
/// El digest se comprueba fuera de core, que no calcula hashes.
final class ProjectContext {
  ProjectContext({
    required this.projectId,
    required this.revision,
    required this.producer,
    required this.observedAt,
    required this.recognition,
    required this.observationDigest,
  }) {
    validateProjectContext(this);
  }

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory ProjectContext.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'schema_version');
    requireSemantic(json['kind'] == projectContextKind, 'kind');
    requireSemantic(json['root'] == '.', 'root');
    return ProjectContext(
      projectId: json['projectId']! as String,
      revision: json['revision']! as int,
      producer: readObject(json['producer'], ContextProducer.fromJson),
      observedAt: json['observedAt']! as String,
      recognition: readObject(
        json['recognition'],
        PortableRecognition.fromJson,
      ),
      observationDigest: json['observationDigest']! as String,
    );
  }

  final int schemaVersion = 1;
  final String kind = projectContextKind;

  /// UUID v4 opaco: no es identidad personal ni autorización.
  final String projectId;
  final String root = '.';

  /// Aumenta sólo al cambiar las observaciones o su productor.
  final int revision;
  final ContextProducer producer;

  /// UTC; cuándo se observó, nunca prueba de vigencia.
  final String observedAt;
  final PortableRecognition recognition;
  final String observationDigest;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'kind': kind,
    'projectId': projectId,
    'root': root,
    'revision': revision,
    'producer': producer.toJson(),
    'observedAt': observedAt,
    'recognition': recognition.toJson(),
    'observationDigest': observationDigest,
  };
}

/// Las reglas del documento que su schema no expresa, salvo el digest.
void validateProjectContext(ProjectContext context) {
  requireSemantic(isUuidV4(context.projectId), 'project_id');
  requireSemantic(context.revision >= 1, 'revision');
  requireSemantic(isUtcTimestamp(context.observedAt), 'observed_at');
  requireSemantic(isSha256Hex(context.observationDigest), 'digest_form');
  final declared = context.producer.pluginIds;
  final proposed = {for (final c in context.recognition.candidates) c.pluginId};
  requireSemantic(
    declared.toSet().length == declared.length &&
        declared.toSet().containsAll(proposed) &&
        proposed.containsAll(declared),
    'producer_plugins',
  );
}
