import 'dart:convert';

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'assessment_support.dart';

void main() {
  final box = AssessSandbox()..register();
  String id(String prefix, List<Object?> tuple) =>
      '$prefix${sha256.convert(utf8.encode(canonicalAssessmentJson(tuple)))}';

  test('a candidate source key derives from scope, path and kind', () async {
    box.package('.', 'app');
    box.place('README.md', '# app\n');
    final basis = projectDartAssessmentContext(
      await box.context(sources: const [readmeRule]),
    );
    final link = basis.contextLinks.single;
    expect(link.kind, AssessmentLinkKind.candidateSource);
    expect(
      link.sourceId,
      id('s_', ['candidate_source', '.', 'README.md', 'documentation']),
    );
    expect(
      (link.sourcePath, link.label, link.targetUnitId),
      ('README.md', 'documentation', null),
    );
  });

  test(
    'a missing candidate source is not promoted to an observed one',
    () async {
      box.package('.', 'app');
      final basis = projectDartAssessmentContext(
        await box.context(sources: const [readmeRule]),
      );
      expect(basis.contextLinks, isEmpty);
    },
  );

  test('a local dependency keeps its V2 id and its target unit', () async {
    box.package(
      '.',
      'app',
      extra: '''
dependencies:
  widgets:
    path: packages/widgets
''',
    );
    box.package('packages/widgets', 'widgets');
    final context = await box.context();
    final relation = context.recognition.relations.single;
    final basis = projectDartAssessmentContext(context);
    final link = basis.contextLinks.single;
    expect(link.kind, AssessmentLinkKind.declaredDependency);
    expect(link.sourceId, relation.id);
    expect(link.label, 'widgets');
    // La ruta de su primera evidencia por ID, como fija el spec.
    final first = ([...relation.evidenceIds]..sort()).first;
    expect(
      link.sourcePath,
      context.recognition.evidence.singleWhere((e) => e.id == first).path,
    );
    expect(link.targetUnitId, id('u_', ['unit', 'packages/widgets']));
  });

  test('a workspace member is not renamed as a dependency', () async {
    box.package(
      '.',
      'app',
      extra: '''
workspace:
  - packages/widgets
''',
    );
    box.package(
      'packages/widgets',
      'widgets',
      extra: 'resolution: workspace\n',
    );
    final context = await box.context();
    expect(
      context.recognition.relations.map((r) => r.kind),
      contains(RelationKind.workspaceMember),
    );
    final basis = projectDartAssessmentContext(context);
    expect(
      basis.contextLinks.where(
        (l) => l.kind == AssessmentLinkKind.declaredDependency,
      ),
      isEmpty,
    );
  });

  test(
    'units and required recognition sources come from the context',
    () async {
      box.package('.', 'app');
      final context = await box.context();
      final basis = projectDartAssessmentContext(context);
      expect(basis.units.single.id, id('u_', ['unit', '.']));
      expect(basis.units.single.label, 'app');
      final manifest = basis.recognitionInputs.singleWhere(
        (i) => i.path == 'pubspec.yaml',
      );
      final evidence = context.recognition.evidence.firstWhere(
        (e) => e.path == 'pubspec.yaml',
      );
      expect('sha256:${manifest.sha256}', evidence.fingerprint);
    },
  );
}

const readmeRule = ContextSourceRule(
  relativePath: 'README.md',
  kind: ContextSourceKind.documentation,
  expectsDirectory: false,
);
