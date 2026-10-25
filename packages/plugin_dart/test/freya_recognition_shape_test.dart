import 'dart:io';
import 'dart:isolate';

import 'package:core/core.dart';
import 'package:plugin_dart/src/dart_project_recognizer.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

/// La forma sintética de Freya, copiada a una raíz nueva con sus enlaces:
/// los dos assets compartidos del catálogo y los paquetes de la carpeta
/// temporal de iOS, uno fuera de la raíz y otro hacia `build`.
Future<void> recreate(Directory root, Directory outside) async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:plugin_dart/plugin_dart.dart'),
  );
  final fixture =
      '${File.fromUri(barrel!).parent.parent.path}'
      '/test/fixtures/freya_recognition_shape';
  await Process.run('cp', ['-R', '$fixture/.', root.path]);
  // Los manifiestos se guardan con otro nombre para que las herramientas
  // del editor no los tomen por paquetes reales.
  for (final unit in ['', 'componentes_freya/']) {
    File(
      '${root.path}/${unit}pubspec.yaml.fixture',
    ).renameSync('${root.path}/${unit}pubspec.yaml');
  }
  for (final share in ['fonts', 'images']) {
    Link(
      '${root.path}/componentes_freya/assets/$share',
    ).createSync('../../assets/$share');
  }
  final packages = '${root.path}/ios/Flutter/ephemeral/Packages/.packages';
  Directory(packages).createSync(recursive: true);
  Directory(
    '${root.path}/build/ios/SourcePackages/built',
  ).createSync(recursive: true);
  Link('$packages/external').createSync(outside.path);
  Link(
    '$packages/built',
  ).createSync('../../../../../build/ios/SourcePackages/built');
}

/// Cada ruta con su tipo y tamaño, sin seguir enlaces.
List<String> snapshot(Directory root) => [
  for (final e in root.listSync(recursive: true, followLinks: false))
    '${e.path}:${FileSystemEntity.typeSync(e.path, followLinks: false)}:'
        '${e is File ? e.lengthSync() : 0}',
]..sort();

void main() {
  final sandbox = ScanSandbox()..register();
  late Directory outside;
  late ListingSpy spy;
  late RecognitionReport report;
  late List<String> before;

  setUp(() async {
    outside = await Directory.systemTemp.createTemp('shipflow-fuera-');
    await recreate(sandbox.root, outside);
    before = snapshot(sandbox.root);
    spy = ListingSpy(sandbox.root);
    report = assembleRecognition(
      requestedRoot: sandbox.root.path,
      resolvedRoot: sandbox.root.path,
      repository: const RepositoryContext(
        status: RepositoryStatus.absent,
        root: null,
        relation: RepositoryRelation.none,
      ),
      contributions: [
        await recognizeListing(
          sandbox.root,
          list: spy.call,
          contextSources: candidateCatalogue,
        ),
      ],
    );
  });
  tearDown(() => outside.delete(recursive: true));

  test('RU-01: two units and a corroborated catalogue dependency', () {
    expect(report.units.map((u) => '${u.name} ${u.path}'), [
      'freya .',
      'componentes_freya componentes_freya',
    ]);
    final relation = report.relations.single;
    expect(relation.fromPath, 'componentes_freya');
    expect(relation.targetPath, '.');
    expect(relation.declaredName, 'freya');
    expect(relation.status, RelationStatus.corroborated);
  });

  test('RU-01: description and environment are attributed to sources', () {
    String of(EvidenceRole role) => [
      for (final e in report.evidence)
        if (e.role == role) '${e.path}=${e.value}',
    ].join(' | ');
    expect(
      of(EvidenceRole.description),
      'componentes_freya/pubspec.yaml=Storybook for Freya App | '
      'pubspec.yaml=A new Flutter project.',
    );
    expect(of(EvidenceRole.environment), contains('.fvmrc=3.44.0'));
    expect(of(EvidenceRole.environment), contains('pubspec.yaml=^3.12.0'));
  });

  test('RU-01: ephemeral and the shared assets are omitted, not walked', () {
    expect(report.omissions.map((o) => '${o.path}:${o.rule.toWireName()}'), [
      'assets/images:declared_resource',
      'build:baseline_exclusion',
      'componentes_freya/assets/fonts:declared_resource',
      'componentes_freya/assets/images:declared_resource',
      'ios/Flutter/ephemeral:temporary_directory',
    ]);
    for (final hidden in [
      'ios/Flutter/ephemeral',
      'componentes_freya/assets/fonts',
      'componentes_freya/assets/images',
      'assets/images',
    ]) {
      expect(spy.listed, isNot(contains(hidden)), reason: hidden);
    }
  });

  test('RU-01: nothing else blocks, so the proposal is eligible', () {
    expect(report.limitations, isEmpty);
    expect(report.conflicts, isEmpty);
    expect(report.status, RecognitionStatus.recognized);
    expect(report.proposal.eligible, isTrue);
  });

  test('RU-09: the tree is the same after recognizing it', () {
    expect(snapshot(sandbox.root), before);
  });
}
