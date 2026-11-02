import 'package:core/core.dart';

import 'assessment_fixtures.dart';

typedef SerializationCase = (
  Map<String, Object?>,
  Map<String, Object?> Function(Map<String, Object?>),
);

/// Una instancia canónica de cada clase serializable del levantamiento, con
/// un valor distinguible en cada campo, y cómo reconstruirla.
Map<String, SerializationCase> assessmentSerializationCases() {
  final document = AssessmentDocument.fromJson(
    documentJson(previous: snapshotJson(), revision: 2),
  );
  return {
    ..._recordCases(document.current),
    ..._documentCases(document),
    ..._resultCases(document.current),
  };
}

Map<String, SerializationCase> _recordCases(AssessmentSnapshot snapshot) {
  final claim = snapshot.claims.single;
  return {
    'AssessmentUnit': (
      snapshot.units.last.toJson(),
      (j) => AssessmentUnit.fromJson(j).toJson(),
    ),
    'AssessmentInput': (
      snapshot.inputs.last.toJson(),
      (j) => AssessmentInput.fromJson(j).toJson(),
    ),
    'AssessmentFile': (
      snapshot.files.last.toJson(),
      (j) => AssessmentFile.fromJson(j).toJson(),
    ),
    'AssessmentProducer': (
      snapshot.producer.toJson(),
      (j) => AssessmentProducer.fromJson(j).toJson(),
    ),
    'AssessmentEvidence': (
      claim.evidence.toJson(),
      (j) => AssessmentEvidence.fromJson(j).toJson(),
    ),
    'AssessmentClaim': (
      claim.toJson(),
      (j) => AssessmentClaim.fromJson(j).toJson(),
    ),
    ..._claimPartCases(snapshot),
  };
}

Map<String, SerializationCase> _claimPartCases(AssessmentSnapshot snapshot) => {
  'AssessmentSourceMetadata': (
    const AssessmentSourceMetadata(
      directive: 'import',
      conditionText: 'flag == true',
    ).toJson(),
    (j) => AssessmentSourceMetadata.fromJson(j).toJson(),
  ),
  'AssessmentWitness': (
    snapshot.witnesses.first.toJson(),
    (j) => AssessmentWitness.fromJson(j).toJson(),
  ),
  'AssessmentContextLink': (
    snapshot.contextLinks.single.toJson(),
    (j) => AssessmentContextLink.fromJson(j).toJson(),
  ),
  'AssessmentDiagnostic': (
    _diagnostic().toJson(),
    (j) => AssessmentDiagnostic.fromJson(j).toJson(),
  ),
};

AssessmentDiagnostic _diagnostic() => AssessmentDiagnostic(
  code: 'source_unreadable',
  path: 'lib',
  consequence: 'references_unknown',
  actionCode: 'check_permissions',
  count: 3,
  examples: ['lib/a.src', 'lib/b.src'],
);

Map<String, SerializationCase> _documentCases(AssessmentDocument document) {
  final snapshot = document.current;
  final input = AssessmentRecognitionInput(
    path: 'manifest.example',
    sha256: hashOf('b'),
  );
  return {
    'AssessmentSnapshot': (
      snapshot.toJson(),
      (j) => AssessmentSnapshot.fromJson(j).toJson(),
    ),
    'AssessmentDocument': (
      document.toJson(),
      (j) => AssessmentDocument.fromJson(j).toJson(),
    ),
    'AssessmentRecognitionInput': (
      input.toJson(),
      (j) => AssessmentRecognitionInput.fromJson(j).toJson(),
    ),
    'AssessmentContextBasis': (
      AssessmentContextBasis(
        units: snapshot.units,
        recognitionInputs: [input],
        contextLinks: snapshot.contextLinks,
      ).toJson(),
      (j) => AssessmentContextBasis.fromJson(j).toJson(),
    ),
    ..._derivedCases(snapshot),
  };
}

Map<String, SerializationCase> _derivedCases(AssessmentSnapshot snapshot) => {
  'AssessmentLimits': (
    AssessmentLimits.forProfile(AssessmentProfile.extended).toJson(),
    (j) => AssessmentLimits.fromJson(j).toJson(),
  ),
  'AssessmentConnection': (
    projectAssessment(snapshot).single.toJson(),
    (j) => AssessmentConnection.fromJson(j).toJson(),
  ),
  'AssessmentComparison': (
    _comparison.toJson(),
    (j) => AssessmentComparison.fromJson(j).toJson(),
  ),
  'AssessmentTransaction': (
    AssessmentTransaction(
      projectId: assessmentProjectId,
      operationId: '22222222-2222-4222-8222-222222222222',
      before: hashOf('1'),
      after: hashOf('2'),
      state: AssessmentTransactionState.published,
      baseContextDigest: contextHash,
      snapshotId: hashOf('a'),
    ).toJson(),
    (j) => AssessmentTransaction.fromJson(j).toJson(),
  ),
};

const _comparison = AssessmentComparison(
  addedReferences: 1,
  repeatedReferences: 2,
  notObservedNow: 3,
);

Map<String, SerializationCase> _resultCases(AssessmentSnapshot snapshot) {
  final effects = AssessmentEffects(
    created: ['shipflow/assessment.json'],
    replaced: ['shipflow/local/x'],
    removed: ['shipflow/local/y'],
    published: true,
    gitQueries: 4,
  );
  final action = AssessmentNextAction(
    argv: ['shipflow', 'assess', '--show'],
    purpose: 'inspect_saved',
    effect: AssessmentActionEffect.readOnly,
  );
  return {
    'AssessmentEffects': (
      effects.toJson(),
      (j) => AssessmentEffects.fromJson(j).toJson(),
    ),
    'AssessmentNextAction': (
      action.toJson(),
      (j) => AssessmentNextAction.fromJson(j).toJson(),
    ),
    'AssessmentResult': (
      _result(snapshot, effects, action).toJson(),
      (j) => AssessmentResult.fromJson(j).toJson(),
    ),
  };
}

AssessmentResult _result(
  AssessmentSnapshot snapshot,
  AssessmentEffects effects,
  AssessmentNextAction action,
) => AssessmentResult(
  operation: AssessmentOperation.observe,
  exitCode: 65,
  outcome: AssessmentOutcome.saved,
  freshness: AssessmentFreshness.current,
  coverage: snapshot.coverage,
  snapshot: snapshot,
  diagnostics: [_diagnostic()],
  effects: effects,
  nextActions: [action],
  comparison: _comparison,
  retiredRevision: 1,
);
