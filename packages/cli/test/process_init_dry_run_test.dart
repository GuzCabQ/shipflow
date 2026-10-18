@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'init_process_support.dart';

void main() {
  final process = InitProcessSandbox()..register();

  group('desde el código fuente', () {
    test('una raíz Dart reconocida informa esa raíz', () async {
      process.place('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.0.0\n');
      final result = await process.runSource(['init', '--dry-run', '--json']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stderr, isEmpty);
      expect(result.json['status'], 'recognized');
      expect(result.json['requestedRoot'], process.root.path);
      expect(result.json['resolvedRoot'], process.root.path);
    });

    test('una raíz vacía no es soportada', () async {
      final result = await process.runSource(['init', '--dry-run', '--json']);
      expect(result.exitCode, 65);
      expect(result.json['status'], 'unsupported');
    });

    test('la forma del piloto es ambigua', () async {
      final shape = await pilotShape();
      final result = await process.runSource([
        'init',
        '--dry-run',
        '--json',
      ], at: shape);
      expect(result.exitCode, 65);
      expect(result.json['status'], 'ambiguous');
      expect(result.json['resolvedRoot'], shape.resolveSymbolicLinksSync());
    });
  });

  group('ejecutable compilado fuera del checkout', () {
    test('ayuda y versión conservan V0', () async {
      final version = await process.run(['--version']);
      expect(version.exitCode, 0);
      expect(version.stdout, 'shipflow $v1Version\n');
      expect(version.stderr, isEmpty);
      final help = await process.run(['--help', '--json']);
      expect(help.exitCode, 0);
      expect(help.json['type'], 'help');
      expect(help.json['commands'], isNotEmpty);
    });

    test('un proyecto Flutter inequívoco se reconoce, humano y JSON', () async {
      process.place(
        'pubspec.yaml',
        'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      final json = await process.run(['init', '--dry-run', '--json']);
      expect(json.exitCode, 0, reason: json.stderr);
      expect(json.stderr, isEmpty);
      expect(json.json['status'], 'recognized');
      expect(
        (json.json['candidates']! as List).single,
        containsPair('id', 'flutter'),
      );
      final human = await process.run(['init', '--dry-run']);
      expect(human.exitCode, 0);
      expect(human.stderr, isEmpty);
      expect(
        human.stdout,
        startsWith('Shipflow · reconocimiento\nEstado: recognized\n'),
      );
      expect(
        human.stdout,
        endsWith(
          'Efectos: 0 archivos, 0 directorios, 0 procesos, 0 solicitudes de red.\n',
        ),
      );
    });

    test('la forma del piloto reproduce lo fijado', () async {
      final result = await process.run([
        'init',
        '--dry-run',
        '--json',
      ], at: await pilotShape());
      expect(result.exitCode, 65);
      expect(result.json['status'], 'ambiguous');
      expect(
        [for (final c in result.json['conflicts']! as List) (c as Map)['code']],
        ['toolchain_outside_constraint', 'toolchain_versions_disagree'],
      );
      expect(
        (result.json['units']! as List).single,
        containsPair('path', 'packages/smooth_app'),
      );
      expect(result.json['proposal'], containsPair('eligible', false));
    });

    test('init sin --dry-run es uso inválido y no inspecciona', () async {
      final result = await process.run(['init']);
      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('--dry-run'));
      final json = await process.run(['init', '--bogus', '--json']);
      expect(json.exitCode, 64);
      expect(json.stderr, isEmpty);
      expect(json.json['code'], 'invalid_usage');
    });

    test('una raíz sin permiso de lectura es invalid_root', () async {
      final closed = Directory('${process.root.path}/cerrada')..createSync();
      await Process.run('chmod', ['111', closed.path]);
      final result = await process.run([
        'init',
        '--dry-run',
        '--json',
      ], at: closed);
      expect(result.exitCode, 66);
      expect(result.json['status'], 'invalid_root');
      expect(result.json['resolvedRoot'], isNull);
    });
  });
}
