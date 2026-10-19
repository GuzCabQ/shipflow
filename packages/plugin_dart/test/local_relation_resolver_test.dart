import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/src/dart_project_recognizer.dart';
import 'package:plugin_dart/src/project_scanner.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

const _repository = RepositoryContext(
  status: RepositoryStatus.absent,
  root: null,
  relation: RepositoryRelation.none,
);

/// Cada relación como `origen>destino:estado`, con `?` sin destino.
List<String> relationsOf(RecognitionReport report) => [
  for (final r in report.relations)
    '${r.fromPath}>${r.targetPath ?? '?'}:${r.status.toWireName()}',
];

Set<String> blockingOf(RecognitionReport report) => {
  for (final l in report.limitations)
    if (l.blocking) l.code,
};

void main() {
  group('diagnostics fit the human view', diagnosticsFitTheView);
  final sandbox = ScanSandbox()..register();

  Future<RecognitionReport> recognize({DirectoryLister? list}) async =>
      assembleRecognition(
        requestedRoot: sandbox.root.path,
        resolvedRoot: sandbox.root.path,
        repository: _repository,
        contributions: [
          await recognizeListing(
            sandbox.root,
            list: list ?? listWithoutFollowing,
          ),
        ],
      );

  /// Una raíz `app` con [declarations] bajo su manifiesto y el paquete `b`.
  void project(String declarations) {
    sandbox.place('pubspec.yaml', 'name: app\n$declarations');
    sandbox.place('packages/b/pubspec.yaml', 'name: b\n');
  }

  test('a valid dependency and workspace member are corroborated', () async {
    project(
      'workspace:\n  - packages/b\ndependencies:\n  b: {path: packages/b}\n',
    );
    final report = await recognize();
    expect(relationsOf(report), [
      '.>packages/b:corroborated',
      '.>packages/b:corroborated',
    ]);
    expect(report.relations.map((r) => r.kind.toWireName()), [
      'local_dependency',
      'workspace_member',
    ]);
    expect(report.relations.map((r) => r.id), ['r0001', 'r0002']);
    expect(report.relations.first.declaredName, 'b');
    expect(report.relations.last.declaredName, isNull);
    expect(report.relations.first.targetUnitId, 'u0002');
    expect(report.relations.first.evidenceIds, hasLength(2));
    expect(report.proposal.eligible, isTrue);
  });

  group('every other case is unresolved, located and keeps the facts', () {
    for (final (name, declaration, setup, code) in [
      (
        'destination without manifest',
        'dependencies:\n  c: {path: packages/c}\n',
        () => sandbox.directory('packages/c'),
        'required_manifest_missing',
      ),
      (
        'missing destination',
        'dependencies:\n  c: {path: vendor/c}\n',
        () {},
        'required_manifest_missing',
      ),
      (
        'destination manifest without name',
        'dependencies:\n  c: {path: packages/c}\n',
        () => sandbox.place('packages/c/pubspec.yaml', 'version: 1.0.0\n'),
        'required_manifest_missing',
      ),
      (
        'outside the root',
        'dependencies:\n  c: {path: ../c}\n',
        () {},
        'path_dependency_outside_root',
      ),
      (
        'leaving the root and coming back',
        'dependencies:\n  b: {path: ../%ROOT%/packages/b}\n',
        () {},
        'path_dependency_outside_root',
      ),
      (
        'through an internal link',
        'dependencies:\n  b: {path: vendor/b}\n',
        () => Link('${sandbox.root.path}/vendor').createSync('packages'),
        'unsupported_local_reference',
      ),
      (
        'a workspace glob',
        'workspace:\n  - packages/*\n',
        () {},
        'unsupported_local_reference',
      ),
      (
        'a workspace member that climbs',
        'workspace:\n  - ../b\n',
        () {},
        'unsupported_local_reference',
      ),
      (
        'a URI',
        'dependencies:\n  b: {path: "file:///b"}\n',
        () {},
        'unsupported_local_reference',
      ),
      (
        'an empty path',
        'dependencies:\n  b: {path: ""}\n',
        () {},
        'unsupported_local_reference',
      ),
      (
        'inside the baseline exclusion build',
        'dependencies:\n  c: {path: build/c}\n',
        () => sandbox.place('build/c/pubspec.yaml', 'name: c\n'),
        'required_path_excluded',
      ),
    ]) {
      test(name, () async {
        final root = sandbox.root.path.split('/').last;
        project(declaration.replaceAll('%ROOT%', root));
        setup();
        final report = await recognize();
        expect(report.relations.single.status, RelationStatus.unresolved);
        expect(report.relations.single.targetUnitId, isNull);
        expect(blockingOf(report), contains(code));
        final diagnostic = report.limitations.firstWhere((l) => l.code == code);
        expect(diagnostic.path, 'pubspec.yaml');
        expect(report.proposal.eligible, isFalse);
        expect(report.units.map((u) => u.name), containsAll(['app', 'b']));
      });
    }
  });

  test('a name mismatch is a conflict with both sources', () async {
    project('dependencies:\n  x: {path: packages/b}\n');
    final report = await recognize();
    final conflict = report.conflicts.single;
    expect(conflict.code, 'local_dependency_name_mismatch');
    expect(conflict.evidenceIds, hasLength(2));
    final relation = report.relations.single;
    expect(relation.status, RelationStatus.unresolved);
    expect(relation.targetPath, 'packages/b');
    expect(relation.evidenceIds, conflict.evidenceIds);
    expect(report.proposal.eligible, isFalse);
  });

  test('diagnostics name the declaration, its effect and what to do', () async {
    project('dependencies:\n  c: {path: build/c}\n');
    sandbox.place('build/c/pubspec.yaml', 'name: c\n');
    final message = (await recognize()).limitations
        .firstWhere((l) => l.code == 'required_path_excluded')
        .message;
    expect(message, contains('«dependencies.c: build/c»'));
    expect(message, contains('«build»'));
    expect(message, contains('sin corroborar'));
    expect(message, contains('por separado'));
  });

  test('two sections towards the same target keep their provenance', () async {
    project(
      'dependencies:\n  b: {path: packages/b}\n'
      'dev_dependencies:\n  b: {path: packages/b}\n',
    );
    final report = await recognize();
    expect(report.relations, hasLength(2));
    final first = report.relations.first.evidenceIds.toSet();
    final second = report.relations.last.evidenceIds.toSet();
    expect(first.intersection(second), hasLength(1)); // el nombre destino
    expect(first.union(second), hasLength(3));
  });

  test('the listing order does not change the report', () async {
    project(
      'workspace:\n  - packages/b\ndependencies:\n  b: {path: packages/b}\n',
    );
    sandbox.place(
      'packages/a/pubspec.yaml',
      'name: a\ndependencies:\n  b: {path: ../b}\n',
    );
    final forward = await recognize();
    final backward = await recognize(
      list: (Directory directory) async* {
        final entries = await directory.list(followLinks: false).toList();
        yield* Stream.fromIterable(entries.reversed);
      },
    );
    expect(jsonEncode(backward), jsonEncode(forward));
    expect(relationsOf(forward), [
      '.>packages/b:corroborated',
      '.>packages/b:corroborated',
      'packages/a>packages/b:corroborated',
    ]);
  });

  test('a nameless declaring manifest leaves no dangling reference', () async {
    sandbox.place('pubspec.yaml', 'dependencies:\n  b: {path: packages/b}\n');
    sandbox.place('packages/b/pubspec.yaml', 'name: b\n');
    final report = await recognize();
    expect(relationsOf(report), ['.>packages/b:corroborated']);
    expect(report.status, RecognitionStatus.recognized);
  });
}

/// Con una declaración corta, cada diagnóstico cabe entero en una línea de
/// la vista humana (240 runes), alternativa incluida.
void diagnosticsFitTheView() {
  final sandbox = ScanSandbox()..register();

  for (final (declared, setup) in [
    ('build/m', () => sandbox.place('build/m/pubspec.yaml', 'name: m\n')),
    ('../m', () {}),
    ('falta/../m', () {}),
    ('vendor/m', () => Link('${sandbox.root.path}/vendor').createSync('.')),
    ('nada/m', () {}),
    ('"m*"', () {}),
  ]) {
    test('«$declared» fits whole', () async {
      sandbox.place(
        'pubspec.yaml',
        'name: app\ndependencies:\n  modulo: {path: $declared}\n',
      );
      setup();
      final contribution = await recognizeListing(sandbox.root);
      final message = contribution.limitations
          .firstWhere((l) => l.path == 'pubspec.yaml')
          .message;
      expect(message.runes.length, lessThanOrEqualTo(240), reason: message);
      expect(message, endsWith('.'));
    });
  }
}
