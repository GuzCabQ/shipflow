import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cli/cli.dart';
import 'package:test/test.dart';
import 'static_evaluation.dart';

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

/// El artefacto compilado con [compiledVersion] dentro de un sandbox con HOME
/// y TMPDIR propios, para observar qué escribe el proceso.
final class CompiledContract {
  late Directory sandbox;
  late String binary;
  late String entrypoint;
  late Directory watchedHome;
  late Directory watchedTemp;

  /// Compila una vez para todo el archivo y borra el sandbox al terminar.
  void register() {
    setUpAll(_compile);
    tearDownAll(_remove);
  }

  Future<void> _compile() async {
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
  }

  Future<void> _remove() async {
    if (await sandbox.exists()) {
      await Process.run('chmod', ['-R', 'u+w', sandbox.path]);
      await sandbox.delete(recursive: true);
    }
  }

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
    final expected = evaluate(arguments, version: compiledVersion);
    final payload = utf8.encode(expected.payload);
    final onStdout = expected.channel == CliOutputChannel.stdout;
    expect(observed.exitCode, expected.exitCode, reason: '$arguments');
    expect(observed.stdout, onStdout ? payload : isEmpty, reason: '$arguments');
    expect(observed.stderr, onStdout ? isEmpty : payload, reason: '$arguments');
  }
}
