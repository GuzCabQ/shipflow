@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

const compiledVersion = '9.8.7-contrato.1+build.5';
const failureDiagnostic = 'shipflow: no se pudo completar la operación.\n';

const cases = <List<String>>[
  [],
  ['--help'],
  ['-h'],
  ['--json'],
  ['--help', '--json'],
  ['--json', '-h'],
  ['--version'],
  ['--version', '--json'],
  ['--json', '--version'],
  ['--inventada', '--help'],
  ['--help', '--version'],
  ['--version', '--version'],
  ['-h', '--help'],
  ['--json', '--inventada'],
  ['--inventada', '--json'],
  ['--json=true', '--version'],
  ['--'],
  ['init'],
  ['línea\nnueva\x1b[2J'],
  ['--json', 'a b'],
];

Future<Directory> packageRoot() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:cli/cli.dart'),
  );
  return File.fromUri(barrel!).parent.parent;
}

/// Lista recursiva con tamaño y fecha de cada entrada: cambia si el proceso
/// crea, borra o reescribe algo debajo de [directory].
String snapshot(Directory directory) {
  final entries = [
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    ))
      '${entity.path}|${entity.statSync().size}|'
          '${entity.statSync().modified.microsecondsSinceEpoch}',
  ]..sort();
  return entries.join('\n');
}

final class Observed {
  Observed(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final List<int> stdout;
  final List<int> stderr;
}

void main() {
  late Directory sandbox;
  late String binary;
  late String entrypoint;
  late Directory watchedHome;
  late Directory watchedTemp;

  Future<Observed> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    Map<String, String> environment = const {},
    List<String> prefix = const [],
  }) async {
    expect(
      File(executable).isAbsolute,
      isTrue,
      reason: 'el contrato se prueba invocando el artefacto exacto',
    );
    final command = [...prefix, executable, ...arguments];
    final result = await Process.run(
      command.first,
      command.skip(1).toList(),
      workingDirectory: workingDirectory.path,
      environment: {
        'HOME': watchedHome.path,
        'TMPDIR': watchedTemp.path,
        ...environment,
      },
      includeParentEnvironment: false,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    return Observed(
      result.exitCode,
      result.stdout as List<int>,
      result.stderr as List<int>,
    );
  }

  void expectContract(List<String> arguments, Observed observed) {
    final expected = evaluateCli(arguments, version: compiledVersion);
    final payload = utf8.encode(expected.payload);
    final onStdout = expected.channel == CliOutputChannel.stdout;
    expect(observed.exitCode, expected.exitCode, reason: '$arguments');
    expect(observed.stdout, onStdout ? payload : isEmpty, reason: '$arguments');
    expect(observed.stderr, onStdout ? isEmpty : payload, reason: '$arguments');
  }

  setUpAll(() async {
    final root = await packageRoot();
    entrypoint = '${root.path}/bin/shipflow.dart';
    sandbox = await Directory.systemTemp.createTemp('shipflow-contrato-');
    watchedHome = await Directory('${sandbox.path}/home').create();
    watchedTemp = await Directory('${sandbox.path}/tmp').create();
    final artifacts = await Directory('${sandbox.path}/artefacto').create();
    binary = '${artifacts.path}/shipflow';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSHIPFLOW_VERSION=$compiledVersion',
      '-o',
      binary,
      entrypoint,
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
    expect(root.path.startsWith(sandbox.path), isFalse);
  });

  tearDownAll(() async {
    if (await sandbox.exists()) {
      await Process.run('chmod', ['-R', 'u+w', sandbox.path]);
      await sandbox.delete(recursive: true);
    }
  });

  group('entrypoint en desarrollo', () {
    test('sin declaración de compilación informa 0.0.0-dev', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        entrypoint,
        '--version',
      ]);
      expect(result.stdout, 'shipflow 0.0.0-dev\n');
      expect(result.stderr, '');
      expect(result.exitCode, 0);
    });

    test('con -DSHIPFLOW_VERSION informa la versión declarada', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        '-DSHIPFLOW_VERSION=4.5.6-dev.1',
        entrypoint,
        '--version',
      ]);
      expect(result.stdout, 'shipflow 4.5.6-dev.1\n');
      expect(result.stderr, '');
      expect(result.exitCode, 0);
    });

    test('el uso inválido sale por stderr con código 64', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        entrypoint,
        '--inventada',
      ]);
      expect(result.stdout, '');
      expect(
        result.stderr,
        "shipflow: opción desconocida: '--inventada'\n"
        "Usa 'shipflow --help'.\n",
      );
      expect(result.exitCode, 64);
    });
  });

  group('ejecutable compilado fuera del checkout', () {
    Future<void> expectAllCases(
      Directory workingDirectory, {
      Map<String, String> environment = const {},
      List<String> prefix = const [],
    }) async {
      for (final arguments in cases) {
        expectContract(
          arguments,
          await run(
            binary,
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
        '${sandbox.path}/normal',
      ).create(recursive: true);
      final before = snapshot(directory);
      await expectAllCases(directory);
      expect(snapshot(directory), before);
    });

    // V0-S9
    test('en un directorio de sólo lectura no crea nada', () async {
      final directory = await Directory(
        '${sandbox.path}/solo-lectura',
      ).create(recursive: true);
      await Process.run('chmod', ['0555', directory.path]);
      await expectAllCases(directory);
      expect(directory.listSync(), isEmpty);
    });

    test('dentro de un repositorio git ajeno', () async {
      final directory = await Directory(
        '${sandbox.path}/git-ajeno',
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

    // V0-S6, V0-S7
    test(
      'un .sdlc/version y un pubspec.yaml vecinos no cambian la versión',
      () async {
        final directory = await Directory(
          '${sandbox.path}/proyecto',
        ).create(recursive: true);
        final pinned = await File(
          '${directory.path}/.sdlc/version',
        ).create(recursive: true);
        pinned.writeAsStringSync('0.1.0\n');
        File(
          '${directory.path}/pubspec.yaml',
        ).writeAsStringSync('name: cli\nversion: 0.1.0\n');
        final observed = await run(binary, [
          '--version',
        ], workingDirectory: directory);
        expect(utf8.decode(observed.stdout), 'shipflow $compiledVersion\n');
        await expectAllCases(directory);
      },
    );

    // V0-S11
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
          '${sandbox.path}/entorno',
        ).create(recursive: true);
        await expectAllCases(directory, environment: environment);
      });
    }

    // V0-S26
    test('un shipflow anterior en el PATH no es el que se prueba', () async {
      final impostorDirectory = await Directory(
        '${sandbox.path}/impostor',
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
      final observed = await run(
        binary,
        ['--version'],
        workingDirectory: impostorDirectory,
        environment: {'PATH': path},
      );
      expect(utf8.decode(observed.stdout), 'shipflow $compiledVersion\n');
      await expectAllCases(impostorDirectory, environment: {'PATH': path});
    });

    // V0-S8, V0-S38
    test('sin red, sin escribir y sin lanzar procesos', () async {
      final directory = await Directory(
        '${sandbox.path}/aislado',
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
      final before = [watchedHome, watchedTemp, directory].map(snapshot);
      await expectAllCases(directory, prefix: prefix);
      expect([watchedHome, watchedTemp, directory].map(snapshot), before);
    });

    // V0-S24
    test('con stdout cerrado devuelve 70 y no afirma JSON', () async {
      for (final arguments in [
        ['--json'],
        ['--version', '--json'],
        ['--json', '--inventada'],
        ['--help'],
      ]) {
        final observed = await run('/bin/sh', [
          '-c',
          r'exec "$0" "$@" 1>&-',
          binary,
          ...arguments,
        ], workingDirectory: sandbox);
        expect(observed.exitCode, 70, reason: '$arguments');
        expect(utf8.decode(observed.stderr), failureDiagnostic);
      }
    });

    test('con stderr cerrado un error devuelve 70', () async {
      final observed = await run('/bin/sh', [
        '-c',
        r'exec "$0" "$@" 2>&-',
        binary,
        '--inventada',
      ], workingDirectory: sandbox);
      expect(observed.exitCode, 70);
      expect(utf8.decode(observed.stdout), failureDiagnostic);
    });

    // V0-S18
    test('un error controlado no filtra detalles del runtime', () async {
      for (final arguments in cases) {
        final observed = await run(
          binary,
          arguments,
          workingDirectory: sandbox,
        );
        final text = utf8.decode(observed.stdout + observed.stderr);
        for (final leak in ['#0', 'dart:', 'Unhandled', 'Exception', '.dart']) {
          expect(text, isNot(contains(leak)), reason: '$arguments');
        }
        expect(text, isNot(contains(sandbox.path)));
      }
    });

    // V0-S5
    test('cada respuesta JSON es exactamente una línea', () async {
      for (final arguments in cases.where((a) => a.contains('--json'))) {
        final observed = await run(
          binary,
          arguments,
          workingDirectory: sandbox,
        );
        final lines = const LineSplitter().convert(
          utf8.decode(observed.stdout),
        );
        expect(lines, hasLength(1), reason: '$arguments');
        expect(jsonDecode(lines.single), isA<Map<String, Object?>>());
        expect(observed.stderr, isEmpty);
      }
    });

    // V0-S25
    test('el artefacto se llama shipflow y no responde como sdlc', () async {
      expect(binary.split('/').last, 'shipflow');
      for (final arguments in cases) {
        final observed = await run(
          binary,
          arguments,
          workingDirectory: sandbox,
        );
        expect(
          utf8.decode(observed.stdout + observed.stderr).toLowerCase(),
          isNot(contains('sdlc')),
        );
      }
    });
  });

  // V0-S38
  test('el ejecutable público sólo importa lo que necesita', () async {
    final root = await packageRoot();
    final imports = <String, Set<String>>{};
    for (final directory in ['lib', 'bin']) {
      for (final file
          in Directory('${root.path}/$directory')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final relative = file.path.substring(root.path.length + 1);
        imports[relative] = {
          for (final m in RegExp(
            r"^(?:import|export)\s+'([^']+)'",
            multiLine: true,
          ).allMatches(file.readAsStringSync()))
            m.group(1)!,
        };
      }
    }
    expect(imports, {
      'bin/shipflow.dart': {'dart:io', 'package:cli/cli.dart'},
      'lib/cli.dart': {
        'src/build_version.dart',
        'src/cli_application.dart',
        'src/cli_emitter.dart',
        'src/cli_response.dart',
      },
      'lib/src/build_version.dart': <String>{},
      'lib/src/cli_application.dart': {'dart:convert', 'cli_response.dart'},
      'lib/src/cli_emitter.dart': {
        'dart:convert',
        'dart:io',
        'cli_response.dart',
      },
      'lib/src/cli_response.dart': <String>{},
    });
    for (final relative in ['bin/shipflow.dart', 'lib/src/cli_emitter.dart']) {
      final source = File('${root.path}/$relative').readAsStringSync();
      for (final effect in [
        'Process',
        'File',
        'Directory',
        'Link',
        'Socket',
        'HttpClient',
        'InternetAddress',
        'Platform',
        'exit(',
      ]) {
        expect(source, isNot(contains(effect)), reason: '$relative: $effect');
      }
    }
  });

  // V0-S16
  test('ningún comentario de packages/cli nombra una ruta local', () async {
    final root = await packageRoot();
    final local = RegExp(
      r'/Users/|/home/|~/|/private/|/var/folders/|file://|[A-Za-z]:\\|'
      r'Downloads|Obsidian',
      caseSensitive: false,
    );
    final found = <String>[];
    for (final file
        in root
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) => f.path.endsWith('.dart') && !f.path.contains('.dart_tool'),
            )) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//') && local.hasMatch(line)) {
          found.add('${file.path.substring(root.path.length + 1)}:${i + 1}');
        }
      }
    }
    expect(found, isEmpty);
  });
}
