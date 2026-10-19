import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assembler_support.dart';

/// Una contribución reconocible de dos unidades con una relación entre
/// ellas; cada caso cambia sólo lo que prueba.
RecognitionContribution _scoped({
  List<RecognitionRelation>? relations,
  List<ContextSource> contextSources = const [],
  List<RecognitionOmission> omissions = const [],
  List<RecognitionLimitation> limitations = const [],
}) => contribution(
  candidates: [
    candidate('stack', ['e0001']),
  ],
  units: [
    unit('u0001', 'app', ['e0001']),
    unit('u0002', 'lib', ['e0002']),
  ],
  evidence: [
    evidence('e0001'),
    evidence('e0002', path: 'lib/manifest'),
  ],
  limitations: limitations,
  relations: relations ?? [_relation('r0001')],
  contextSources: contextSources,
  omissions: omissions,
);

RecognitionRelation _relation(
  String id, {
  String fromPath = 'app',
  String? targetPath = 'lib',
  String? targetUnitId = 'u0002',
  RelationStatus status = RelationStatus.corroborated,
  List<String> evidenceIds = const ['e0001', 'e0002'],
}) => RecognitionRelation(
  id: id,
  kind: RelationKind.localDependency,
  fromPath: fromPath,
  declaredName: 'lib',
  targetPath: targetPath,
  targetUnitId: targetUnitId,
  status: status,
  evidenceIds: evidenceIds,
);

RecognitionRelation _unresolved(List<String> evidenceIds) => _relation(
  'r0001',
  targetPath: null,
  targetUnitId: null,
  status: RelationStatus.unresolved,
  evidenceIds: evidenceIds,
);

ContextSource _source(String scope, String path) => ContextSource(
  scopePath: scope,
  path: path,
  kind: ContextSourceKind.documentation,
  entityType: ContextEntityType.missing,
  reason: ContextReason.notFound,
);

RecognitionOmission _omission(String path, OmissionRule rule, String? id) =>
    RecognitionOmission(path: path, rule: rule, evidenceIds: [?id]);

/// Las mismas filas en un orden o en el inverso.
RecognitionContribution _shuffled(bool reversed) {
  List<T> order<T>(List<T> items) => reversed ? items.reversed.toList() : items;
  return _scoped(
    relations: order([
      _relation(
        'r0002',
        fromPath: 'lib',
        targetPath: 'app',
        targetUnitId: 'u0001',
      ),
      _relation('r0001', evidenceIds: ['e0002', 'e0001']),
    ]),
    contextSources: order([
      _source('lib', 'lib/README.md'),
      _source('.', 'docs'),
      _source('.', 'README.md'),
    ]),
    omissions: order([
      _omission('lib/assets', OmissionRule.declaredResource, 'e0002'),
      _omission('.git', OmissionRule.baselineExclusion, null),
    ]),
  );
}

void main() {
  group('the assembler rejects defects in the new lists', () {
    for (final (name, broken) in [
      (
        'relación con evidencia inexistente',
        _scoped(
          relations: [
            _relation('r0001', evidenceIds: ['e0009']),
          ],
        ),
      ),
      (
        'relación hacia una unidad inexistente',
        _scoped(relations: [_relation('r0001', targetUnitId: 'u0009')]),
      ),
      (
        'IDs de relación repetidos',
        _scoped(
          relations: [
            _relation('r0001'),
            _relation('r0001', fromPath: 'z'),
          ],
        ),
      ),
      (
        'omisión con evidencia inexistente',
        _scoped(
          omissions: [
            _omission('app/assets', OmissionRule.declaredResource, 'e0009'),
          ],
        ),
      ),
      (
        'omisión repetida',
        _scoped(
          omissions: [
            for (var i = 0; i < 2; i++)
              _omission('.git', OmissionRule.baselineExclusion, null),
          ],
        ),
      ),
      (
        'fuente candidata repetida',
        _scoped(
          contextSources: [
            _source('.', 'README.md'),
            _source('.', 'README.md'),
          ],
        ),
      ),
      (
        'relación sin resolver sin diagnóstico',
        _scoped(
          relations: [
            _unresolved(['e0001']),
          ],
        ),
      ),
    ]) {
      test(name, () {
        expect(() => assemble([broken]), throwsArgumentError);
      });
    }
  });

  group('an unresolved relation needs a locatable diagnostic', () {
    test('a blocking limitation at its declaring source', () {
      final report = assemble([
        _scoped(
          relations: [
            _unresolved(['e0001']),
          ],
          limitations: const [
            RecognitionLimitation(
              code: 'required_path_excluded',
              message: 'm',
              path: 'a/manifest',
              blocking: true,
            ),
          ],
        ),
      ]);
      expect(report.relations.single.status, RelationStatus.unresolved);
      expect(report.status, RecognitionStatus.ambiguous);
    });

    test('a non-blocking limitation there is not enough', () {
      final quiet = _scoped(
        relations: [
          _unresolved(['e0001']),
        ],
        limitations: const [
          RecognitionLimitation(
            code: 'x',
            message: 'm',
            path: 'a/manifest',
            blocking: false,
          ),
        ],
      );
      expect(() => assemble([quiet]), throwsArgumentError);
    });
  });

  test('omissions and context are not blockers by themselves', () {
    final report = assemble([
      _scoped(
        contextSources: [_source('.', 'README.md')],
        omissions: [_omission('.git', OmissionRule.baselineExclusion, null)],
      ),
    ]);
    expect(report.status, RecognitionStatus.recognized);
    expect(report.proposal.eligible, isTrue);
    expect(report.omissions.single.path, '.git');
    expect(report.contextSources.single.path, 'README.md');
  });

  test('the new lists are ordered deterministically', () {
    final forward = assemble([_shuffled(false)]);
    expect(jsonEncode(forward), jsonEncode(assemble([_shuffled(true)])));
    expect(forward.relations.map((r) => r.fromPath), ['app', 'lib']);
    expect(forward.relations.first.evidenceIds, ['e0001', 'e0002']);
    expect(forward.contextSources.map((s) => s.path), [
      'README.md',
      'docs',
      'lib/README.md',
    ]);
    expect(forward.omissions.map((o) => o.path), ['.git', 'lib/assets']);
  });
}
