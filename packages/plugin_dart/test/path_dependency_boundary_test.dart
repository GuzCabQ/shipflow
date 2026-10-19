import 'dart:io';

import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

void main() {
  final sandbox = ScanSandbox()..register();
  late Directory outside;

  setUp(() async {
    final made = await Directory.systemTemp.createTemp('shipflow-fuera-');
    outside = Directory(made.resolveSymbolicLinksSync());
  });
  tearDown(() => outside.delete(recursive: true));

  /// Los códigos de limitación de una raíz cuyo manifiesto declara [path].
  /// `build` es una exclusión conocida: un enlace ahí no limita por sí solo.
  Future<Set<String>> limitationsFor(String path) async {
    sandbox.place(
      'pubspec.yaml',
      'name: a\ndependencies:\n  x: {path: $path}\n',
    );
    final contribution = await recognizeDartProject(sandbox.root);
    return {for (final l in contribution.limitations) l.code};
  }

  test('un .. dentro de la raíz sigue dentro', () async {
    sandbox.directory('a');
    sandbox.directory('b');
    expect(await limitationsFor('a/../b'), isEmpty);
  });

  test('un .. se aplica después de seguir el enlace que lo precede', () async {
    Directory('${outside.path}/deep').createSync();
    Directory('${outside.path}/dep').createSync();
    Link('${sandbox.root.path}/build').createSync('${outside.path}/deep');
    expect(await limitationsFor('build/../dep'), {
      'path_dependency_outside_root',
    });
  });

  test('un enlace seguido de un tramo inexistente sale', () async {
    Link('${sandbox.root.path}/build').createSync(outside.path);
    expect(await limitationsFor('build/falta/pkg'), {
      'path_dependency_outside_root',
    });
  });

  test('un .. después de un tramo inexistente no se resuelve', () async {
    sandbox.directory('b');
    expect(await limitationsFor('falta/../b'), {'path_dependency_unresolved'});
  });

  test('un enlace roto no se toma como pertenencia', () async {
    Link('${sandbox.root.path}/build').createSync('${outside.path}/no-existe');
    expect(await limitationsFor('build/pkg'), {'path_dependency_unresolved'});
  });

  test('un .. por encima de / se queda en /', () async {
    expect(await limitationsFor('/../..'), {'path_dependency_outside_root'});
  });

  test('una ruta con NUL no es una ruta que el sistema resuelva', () async {
    expect(await limitationsFor(r'"a\0b"'), {'path_dependency_unresolved'});
  });

  test('un tramo sin permiso no se toma como inexistente', () async {
    final locked = sandbox.directory('cerrada');
    Directory('${locked.path}/sub').createSync();
    await Process.run('chmod', ['000', locked.path]);
    addTearDown(() => Process.run('chmod', ['755', locked.path]));
    // El escáner tampoco puede listar la carpeta cerrada.
    expect(await limitationsFor('cerrada/sub/pkg'), {
      'path_dependency_unresolved',
      'subtree_unreadable',
    });
  });

  test('un sufijo bajo un archivo interior queda dentro', () async {
    sandbox.place('archivo', '');
    expect(await limitationsFor('archivo/sub'), isEmpty);
  });

  test('la limitación nombra la dependencia que la causa', () async {
    sandbox.place(
      'pubspec.yaml',
      'name: a\ndependencies:\n  x: {path: ../x}\n  y: {path: falta/../y}\n',
    );
    final contribution = await recognizeDartProject(sandbox.root);
    expect([for (final l in contribution.limitations) l.message]..sort(), [
      'la dependencia local «dependencies.x: ../x» sale de la raíz y no se '
          'atraviesa',
      'la dependencia local «dependencies.y: falta/../y» no se pudo resolver '
          'y no se atraviesa',
    ]);
  });

  test('una ruta inexistente bajo la raíz queda dentro', () async {
    expect(await limitationsFor('vendor/pkg'), isEmpty);
  });
}
