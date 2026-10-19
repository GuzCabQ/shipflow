import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'runner_support.dart';

void main() {
  final sandbox = RunnerSandbox()..register();

  Future<CliResponse> boundary(
    List<String> arguments, {
    RecognitionContributor? contributor,
  }) => runCliAtProcessBoundary(
    arguments,
    version: '1.0.0',
    workingDirectory: sandbox.root,
    recognizeProject: contributor ?? sandbox.contribute,
  );

  Future<Never> failing(_, {required ReportLimits reportLimits}) =>
      Future.error(
        StateError('defecto en ${sandbox.root.path}'),
        StackTrace.current,
      );

  test('un defecto en JSON es la respuesta interna estable', () async {
    final response = await boundary([
      'init',
      '--dry-run',
      '--json',
    ], contributor: failing);
    expect(response.exitCode, 70);
    expect(response.channel, CliOutputChannel.stdout);
    expect(
      response.payload,
      '{"schemaVersion":1,"type":"error","code":"internal_error",'
      '"message":"no se pudo completar la operación","exitCode":70}\n',
    );
  });

  test('un defecto en la vista humana no filtra nada', () async {
    final response = await boundary([
      'init',
      '--dry-run',
    ], contributor: failing);
    expect(response.exitCode, 70);
    expect(response.channel, CliOutputChannel.stderr);
    expect(response.payload, 'shipflow: no se pudo completar la operación.\n');
    for (final leak in ['StateError', 'defecto', sandbox.root.path, '#0']) {
      expect(response.payload, isNot(contains(leak)));
    }
  });

  test('sin fallos, la frontera responde lo mismo que runCli', () async {
    for (final arguments in [
      ['init', '--dry-run'],
      ['init', '--dry-run', '--json'],
      ['--help'],
      ['--version', '--json'],
      ['init'],
      ['--bogus', '--json'],
    ]) {
      final direct = await sandbox.run(arguments);
      final bounded = await boundary(arguments);
      expect(bounded.exitCode, direct.exitCode, reason: '$arguments');
      expect(bounded.channel, direct.channel, reason: '$arguments');
      expect(bounded.payload, direct.payload, reason: '$arguments');
    }
  });
}
