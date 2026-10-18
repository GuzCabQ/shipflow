import 'package:cli/cli.dart';
import 'package:test/test.dart';

import 'cli_support.dart';
import 'static_evaluation.dart';

void main() {
  group('ayuda', () {
    for (final arguments in [
      <String>[],
      ['--help'],
      ['-h'],
    ]) {
      test('$arguments emite la ayuda humana exacta', () {
        expectResponse(
          arguments,
          exitCode: 0,
          channel: CliOutputChannel.stdout,
          payload: helpText,
        );
      });
    }

    for (final arguments in [
      ['--json'],
      ['--help', '--json'],
      ['--json', '--help'],
      ['-h', '--json'],
      ['--json', '-h'],
    ]) {
      test('$arguments emite la ayuda JSON exacta', () {
        expectResponse(
          arguments,
          exitCode: 0,
          channel: CliOutputChannel.stdout,
          payload: helpJson,
        );
      });
    }
  });

  group('versión', () {
    test('--version emite la versión incorporada', () {
      expectResponse(
        ['--version'],
        exitCode: 0,
        channel: CliOutputChannel.stdout,
        payload: 'shipflow 1.2.3-rc.1+build.7\n',
      );
    });

    for (final arguments in [
      ['--version', '--json'],
      ['--json', '--version'],
    ]) {
      test('$arguments emite la versión JSON exacta', () {
        expectResponse(
          arguments,
          exitCode: 0,
          channel: CliOutputChannel.stdout,
          payload: versionJson,
        );
      });
    }

    test('la versión es la recibida, no una constante', () {
      expect(
        evaluate(['--version'], version: '0.0.0-dev').payload,
        'shipflow 0.0.0-dev\n',
      );
    });
  });
}
