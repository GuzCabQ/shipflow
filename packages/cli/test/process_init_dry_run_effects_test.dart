@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'init_process_support.dart';

void main() {
  final process = InitProcessSandbox()..register();
  late Directory outside;

  setUp(() async {
    final created = await Directory.systemTemp.createTemp('shipflow-ajeno-');
    outside = Directory(created.resolveSymbolicLinksSync());
    File('${outside.path}/pubspec.yaml').writeAsStringSync('name: centinela\n');
    File('${outside.path}/centinela.txt').writeAsStringSync('no tocar\n');
  });

  tearDown(() => outside.delete(recursive: true));

  /// Un proyecto con todo lo que podría tentar a escribir o a salir.
  void hostileProject() {
    process.place('pubspec.yaml', '''
name: app
environment:
  sdk: ^3.0.0
dependencies:
  ajeno: {path: ${outside.path}}
''');
    process.place('packages/b/pubspec.yaml', 'name: b\n');
    process.place('build/copia/pubspec.yaml', 'name: app\n');
    process.place('.dart_tool/package_config.json', '{}');
    Link('${process.root.path}/enlace').createSync(outside.path);
  }

  for (final arguments in [
    ['init', '--dry-run'],
    ['init', '--dry-run', '--json'],
  ]) {
    test('$arguments no cambia el proyecto ni lo de afuera', () async {
      hostileProject();
      final before = treeSnapshot(process.root);
      final outsideBefore = treeSnapshot(outside);
      final result = await process.run(arguments);
      expect(result.exitCode, 65, reason: result.stderr);
      expect(treeSnapshot(process.root), before);
      expect(treeSnapshot(outside), outsideBefore);
      expect(Directory('${process.root.path}/.sdlc').existsSync(), isFalse);
      expect(process.home.listSync(), isEmpty);
      expect(process.temp.listSync(), isEmpty);
    });
  }

  test('el enlace y la dependencia ajena no se atraviesan', () async {
    hostileProject();
    final result = await process.run(['init', '--dry-run', '--json']);
    final codes = [
      for (final l in result.json['limitations']! as List) (l as Map)['code'],
    ];
    expect(codes, ['path_dependency_outside_root', 'symlink_not_followed']);
    final values = [
      for (final e in result.json['evidence']! as List) (e as Map)['value'],
    ];
    expect(values, isNot(contains('centinela')));
    expect(
      [for (final u in result.json['units']! as List) (u as Map)['path']],
      ['.', 'packages/b'],
    );
  });

  test('el orden de creación no cambia el JSON salvo las raíces', () async {
    Future<String> recognizeCreatedIn(List<String> order) async {
      final created = await Directory.systemTemp.createTemp('shipflow-orden-');
      final root = Directory(created.resolveSymbolicLinksSync());
      addTearDown(() => root.delete(recursive: true));
      for (final name in order) {
        File('${root.path}/packages/$name/pubspec.yaml')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('name: $name\nenvironment:\n  sdk: ^3.0.0\n');
      }
      final result = await process.run([
        'init',
        '--dry-run',
        '--json',
      ], at: root);
      return result.stdout.replaceAll(root.path, '<raíz>');
    }

    final forward = await recognizeCreatedIn(['a', 'b', 'c', 'd']);
    final backward = await recognizeCreatedIn(['d', 'c', 'b', 'a']);
    expect(backward, forward);
  });
}
