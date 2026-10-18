import 'dart:io';
import 'dart:isolate';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

Future<Directory> fixture() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:plugin_dart/plugin_dart.dart'),
  );
  final package = File.fromUri(barrel!).parent.parent;
  return Directory('${package.path}/test/fixtures/smooth_app_shape').absolute;
}

void main() {
  test('la forma del piloto es Flutter, ambigua por su toolchain', () async {
    final root = Directory((await fixture()).resolveSymbolicLinksSync());
    final report = assembleRecognition(
      requestedRoot: root.path,
      resolvedRoot: root.path,
      repository: const RepositoryContext(
        status: RepositoryStatus.absent,
        root: null,
        relation: RepositoryRelation.none,
      ),
      contributions: [await recognizeDartProject(root)],
    );
    expect(report.status, RecognitionStatus.ambiguous);
    expect(report.candidates.map((c) => c.id), ['flutter']);
    expect(report.units.map((u) => '${u.name} ${u.path}'), [
      'smooth_app packages/smooth_app',
    ]);
    expect(
      [for (final c in report.conflicts) c.code],
      ['toolchain_outside_constraint', 'toolchain_versions_disagree'],
    );
    expect(report.limitations, isEmpty);
    expect(report.proposal.eligible, isFalse);
    expect(
      [
        for (final e in report.evidence)
          '${e.id} ${e.path} ${e.kind} ${e.value}',
      ],
      [
        'e0001 .fvmrc toolchain.fvm 3.38.7',
        'e0002 flutter-version.txt toolchain.flutter_version_file 3.44.8',
        'e0003 packages/smooth_app/pubspec.yaml manifest.flutter_constraint ^3.44.8',
        'e0004 packages/smooth_app/pubspec.yaml manifest.flutter_dependency sdk: flutter',
        'e0005 packages/smooth_app/pubspec.yaml manifest.package_name smooth_app',
        'e0006 packages/smooth_app/pubspec.yaml manifest.sdk_constraint ^3.12.2',
      ],
    );
    expect(report.conflicts.first.evidenceIds, ['e0001', 'e0003']);
    expect(report.conflicts.last.evidenceIds, ['e0001', 'e0002']);
  });

  test('la fixture sólo contiene los tres hechos fijados', () async {
    final root = await fixture();
    final files = [
      for (final entity in root.listSync(recursive: true))
        if (entity is File) entity.path.substring(root.path.length + 1),
    ]..sort();
    expect(files, [
      '.fvmrc',
      'flutter-version.txt',
      'packages/smooth_app/pubspec.yaml',
    ]);
  });
}
