import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

RecognitionReport assemble(Directory root, RecognitionContribution c) =>
    assembleRecognition(
      requestedRoot: root.path,
      resolvedRoot: root.path,
      repository: const RepositoryContext(
        status: RepositoryStatus.absent,
        root: null,
        relation: RepositoryRelation.none,
      ),
      contributions: [c],
    );

List<String> codesOf(Iterable<Object> findings) => [
  for (final f in findings)
    switch (f) {
      RecognitionConflict(:final code) => code,
      RecognitionLimitation(:final code) => code,
      _ => '$f',
    },
];

void main() {
  final sandbox = ScanSandbox()..register();

  Future<RecognitionReport> recognize() async =>
      assemble(sandbox.root, await recognizeDartProject(sandbox.root));

  test('una raíz vacía no es soportada', () async {
    final report = await recognize();
    expect(report.status, RecognitionStatus.unsupported);
    expect(report.candidates, isEmpty);
  });

  test('un paquete puro se reconoce como Dart', () async {
    sandbox.place('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.5.0\n');
    final report = await recognize();
    expect(report.status, RecognitionStatus.recognized);
    final candidate = report.candidates.single;
    expect(
      [candidate.id, candidate.displayName, candidate.pluginId],
      ['dart', 'Dart', 'plugin_dart'],
    );
    final unit = report.units.single;
    expect([unit.name, unit.kind, unit.path], ['app', 'dart_package', '.']);
    expect(report.proposal.pluginIds, ['plugin_dart']);
  });

  test('una dependencia flutter reconoce Flutter', () async {
    sandbox.place(
      'pubspec.yaml',
      'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    final report = await recognize();
    expect(report.status, RecognitionStatus.recognized);
    expect(report.candidates.single.id, 'flutter');
    expect(report.units.single.kind, 'flutter_package');
  });

  test('una restricción Flutter sola no elige Flutter', () async {
    sandbox.place(
      'pubspec.yaml',
      'name: app\nenvironment:\n  flutter: ^3.0.0\n',
    );
    final report = await recognize();
    expect(report.status, RecognitionStatus.recognized);
    expect(report.candidates.single.id, 'dart');
    expect(report.units.single.kind, 'dart_package');
    expect(
      report.evidence.map((e) => e.kind),
      contains('manifest.flutter_constraint'),
    );
  });

  test('paquetes Dart y Flutter conviven bajo un candidato Flutter', () async {
    sandbox.place('packages/app/pubspec.yaml', '''
name: app
dependencies:
  flutter:
    sdk: flutter
''');
    sandbox.place('packages/core_logic/pubspec.yaml', 'name: core_logic\n');
    final report = await recognize();
    expect(report.status, RecognitionStatus.recognized);
    expect(report.candidates.map((c) => c.id), ['flutter']);
    expect(report.units.map((u) => '${u.path}:${u.kind}'), [
      'packages/app:flutter_package',
      'packages/core_logic:dart_package',
    ]);
  });

  test('la raíz sin manifiesto reconoce los anidados', () async {
    sandbox.place('packages/a/pubspec.yaml', 'name: a\n');
    sandbox.place('packages/b/pubspec.yaml', 'name: b\n');
    final report = await recognize();
    expect(report.status, RecognitionStatus.recognized);
    expect(report.units.map((u) => u.path), ['packages/a', 'packages/b']);
  });

  test('los IDs de evidencia siguen el orden de ruta, tipo y valor', () async {
    sandbox.place('z/pubspec.yaml', 'name: z\nenvironment:\n  sdk: ^3.0.0\n');
    sandbox.place('a/pubspec.yaml', '''
name: a
environment:
  sdk: ^3.1.0
dependencies:
  z: {path: ../z}
''');
    final report = await recognize();
    expect(
      [
        for (final e in report.evidence)
          '${e.id} ${e.path} ${e.kind} ${e.value}',
      ],
      [
        'e0001 a/pubspec.yaml manifest.package_name a',
        'e0002 a/pubspec.yaml manifest.path_dependency dependencies.z: ../z',
        'e0003 a/pubspec.yaml manifest.sdk_constraint ^3.1.0',
        'e0004 z/pubspec.yaml manifest.package_name z',
        'e0005 z/pubspec.yaml manifest.sdk_constraint ^3.0.0',
      ],
    );
    expect(report.units.first.evidenceIds, ['e0001', 'e0002', 'e0003']);
    expect(report.evidence.first.fingerprint, startsWith('sha256:'));
    expect(report.status, RecognitionStatus.recognized);
  });

  test('nombres de paquete repetidos son un conflicto', () async {
    sandbox.place('a/pubspec.yaml', 'name: mismo\n');
    sandbox.place('b/pubspec.yaml', 'name: mismo\n');
    final report = await recognize();
    expect(report.status, RecognitionStatus.ambiguous);
    expect(codesOf(report.conflicts), ['duplicate_package_name']);
    expect(report.conflicts.single.evidenceIds, ['e0001', 'e0002']);
  });

  test('un manifiesto malformado entre válidos se informa', () async {
    sandbox.place('a/pubspec.yaml', 'name: a\n');
    sandbox.place('b/pubspec.yaml', 'name: [roto\n');
    final report = await recognize();
    expect(report.status, RecognitionStatus.ambiguous);
    expect(report.units.map((u) => u.name), ['a']);
    expect(codesOf(report.limitations), ['invalid_manifest']);
    expect(report.limitations.single.path, 'b/pubspec.yaml');
  });

  test('una restricción inválida es limitación, no compatibilidad', () async {
    sandbox.place('pubspec.yaml', 'name: a\nenvironment:\n  sdk: "^^3"\n');
    final report = await recognize();
    expect(report.status, RecognitionStatus.ambiguous);
    expect(codesOf(report.limitations), ['invalid_constraint']);
  });

  group('dependencias locales', () {
    test('dentro de la raíz no limitan', () async {
      sandbox.place(
        'a/pubspec.yaml',
        'name: a\ndependencies:\n  b: {path: ../b}\n',
      );
      sandbox.place('b/pubspec.yaml', 'name: b\n');
      expect((await recognize()).limitations, isEmpty);
    });

    test('fuera de la raíz no se atraviesan y bloquean', () async {
      sandbox.place(
        'pubspec.yaml',
        'name: a\ndependencies:\n  x: {path: ../x}\n',
      );
      final report = await recognize();
      expect(report.status, RecognitionStatus.ambiguous);
      expect(codesOf(report.limitations), ['path_dependency_outside_root']);
      expect(report.limitations.single.path, 'pubspec.yaml');
    });

    test('un enlace dentro de la raíz bloquea sin seguirlo', () async {
      final outside = await Directory.systemTemp.createTemp('shipflow-fuera-');
      addTearDown(() => outside.delete(recursive: true));
      Link('${sandbox.root.path}/vendor').createSync(outside.path);
      sandbox.place(
        'pubspec.yaml',
        'name: a\ndependencies:\n  x: {path: vendor}\n',
      );
      final report = await recognize();
      expect(codesOf(report.limitations), [
        'symlink_not_followed',
        'unsupported_local_reference',
      ]);
    });
  });

  test('un marcador anidado no gobierna el proyecto', () async {
    sandbox.place('pubspec.yaml', 'name: a\nenvironment:\n  flutter: ^3.0.0\n');
    sandbox.place('packages/x/.fvmrc', '{"flutter": "1.0.0"}');
    final report = await recognize();
    expect(report.status, RecognitionStatus.recognized);
    expect(
      report.evidence.map((e) => e.kind),
      isNot(contains('toolchain.fvm')),
    );
  });

  test('un manifiesto que excede su tamaño se informa', () async {
    sandbox.place('a/pubspec.yaml', 'name: a\n');
    sandbox.place('b/pubspec.yaml', 'name: ${'b' * 64}\n');
    final contribution = await recognizeDartProject(
      sandbox.root,
      limits: const ScanLimits(maxManifestBytes: 32),
    );
    final report = assemble(sandbox.root, contribution);
    expect(report.status, RecognitionStatus.ambiguous);
    expect(codesOf(report.limitations), ['source_too_large']);
  });

  test('un adelanto truncado se muestra pero no se interpreta', () async {
    sandbox.place(
      'pubspec.yaml',
      'name: a\nenvironment:\n  sdk: "${'^' * 5000}"\n'
          'dependencies:\n  x: {path: ${'../' * 1700}}\n',
    );
    final report = await recognize();
    expect(report.status, RecognitionStatus.ambiguous);
    expect(codesOf(report.limitations), [
      'observed_value_truncated',
      'observed_value_truncated',
    ]);
    final shown = {
      for (final e in report.evidence)
        if (e.value.endsWith('…')) e.kind: utf8.encode(e.value).length,
    };
    expect(shown.keys, {'manifest.path_dependency', 'manifest.sdk_constraint'});
    expect(shown.values, everyElement(lessThanOrEqualTo(4096)));
  });
}
