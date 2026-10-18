import 'dart:io';

import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_dart/src/project_scanner.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

void main() {
  final sandbox = ScanSandbox()..register();

  Future<ScanResult> scan({DirectoryLister? list}) => scanProject(
    sandbox.root,
    limits: const ScanLimits(),
    list: list ?? listWithoutFollowing,
  );

  test('descubre los manifiestos en orden de ruta', () async {
    sandbox.place('packages/b/pubspec.yaml');
    sandbox.place('packages/a/pubspec.yaml');
    sandbox.place('pubspec.yaml');
    final result = await scan();
    expect(sourcePaths(result), [
      'packages/a/pubspec.yaml',
      'packages/b/pubspec.yaml',
      'pubspec.yaml',
    ]);
    expect(result.sources.first.kind, SourceKind.manifest);
    expect(result.limitations, isEmpty);
  });

  test('las seis exclusiones exactas no se recorren', () async {
    for (final excluded in [
      '.git',
      '.dart_tool',
      'build',
      '.symlinks',
      'Pods',
      'node_modules',
    ]) {
      sandbox.place('app/$excluded/copia/pubspec.yaml');
    }
    sandbox.place('app/pubspec.yaml');
    sandbox.place('app/builder/pubspec.yaml');
    final result = await scan();
    expect(sourcePaths(result), [
      'app/builder/pubspec.yaml',
      'app/pubspec.yaml',
    ]);
  });

  test('los nombres ocultos no se excluyen en bloque', () async {
    sandbox.place('.fvmrc', '{"flutter": "3.0.0"}');
    sandbox.place('.oculto/pubspec.yaml');
    final result = await scan();
    expect(sourcePaths(result), ['.fvmrc', '.oculto/pubspec.yaml']);
    expect(result.sources.first.kind, SourceKind.fvmConfig);
  });

  test('los marcadores de toolchain sólo cuentan en la raíz', () async {
    sandbox.place('flutter-version.txt', '3.0.0\n');
    sandbox.place('packages/a/.fvmrc', '{"flutter": "9.9.9"}');
    sandbox.place('packages/a/flutter-version.txt', '9.9.9\n');
    final result = await scan();
    expect(sourcePaths(result), ['flutter-version.txt']);
    expect(result.sources.single.kind, SourceKind.flutterVersionFile);
  });

  test('un enlace simbólico no se sigue y bloquea', () async {
    final outside = await Directory.systemTemp.createTemp('shipflow-fuera-');
    addTearDown(() => outside.delete(recursive: true));
    File('${outside.path}/pubspec.yaml').writeAsStringSync('name: ajeno\n');
    Link('${sandbox.root.path}/enlace').createSync(outside.path);
    final result = await scan();
    expect(sourcePaths(result), isEmpty);
    expect(limitationsOf(result), ['symlink_not_followed:enlace:true']);
  });

  test('un enlace dentro de una exclusión no se mira', () async {
    sandbox.directory('ios/.symlinks');
    Link(
      '${sandbox.root.path}/ios/.symlinks/plugin',
    ).createSync(sandbox.root.path);
    expect((await scan()).limitations, isEmpty);
  });

  test('un subárbol ilegible bloquea y no apaga a sus hermanos', () async {
    sandbox.place('a/pubspec.yaml');
    sandbox.place('cerrado/pubspec.yaml');
    sandbox.place('z/pubspec.yaml');
    final result = await scan(
      list: (directory) {
        if (directory.path.endsWith('/cerrado')) {
          throw const FileSystemException('denegado', '/ruta/interna');
        }
        return listWithoutFollowing(directory);
      },
    );
    expect(sourcePaths(result), ['a/pubspec.yaml', 'z/pubspec.yaml']);
    expect(limitationsOf(result), ['subtree_unreadable:cerrado:true']);
    expect(result.limitations.single.message, isNot(contains('/ruta')));
  });

  test('el orden en que el sistema enumera no cambia el resultado', () async {
    for (final name in ['c', 'a', 'b']) {
      sandbox.place('$name/pubspec.yaml', 'name: $name\n');
    }
    final forward = await scan();
    final reversed = await scan(
      list: (directory) => listWithoutFollowing(directory).reversed.toList(),
    );
    expect(sourcePaths(reversed), sourcePaths(forward));
    expect(
      [for (final s in reversed.sources) s.read.fingerprint],
      [for (final s in forward.sources) s.read.fingerprint],
    );
  });

  test(
    'una fuente que no es un archivo regular bloquea sin abrirse',
    () async {
      sandbox.directory('f');
      for (final name in ['f/pubspec.yaml', '.fvmrc']) {
        final made = await Process.run('mkfifo', [
          '${sandbox.root.path}/$name',
        ]);
        expect(made.exitCode, 0, reason: '${made.stderr}');
      }
      final result = await scan();
      expect(sourcePaths(result), isEmpty);
      expect(limitationsOf(result), [
        'source_unreadable:.fvmrc:true',
        'source_unreadable:f/pubspec.yaml:true',
      ]);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('un manifiesto que cambia entre lecturas bloquea', () async {
    sandbox.place('pubspec.yaml');
    var call = 0;
    final result = await scanProject(
      sandbox.root,
      readBytes: (_, _) async => [call++],
    );
    expect(sourcePaths(result), isEmpty);
    expect(limitationsOf(result), [
      'source_changed_during_scan:pubspec.yaml:true',
    ]);
  });
}
