import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'assessment_claims.dart';
import 'assessment_enums.dart';
import 'assessment_sources.dart';
import 'assessment_validation.dart';
import 'assessment_witnesses.dart';

/// El único `kind` del documento de levantamiento.
const assessmentKind = 'shipflow.assessment';

/// Una observación sellada: quién la produjo, sobre qué contexto citado, qué
/// inventario y bytes leyó, qué afirmó y con qué testigos. Su identidad es
/// el SHA-256 de su forma canónica sin `snapshotId` ni `observedAt`, que se
/// comprueba fuera de core.
final class AssessmentSnapshot {
  AssessmentSnapshot({
    required this.snapshotId,
    required this.observedAt,
    required this.producer,
    required this.contextDigest,
    required this.profile,
    required this.coverage,
    required this.inventoryComplete,
    required List<AssessmentUnit> units,
    required List<AssessmentInput> inputs,
    required List<AssessmentFile> files,
    required List<AssessmentClaim> claims,
    required List<AssessmentWitness> witnesses,
    required List<AssessmentContextLink> contextLinks,
    required List<AssessmentDiagnostic> diagnostics,
  }) : units = List.unmodifiable(units),
       inputs = List.unmodifiable(inputs),
       files = List.unmodifiable(files),
       claims = List.unmodifiable(claims),
       witnesses = List.unmodifiable(witnesses),
       contextLinks = List.unmodifiable(contextLinks),
       diagnostics = List.unmodifiable(diagnostics) {
    validateAssessmentSnapshot(this);
  }

  factory AssessmentSnapshot.fromJson(Map<String, Object?> json) =>
      AssessmentSnapshot(
        snapshotId: json['snapshotId']! as String,
        observedAt: json['observedAt']! as String,
        producer: readObject(json['producer'], AssessmentProducer.fromJson),
        contextDigest: json['contextDigest']! as String,
        profile: AssessmentProfile.fromWireName(json['profile']! as String),
        coverage: AssessmentCoverage.fromWireName(json['coverage']! as String),
        inventoryComplete: json['inventoryComplete']! as bool,
        units: readObjects(json['units'], AssessmentUnit.fromJson),
        inputs: readObjects(json['inputs'], AssessmentInput.fromJson),
        files: readObjects(json['files'], AssessmentFile.fromJson),
        claims: readObjects(json['claims'], AssessmentClaim.fromJson),
        witnesses: readObjects(json['witnesses'], AssessmentWitness.fromJson),
        contextLinks: readObjects(
          json['contextLinks'],
          AssessmentContextLink.fromJson,
        ),
        diagnostics: readObjects(
          json['diagnostics'],
          AssessmentDiagnostic.fromJson,
        ),
      );

  final String snapshotId;

  /// UTC; cuándo se observó, nunca prueba de vigencia.
  final String observedAt;
  final AssessmentProducer producer;

  /// SHA-256 de los bytes exactos del contexto citado.
  final String contextDigest;
  final AssessmentProfile profile;
  final AssessmentCoverage coverage;
  final bool inventoryComplete;
  final List<AssessmentUnit> units;
  final List<AssessmentInput> inputs;
  final List<AssessmentFile> files;
  final List<AssessmentClaim> claims;
  final List<AssessmentWitness> witnesses;
  final List<AssessmentContextLink> contextLinks;
  final List<AssessmentDiagnostic> diagnostics;

  Map<String, Object?> toJson() => {
    'snapshotId': snapshotId,
    'observedAt': observedAt,
    'producer': producer.toJson(),
    'contextDigest': contextDigest,
    'profile': profile.toWireName(),
    'coverage': coverage.toWireName(),
    'inventoryComplete': inventoryComplete,
    'units': [for (final u in units) u.toJson()],
    'inputs': [for (final i in inputs) i.toJson()],
    'files': [for (final f in files) f.toJson()],
    'claims': [for (final c in claims) c.toJson()],
    'witnesses': [for (final w in witnesses) w.toJson()],
    'contextLinks': [for (final l in contextLinks) l.toJson()],
    'diagnostics': [for (final d in diagnostics) d.toJson()],
  };
}

/// `shipflow/assessment.json`: la revisión vigente y la anterior, completas.
/// La revisión sólo aumenta al publicar un snapshot nuevo, y la anterior es
/// exactamente la vigente que reemplazó.
final class AssessmentDocument {
  AssessmentDocument({
    required this.projectId,
    required this.revision,
    required this.current,
    required this.previous,
  }) {
    validateAssessmentDocument(this);
  }

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory AssessmentDocument.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'schema_version');
    requireSemantic(json['kind'] == assessmentKind, 'kind');
    return AssessmentDocument(
      projectId: json['projectId']! as String,
      revision: json['revision']! as int,
      current: readObject(json['current'], AssessmentSnapshot.fromJson),
      previous: json['previous'] == null
          ? null
          : readObject(json['previous'], AssessmentSnapshot.fromJson),
    );
  }

  final int schemaVersion = 1;
  final String kind = assessmentKind;
  final String projectId;
  final int revision;
  final AssessmentSnapshot current;
  final AssessmentSnapshot? previous;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'kind': kind,
    'projectId': projectId,
    'revision': revision,
    'current': current.toJson(),
    'previous': previous?.toJson(),
  };
}

/// Las reglas cruzadas de [s] que su schema no expresa, salvo las huellas.
void validateAssessmentSnapshot(AssessmentSnapshot s) => validateSnapshotParts((
  snapshotId: s.snapshotId,
  observedAt: s.observedAt,
  contract: s.producer.contract,
  contextDigest: s.contextDigest,
  coverage: s.coverage,
  inventoryComplete: s.inventoryComplete,
  units: s.units,
  inputs: s.inputs,
  files: s.files,
  claims: s.claims,
  witnesses: s.witnesses,
  contextLinks: s.contextLinks,
  diagnostics: s.diagnostics,
));

/// Las reglas del documento que su schema no expresa, salvo las huellas.
void validateAssessmentDocument(AssessmentDocument document) {
  requireSemantic(isUuidV4(document.projectId), 'project_id');
  requireSemantic(
    document.revision >= 1 &&
        (document.previous == null || document.revision >= 2),
    'revision',
  );
}
