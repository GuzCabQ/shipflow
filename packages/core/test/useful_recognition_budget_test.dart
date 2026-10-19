import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assembler_support.dart';

/// Una evidencia con rol y etiqueta, un candidato, una unidad, una relación
/// hacia ella, una fuente candidata y una omisión, con texto no ASCII. Al
/// ser reconocido suma las dos acciones de la propuesta: 12 elementos.
final _contribution = contribution(
  candidates: [
    candidate('c', ['e0001']),
  ],
  units: [
    unit('u0001', 'añ', ['e0001']),
  ],
  evidence: const [
    RecognitionEvidence(
      id: 'e0001',
      kind: 'k',
      role: EvidenceRole.relation,
      label: 'Dependencia ñ',
      path: 'añ/m',
      value: 'v',
      fingerprint: 'f',
    ),
  ],
  relations: [
    RecognitionRelation(
      id: 'r0001',
      kind: RelationKind.workspaceMember,
      fromPath: '.',
      declaredName: null,
      targetPath: 'añ',
      targetUnitId: 'u0001',
      status: RelationStatus.corroborated,
      evidenceIds: const ['e0001'],
    ),
  ],
  contextSources: [
    ContextSource(
      scopePath: '.',
      path: 'docs',
      kind: ContextSourceKind.documentation,
      entityType: ContextEntityType.directory,
      reason: ContextReason.observed,
    ),
  ],
  omissions: [
    RecognitionOmission(
      path: 'añ/assets',
      rule: OmissionRule.declaredResource,
      evidenceIds: const ['e0001'],
    ),
  ],
);

/// Cada texto que el reporte retiene, con los enums serializados y el alcance.
final _textBytes = [
  'e0001', 'k', 'relation', 'Dependencia ñ', 'añ/m', 'v', 'f', // evidencia
  'c', 'C', 'plugin-c', 'e0001', // candidato y su referencia
  'u0001', 'u0001', 'package', 'añ', 'e0001', // unidad y su referencia
  'r0001', 'workspace_member', '.', 'añ', 'u0001', 'corroborated', 'e0001',
  '.', 'docs', 'documentation', 'directory', 'observed', 'not_inspected',
  'añ/assets', 'declared_resource', 'e0001', // omisión y su referencia
  recordProjectIdentity.code, recordProjectIdentity.description,
  enableStackPlugin.code, enableStackPlugin.description,
  'plugin-c', // pluginIds de la propuesta
  'declared_project_recognition', // alcance del reporte
].fold(0, (sum, text) => sum + utf8.encode(text).length);

Matcher exceeds(ReportLimitDimension dimension) => throwsA(
  isA<ReportLimitExceeded>().having((e) => e.dimension, 'dimension', dimension),
);

RecognitionReport _assemble(ReportLimits limits) => assembleRecognition(
  requestedRoot: '/r',
  resolvedRoot: '/r',
  repository: absentRepository,
  contributions: [_contribution],
  limits: limits,
);

void main() {
  group('the recount charges every new row and reference', () {
    test('12 items fit and 11 do not', () {
      expect(
        _assemble(const ReportLimits(maxDerivedItems: 12)).status,
        RecognitionStatus.recognized,
      );
      expect(
        () => _assemble(const ReportLimits(maxDerivedItems: 11)),
        exceeds(ReportLimitDimension.items),
      );
    });

    test('its exact UTF-8 text fits and one byte less does not', () {
      _assemble(ReportLimits(maxDerivedTextBytes: _textBytes));
      expect(
        () => _assemble(ReportLimits(maxDerivedTextBytes: _textBytes - 1)),
        exceeds(ReportLimitDimension.textBytes),
      );
    });
  });

  test('many small context sources exhaust items before being retained', () {
    final sources = [
      for (var i = 0; i < 20; i++)
        ContextSource(
          scopePath: '.',
          path: 'f$i',
          kind: ContextSourceKind.documentation,
          entityType: ContextEntityType.missing,
          reason: ContextReason.notFound,
        ),
    ];
    final crowded = contribution(contextSources: sources);
    expect(
      () => assembleRecognition(
        requestedRoot: '/r',
        resolvedRoot: '/r',
        repository: absentRepository,
        contributions: [crowded],
        limits: const ReportLimits(maxDerivedItems: 19),
      ),
      exceeds(ReportLimitDimension.items),
    );
  });
}
