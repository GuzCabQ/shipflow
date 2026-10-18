@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'process_contract_support.dart';

void main() {
  final contract = CompiledContract()..register();

  group('ejecutable compilado fuera del checkout', () {
    Future<void> expectAllCases(
      Directory workingDirectory, {
      Map<String, String> environment = const {},
      List<String> prefix = const [],
    }) async {
      for (final arguments in cases) {
        contract.expectContract(
          arguments,
          await contract.run(
            contract.binary,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            prefix: prefix,
          ),
        );
      }
    }

    test('en un directorio temporal sin .git', () async {
      final directory = await Directory(
        '${contract.sandbox.path}/normal',
      ).create(recursive: true);
      final before = snapshot(directory);
      await expectAllCases(directory);
      expect(snapshot(directory), before);
    });

    test('en un directorio de sólo lectura no crea nada', () async {
      final directory = await Directory(
        '${contract.sandbox.path}/solo-lectura',
      ).create(recursive: true);
      await Process.run('chmod', ['0555', directory.path]);
      await expectAllCases(directory);
      expect(directory.listSync(), isEmpty);
    });

    test('dentro de un repositorio git ajeno', () async {
      final directory = await Directory(
        '${contract.sandbox.path}/git-ajeno',
      ).create(recursive: true);
      final init = await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: directory.path);
      expect(init.exitCode, 0, reason: '${init.stderr}');
      final before = snapshot(directory);
      await expectAllCases(directory);
      expect(snapshot(directory), before);
    });

    test(
      'un .sdlc/version y un pubspec.yaml vecinos no cambian la versión',
      () async {
        final directory = await Directory(
          '${contract.sandbox.path}/proyecto',
        ).create(recursive: true);
        final pinned = await File(
          '${directory.path}/.sdlc/version',
        ).create(recursive: true);
        pinned.writeAsStringSync('0.1.0\n');
        File(
          '${directory.path}/pubspec.yaml',
        ).writeAsStringSync('name: cli\nversion: 0.1.0\n');
        final observed = await contract.run(contract.binary, [
          '--version',
        ], workingDirectory: directory);
        expect(utf8.decode(observed.stdout), 'shipflow $compiledVersion\n');
        await expectAllCases(directory);
      },
    );

    for (final (name, environment) in [
      ('sin variables', <String, String>{}),
      ('locale C', {'LANG': 'C', 'LC_ALL': 'C'}),
      ('locale es_MX', {'LANG': 'es_MX.UTF-8', 'LC_ALL': 'es_MX.UTF-8'}),
      ('terminal mudo', {'TERM': 'dumb'}),
      (
        'terminal a color',
        {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
      ),
      ('NO_COLOR', {'NO_COLOR': '1'}),
      ('SHIPFLOW_VERSION en el ambiente', {'SHIPFLOW_VERSION': '6.6.6'}),
    ]) {
      test('el entorno no altera los bytes: $name', () async {
        final directory = await Directory(
          '${contract.sandbox.path}/entorno',
        ).create(recursive: true);
        await expectAllCases(directory, environment: environment);
      });
    }

    test('un shipflow anterior en el PATH no es el que se prueba', () async {
      final impostorDirectory = await Directory(
        '${contract.sandbox.path}/impostor',
      ).create(recursive: true);
      final impostor = File('${impostorDirectory.path}/shipflow')
        ..writeAsStringSync('#!/bin/sh\nprintf "shipflow 6.6.6\\n"\n');
      await Process.run('chmod', ['0755', impostor.path]);
      final path = '${impostorDirectory.path}:/usr/bin:/bin';
      final resolved = await Process.run(
        '/bin/sh',
        ['-c', 'shipflow --version'],
        environment: {'PATH': path},
        includeParentEnvironment: false,
      );
      expect(resolved.stdout, 'shipflow 6.6.6\n');
      final observed = await contract.run(
        contract.binary,
        ['--version'],
        workingDirectory: impostorDirectory,
        environment: {'PATH': path},
      );
      expect(utf8.decode(observed.stdout), 'shipflow $compiledVersion\n');
      await expectAllCases(impostorDirectory, environment: {'PATH': path});
    });

    test('sin red, sin escribir y sin lanzar procesos', () async {
      final directory = await Directory(
        '${contract.sandbox.path}/aislado',
      ).create(recursive: true);
      final List<String> prefix;
      if (Platform.isMacOS) {
        prefix = [
          '/usr/bin/sandbox-exec',
          '-p',
          '(version 1)(allow default)(deny network*)(deny process-fork)'
              '(deny file-write* (with no-report))',
        ];
      } else if (Platform.isLinux) {
        final probe = await Process.run('unshare', [
          '--user',
          '--map-root-user',
          '--net',
          'true',
        ]);
        prefix = probe.exitCode == 0
            ? ['unshare', '--user', '--map-root-user', '--net']
            : ['sudo', '-n', 'unshare', '--net'];
      } else {
        fail('sin mecanismo de aislamiento para ${Platform.operatingSystem}');
      }
      final isolation = await Process.run(prefix.first, [
        ...prefix.skip(1),
        '/bin/sh',
        '-c',
        'exit 0',
      ]);
      expect(
        isolation.exitCode,
        0,
        reason: 'el aislamiento no está disponible: ${isolation.stderr}',
      );
      final before = [
        contract.watchedHome,
        contract.watchedTemp,
        directory,
      ].map(snapshot);
      await expectAllCases(directory, prefix: prefix);
      expect(
        [contract.watchedHome, contract.watchedTemp, directory].map(snapshot),
        before,
      );
    });
  });
}
