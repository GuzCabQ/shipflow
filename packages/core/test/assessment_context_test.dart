import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assessment_fixtures.dart';

void main() {
  AssessmentContextBasis basis({
    List<AssessmentUnit>? units,
    List<AssessmentRecognitionInput>? inputs,
    List<AssessmentContextLink>? links,
  }) => AssessmentContextBasis(
    units:
        units ??
        [
          AssessmentUnit(id: rootUnit, path: '.', label: 'example'),
          AssessmentUnit(
            id: widgetsUnit,
            path: 'packages/widgets',
            label: 'widgets',
          ),
        ],
    recognitionInputs:
        inputs ??
        [
          AssessmentRecognitionInput(
            path: 'manifest.example',
            sha256: hashOf('b'),
          ),
        ],
    contextLinks: links ?? [readme()],
  );
  final snapshot = AssessmentSnapshot.fromJson(snapshotJson());

  test('the exact basis of the cited context matches', () {
    expect(() => validateAssessmentContext(snapshot, basis()), returnsNormally);
  });

  test('a foreign unit with the right digest is rejected', () {
    final foreign = basis(
      units: [
        AssessmentUnit(id: rootUnit, path: '.', label: 'example'),
        AssessmentUnit(id: 'u_other', path: 'packages/other', label: 'other'),
      ],
    );
    expect(
      () => validateAssessmentContext(snapshot, foreign),
      rejectsWith('context_units'),
    );
  });

  test('a renamed unit is not the cited one', () {
    final renamed = basis(
      units: [
        AssessmentUnit(id: rootUnit, path: '.', label: 'example'),
        AssessmentUnit(id: widgetsUnit, path: 'packages/widgets', label: 'w'),
      ],
    );
    expect(
      () => validateAssessmentContext(snapshot, renamed),
      rejectsWith('context_units'),
    );
  });

  test('a required recognition source must be sealed with its digest', () {
    final missing = basis(
      inputs: [AssessmentRecognitionInput(path: 'other.example', sha256: null)],
    );
    expect(
      () => validateAssessmentContext(snapshot, missing),
      rejectsWith('context_recognition'),
    );
    final changed = basis(
      inputs: [
        AssessmentRecognitionInput(
          path: 'manifest.example',
          sha256: hashOf('e'),
        ),
      ],
    );
    expect(
      () => validateAssessmentContext(snapshot, changed),
      rejectsWith('context_recognition'),
    );
  });

  test('an invented or an omitted link is rejected', () {
    expect(
      () => validateAssessmentContext(snapshot, basis(links: [])),
      rejectsWith('context_links'),
    );
    final extra = AssessmentContextLink(
      kind: AssessmentLinkKind.candidateSource,
      sourceId: 's_other',
      sourcePath: 'docs',
      label: 'documentation',
      targetUnitId: null,
    );
    expect(
      () =>
          validateAssessmentContext(snapshot, basis(links: [readme(), extra])),
      rejectsWith('context_links'),
    );
  });
}

AssessmentContextLink readme() => AssessmentContextLink(
  kind: AssessmentLinkKind.candidateSource,
  sourceId: 's_readme',
  sourcePath: 'README.md',
  label: 'documentation',
  targetUnitId: null,
);
