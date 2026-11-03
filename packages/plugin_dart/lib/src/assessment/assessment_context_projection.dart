import 'package:core/core.dart';

import 'assessment_ids.dart';

/// Lo que el contexto V2 citado exige del levantamiento, calculado sólo
/// desde el documento: sus unidades con ID derivado de la ruta, cada ruta de
/// evidencia como fuente de reconocimiento sellada, las dependencias
/// locales declaradas y las fuentes candidatas observadas. No vuelve al
/// sistema de archivos ni abre ninguna fuente candidata.
AssessmentContextBasis projectDartAssessmentContext(ProjectContext context) {
  final recognition = context.recognition;
  final units = _units(recognition);
  final byPath = {for (final u in units) u.path: u.id};
  return AssessmentContextBasis(
    units: units,
    recognitionInputs: _recognitionInputs(recognition),
    contextLinks: [
      ..._declared(recognition, byPath),
      ..._candidates(recognition),
    ]..sort(_byKindAndSource),
  );
}

/// La identidad V3 de la unidad en [path].
String unitIdOf(String path) => assessmentId(unitIdPrefix, unitTuple(path));

/// Dos unidades en la misma ruta no se fusionan: el contexto no se puede
/// representar.
List<AssessmentUnit> _units(PortableRecognition recognition) {
  final units = [
    for (final unit in recognition.units)
      AssessmentUnit(
        id: unitIdOf(unit.path),
        path: unit.path,
        label: unit.name,
      ),
  ]..sort((a, b) => a.id.compareTo(b.id));
  requireSemantic(
    {for (final u in units) u.path}.length == units.length,
    'context_units',
  );
  return units;
}

/// Cada ruta de evidencia, una vez, con la huella completa de sus bytes si
/// la de V2 es comparable.
List<AssessmentRecognitionInput> _recognitionInputs(
  PortableRecognition recognition,
) {
  final byPath = <String, String?>{};
  for (final evidence in recognition.evidence) {
    final hash = fullByteHash(evidence.fingerprint);
    byPath[evidence.path] = byPath.containsKey(evidence.path)
        ? byPath[evidence.path] ?? hash
        : hash;
  }
  return [
    for (final path in byPath.keys.toList()..sort())
      AssessmentRecognitionInput(path: path, sha256: byPath[path]),
  ];
}

/// Sólo las dependencias locales: su ID V2, la ruta de su primera
/// evidencia por ID, su nombre declarado y la unidad de destino si está
/// corroborada. Una evidencia ausente no se inventa.
List<AssessmentContextLink> _declared(
  PortableRecognition recognition,
  Map<String, String> unitIds,
) {
  final evidence = {for (final e in recognition.evidence) e.id: e};
  return [
    for (final relation in recognition.relations)
      if (relation.kind == RelationKind.localDependency)
        AssessmentContextLink(
          kind: AssessmentLinkKind.declaredDependency,
          sourceId: relation.id,
          sourcePath: _firstEvidence(relation, evidence).path,
          label: relation.declaredName ?? relation.targetPath ?? relation.id,
          targetUnitId: relation.status == RelationStatus.corroborated
              ? unitIds[relation.targetPath]
              : null,
        ),
  ];
}

RecognitionEvidence _firstEvidence(
  RecognitionRelation relation,
  Map<String, RecognitionEvidence> evidence,
) {
  final ids = [...relation.evidenceIds]..sort();
  requireSemantic(
    ids.isNotEmpty && evidence.containsKey(ids.first),
    'context_links',
  );
  return evidence[ids.first]!;
}

/// Sólo las fuentes candidatas observadas, con su clave V3: V2 no les da
/// ID. Siguen sin inspeccionar.
List<AssessmentContextLink> _candidates(PortableRecognition recognition) => [
  for (final source in recognition.contextSources)
    if (source.reason == ContextReason.observed)
      AssessmentContextLink(
        kind: AssessmentLinkKind.candidateSource,
        sourceId: assessmentId(
          candidateIdPrefix,
          candidateTuple(
            source.scopePath,
            source.path,
            source.kind.toWireName(),
          ),
        ),
        sourcePath: source.path,
        label: source.kind.toWireName(),
        targetUnitId: null,
      ),
];

int _byKindAndSource(AssessmentContextLink a, AssessmentContextLink b) {
  final kind = a.kind.toWireName().compareTo(b.kind.toWireName());
  return kind != 0 ? kind : a.sourceId.compareTo(b.sourceId);
}
