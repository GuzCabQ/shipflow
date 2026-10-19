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
  /// Un enlace en `vendor` limita también por sí solo: el escáner no lo
  /// sigue.
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
    sandbox.place('b/pubspec.yaml', 'name: x\n');
    expect(await limitationsFor('a/../b'), isEmpty);
  });

  test('un enlace detiene el trayecto antes de su destino', () async {
    Directory('${outside.path}/deep').createSync();
    Directory('${outside.path}/dep').createSync();
    Link('${sandbox.root.path}/vendor').createSync('${outside.path}/deep');
    expect(await limitationsFor('vendor/../dep'), {
      'unsupported_local_reference',
      'symlink_not_followed',
    });
  });

  test('el destino de un enlace no cambia el resultado', () async {
    final vendor = Link('${sandbox.root.path}/vendor')
      ..createSync(outside.path);
    final live = await limitationsFor('vendor/falta/pkg');
    vendor
      ..deleteSync()
      ..createSync('${outside.path}/no-existe');
    expect(await limitationsFor('vendor/falta/pkg'), live);
    expect(live, {'unsupported_local_reference', 'symlink_not_followed'});
  });

  test(
    'un enlace omitido por una exclusión no se resuelve para salir',
    () async {
      Link('${sandbox.root.path}/build').createSync(outside.path);
      expect(await limitationsFor('build/../dep'), {'required_path_excluded'});
    },
  );

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

  test('nada existe debajo de un archivo interior', () async {
    sandbox.place('archivo', '');
    expect(await limitationsFor('archivo/sub'), {'path_dependency_unresolved'});
  });

  test('un .. no sube desde un archivo interior', () async {
    sandbox.place('archivo', '');
    sandbox.place('b/pubspec.yaml', 'name: x\n');
    expect(await limitationsFor('archivo/../b'), {
      'path_dependency_unresolved',
    });
  });

  test('un .. no sube desde una entidad especial', () async {
    await Process.run('mkfifo', ['${sandbox.root.path}/fifo']);
    sandbox.place('b/pubspec.yaml', 'name: x\n');
    expect(await limitationsFor('fifo/../b'), {'path_dependency_unresolved'});
  });

  test('la limitación nombra la dependencia que la causa', () async {
    sandbox.place(
      'pubspec.yaml',
      'name: a\ndependencies:\n  x: {path: ../x}\n  y: {path: falta/../y}\n',
    );
    final contribution = await recognizeDartProject(sandbox.root);
    expect([for (final l in contribution.limitations) l.message]..sort(), [
      'la dependencia local «dependencies.x: ../x» sale de la raíz y no se '
          'atraviesa; queda sin corroborar y bloquea la propuesta. '
          'Inspecciona una raíz que contenga ambos paquetes.',
      'la dependencia local «dependencies.y: falta/../y» no se pudo resolver '
          'y no se atraviesa; queda sin corroborar y bloquea la propuesta. '
          'Comprueba que la ruta exista y se pueda leer.',
    ]);
  });

  test('una ruta inexistente bajo la raíz queda dentro', () async {
    expect(await limitationsFor('vendor/pkg'), {'required_manifest_missing'});
  });
}
