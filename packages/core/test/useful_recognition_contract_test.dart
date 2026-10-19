import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assembler_support.dart';
import 'recognition_fixtures.dart' as fixtures;

void main() {
  group('wire names fixed by the contract', () {
    test('evidence roles and relations', () {
      expect(EvidenceRole.values.map((r) => r.toWireName()), [
        'identity',
        'environment',
        'description',
        'relation',
        'resource',
      ]);
      expect(RelationKind.values.map((k) => k.toWireName()), [
        'local_dependency',
        'workspace_member',
      ]);
      expect(RelationStatus.values.map((s) => s.toWireName()), [
        'corroborated',
        'unresolved',
      ]);
      expect(OmissionRule.values.map((r) => r.toWireName()), [
        'baseline_exclusion',
        'temporary_directory',
        'declared_resource',
      ]);
    });

    test('context sources', () {
      expect(ContextSourceKind.values.map((k) => k.toWireName()), [
        'documentation',
        'instructions',
        'analysis_configuration',
        'task_configuration',
        'ci_configuration',
      ]);
      expect(ContextEntityType.values.map((t) => t.toWireName()), [
        'file',
        'directory',
        'link',
        'special',
        'missing',
        'unavailable',
      ]);
      expect(ContextReason.values.map((r) => r.toWireName()), [
        'observed',
        'not_found',
        'access_failed',
        'ancestor_link',
        'excluded',
      ]);
    });

    test('a value outside the contract is rejected when reading', () {
      expect(() => EvidenceRole.fromWireName('x'), throwsFormatException);
      expect(
        () => ContextReason.fromWireName('notFound'),
        throwsFormatException,
      );
      final json = fixtures.contextSource.toJson()
        ..['contentStatus'] = 'inspected';
      expect(() => ContextSource.fromJson(json), throwsFormatException);
      final report = fixtures.report.toJson()..['recognitionScope'] = 'global';
      expect(() => RecognitionReport.fromJson(report), throwsFormatException);
    });
  });

  group('serialized shape', () {
    test('field order of each new value', () {
      expect(fixtures.evidence.toJson().keys, [
        'id',
        'kind',
        'role',
        'label',
        'path',
        'value',
        'fingerprint',
      ]);
      expect(fixtures.relation.toJson().keys, [
        'id',
        'kind',
        'fromPath',
        'declaredName',
        'targetPath',
        'targetUnitId',
        'status',
        'evidenceIds',
      ]);
      expect(fixtures.omission.toJson().keys, ['path', 'rule', 'evidenceIds']);
    });

    test('a context source has no fingerprint and is never inspected', () {
      expect(fixtures.contextSource.toJson(), {
        'scopePath': 'packages/app',
        'path': 'packages/app/README.md',
        'kind': 'documentation',
        'entityType': 'file',
        'reason': 'observed',
        'contentStatus': 'not_inspected',
      });
    });

    test('the report states its scope; a contribution does not', () {
      expect(fixtures.report.recognitionScope, 'declared_project_recognition');
      expect(
        fixtures.report.toJson()['recognitionScope'],
        'declared_project_recognition',
      );
      expect(
        fixtures.contribution.toJson().containsKey('recognitionScope'),
        isFalse,
      );
    });

    test('nullable relation fields travel present as null', () {
      final open = RecognitionRelation(
        id: 'r0001',
        kind: RelationKind.workspaceMember,
        fromPath: '.',
        declaredName: null,
        targetPath: null,
        targetUnitId: null,
        status: RelationStatus.unresolved,
        evidenceIds: const ['e0001'],
      );
      final json = open.toJson();
      expect(json, containsPair('declaredName', null));
      expect(json, containsPair('targetPath', null));
      expect(json, containsPair('targetUnitId', null));
      expect(RecognitionRelation.fromJson(json).toJson(), json);
    });
  });

  group('invariants are enforced when building', () {
    RecognitionRelation corroborated({String? path, String? unit}) =>
        RecognitionRelation(
          id: 'r',
          kind: RelationKind.localDependency,
          fromPath: 'a',
          declaredName: 'b',
          targetPath: path,
          targetUnitId: unit,
          status: RelationStatus.corroborated,
          evidenceIds: const [],
        );

    test('a corroborated relation needs its target path and unit', () {
      expect(() => corroborated(unit: 'u'), throwsArgumentError);
      expect(() => corroborated(path: 'b'), throwsArgumentError);
      expect(corroborated(path: 'b', unit: 'u').targetUnitId, 'u');
    });

    test('a context source reason matches its entity type', () {
      for (final (type, reason) in [
        (ContextEntityType.missing, ContextReason.observed),
        (ContextEntityType.file, ContextReason.notFound),
        (ContextEntityType.unavailable, ContextReason.observed),
        (ContextEntityType.link, ContextReason.excluded),
        (ContextEntityType.missing, ContextReason.accessFailed),
      ]) {
        expect(
          () => ContextSource(
            scopePath: '.',
            path: 'README.md',
            kind: ContextSourceKind.documentation,
            entityType: type,
            reason: reason,
          ),
          throwsArgumentError,
          reason: '$type/$reason',
        );
      }
    });

    test('resource and temporary omissions cite evidence', () {
      for (final rule in [
        OmissionRule.declaredResource,
        OmissionRule.temporaryDirectory,
      ]) {
        expect(
          () =>
              RecognitionOmission(path: 'a', rule: rule, evidenceIds: const []),
          throwsArgumentError,
        );
      }
      final baseline = RecognitionOmission(
        path: '.git',
        rule: OmissionRule.baselineExclusion,
        evidenceIds: const [],
      );
      expect(baseline.evidenceIds, isEmpty);
    });
  });

  group('the new lists are immutable', () {
    test('built values copy their lists', () {
      final ids = ['e0001'];
      final relations = [fixtures.relation];
      final omission = RecognitionOmission(
        path: 'a',
        rule: OmissionRule.declaredResource,
        evidenceIds: ids,
      );
      final built = RecognitionContribution(
        candidates: const [],
        units: const [],
        evidence: const [],
        conflicts: const [],
        limitations: const [],
        relations: relations,
      );
      ids.clear();
      relations.clear();
      expect(omission.evidenceIds, ['e0001']);
      expect(built.relations, hasLength(1));
    });

    test('exposed lists cannot be modified', () {
      for (final list in <List<Object>>[
        fixtures.relation.evidenceIds,
        fixtures.omission.evidenceIds,
        fixtures.contribution.relations,
        fixtures.contribution.contextSources,
        fixtures.contribution.omissions,
        fixtures.report.relations,
        fixtures.report.contextSources,
        fixtures.report.omissions,
      ]) {
        expect(list.clear, throwsUnsupportedError);
      }
    });
  });

  group('fallback reports keep every new list empty', () {
    test('report limit reached', () {
      final fallback = reportLimitReached(
        requestedRoot: '/a',
        resolvedRoot: '/a',
        repository: absentRepository,
        dimension: ReportLimitDimension.items,
        extended: false,
      );
      expect(fallback.relations, isEmpty);
      expect(fallback.contextSources, isEmpty);
      expect(fallback.omissions, isEmpty);
      expect(fallback.proposal.eligible, isFalse);
      expect(fallback.recognitionScope, 'declared_project_recognition');
    });

    test('invalid root', () {
      final invalid = RecognitionReport.invalidRoot(
        requestedRoot: '/a',
        reason: fixtures.limitation,
      );
      expect(invalid.relations, isEmpty);
      expect(invalid.contextSources, isEmpty);
      expect(invalid.omissions, isEmpty);
      expect(invalid.proposal.eligible, isFalse);
    });
  });
}
