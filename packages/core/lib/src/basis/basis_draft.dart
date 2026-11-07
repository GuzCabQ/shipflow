import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'basis_input.dart';
import 'basis_model.dart';

/// Una fuente local leída al preparar: su ruta y la huella del contenido.
final class BasisSourceReading {
  BasisSourceReading({required this.path, required this.digest});

  factory BasisSourceReading.fromJson(Map<String, Object?> json) =>
      BasisSourceReading(
        path: json['path']! as String,
        digest: json['digest']! as String,
      );

  final String path;
  final String digest;

  Map<String, Object?> toJson() => {'path': path, 'digest': digest};
}

/// `shipflow/local/basis-draft.json`: un candidato preparado, no aceptado.
/// Sus cambios ya tienen IDs y versiones; su huella es lo que se acepta.
final class BasisDraft {
  BasisDraft({
    required this.projectId,
    required this.operationId,
    required this.createdAt,
    required this.expectedBasisDigest,
    required this.contextProjectDigest,
    required this.input,
    required List<BasisRecordVersion> preparedChanges,
    required List<BasisSourceReading> sourceReads,
    required this.digest,
  }) : preparedChanges = List.unmodifiable(preparedChanges),
       sourceReads = List.unmodifiable(sourceReads);

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory BasisDraft.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'incompatible_version');
    requireSemantic(json['type'] == basisDraftType, 'invalid_schema');
    return BasisDraft(
      projectId: json['projectId']! as String,
      operationId: json['operationId']! as String,
      createdAt: json['createdAt']! as String,
      expectedBasisDigest: json['expectedBasisDigest'] as String?,
      contextProjectDigest: json['contextProjectDigest']! as String,
      input: readObject(json['input'], BasisInput.fromJson),
      preparedChanges: readObjects(
        json['preparedChanges'],
        BasisRecordVersion.fromJson,
      ),
      sourceReads: readObjects(
        json['sourceReads'],
        BasisSourceReading.fromJson,
      ),
      digest: json['digest']! as String,
    );
  }

  final int schemaVersion = 1;
  final String type = basisDraftType;
  final String projectId;
  final String operationId;
  final String createdAt;
  final String? expectedBasisDigest;

  /// La huella de `project.json` con la que se preparó: precondición de
  /// publicación, no de consulta.
  final String contextProjectDigest;
  final BasisInput input;
  final List<BasisRecordVersion> preparedChanges;
  final List<BasisSourceReading> sourceReads;
  final String digest;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'type': type,
    'projectId': projectId,
    'operationId': operationId,
    'createdAt': createdAt,
    'expectedBasisDigest': expectedBasisDigest,
    'contextProjectDigest': contextProjectDigest,
    'input': input.toJson(),
    'preparedChanges': [for (final c in preparedChanges) c.toJson()],
    'sourceReads': [for (final r in sourceReads) r.toJson()],
    'digest': digest,
  };
}

const basisDraftType = 'shipflow.basis.draft';
