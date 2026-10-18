import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

import 'cli_support.dart';

String initHumanError(String reason) =>
    "shipflow: $reason\nUsa 'shipflow init --help'.\n";

void expectInitError(List<String> arguments, String reason) {
  final json = arguments.contains('--json');
  expectResponse(
    arguments,
    exitCode: 64,
    channel: json ? CliOutputChannel.stdout : CliOutputChannel.stderr,
    payload: json ? jsonError(jsonEncode(reason)) : initHumanError(reason),
  );
}

void main() {
  group('formas válidas', () {
    for (final (arguments, json) in [
      (['init', '--dry-run'], false),
      (['init', '--dry-run', '--json'], true),
      (['init', '--json', '--dry-run'], true),
    ]) {
      test('$arguments pide reconocer', () {
        final command = parseCliCommand(arguments);
        expect(command, isA<RunInitDryRun>());
        expect(command.json, json);
      });
    }

    for (final arguments in [
      ['init', '-h'],
      ['init', '--help'],
    ]) {
      test('$arguments emite la ayuda de init', () {
        expectResponse(
          arguments,
          exitCode: 0,
          channel: CliOutputChannel.stdout,
          payload: initHelpText,
        );
      });

      test('$arguments con --json emite la ayuda JSON de init', () {
        for (final withJson in [
          [...arguments, '--json'],
          [arguments.first, '--json', ...arguments.skip(1)],
        ]) {
          expectResponse(
            withJson,
            exitCode: 0,
            channel: CliOutputChannel.stdout,
            payload: initHelpJson,
          );
        }
      });
    }
  });

  group('uso inválido', () {
    const missingDryRun =
        'init requiere --dry-run: esta versión sólo reconoce el proyecto, '
        'sin modificarlo';

    test('init solo explica que hace falta --dry-run', () {
      expectInitError(['init'], missingDryRun);
      expectInitError(['init', '--json'], missingDryRun);
    });

    test('las opciones antes de init no son globales', () {
      expectResponse(
        ['--json', 'init', '--dry-run'],
        exitCode: 64,
        channel: CliOutputChannel.stdout,
        payload: jsonError('"argumento inesperado: \'init\'"'),
      );
      expectResponse(
        ['--dry-run', 'init'],
        exitCode: 64,
        channel: CliOutputChannel.stderr,
        payload: humanError("opción desconocida: '--dry-run'"),
      );
    });

    for (final (arguments, reason) in [
      (
        ['init', '--help', '--dry-run'],
        "'--help' y '--dry-run' no se pueden combinar",
      ),
      (['init', '--dry-run', '-h'], "'--dry-run' y '-h' no se pueden combinar"),
      (['init', '--dry-run', '--dry-run'], "opción repetida: '--dry-run'"),
      (['init', '--dry-run', '--json', '--json'], "opción repetida: '--json'"),
      (['init', '-h', '--help'], "'-h' y '--help' son la misma opción"),
      (['init', '--dry-run', '--force'], "opción desconocida: '--force'"),
      (['init', '--dry-run', '.'], "argumento inesperado: '.'"),
      (['init', 'init'], "argumento inesperado: 'init'"),
      (['init', '--version'], "opción desconocida: '--version'"),
      (['init', '--dry-run=true'], "opción desconocida: '--dry-run=true'"),
      (['init', '--json=1', '--dry-run'], "opción desconocida: '--json=1'"),
      (['init', '--dry'], "opción desconocida: '--dry'"),
      (['init', '--dry-ru'], "opción desconocida: '--dry-ru'"),
      (['init', '-d'], "opción desconocida: '-d'"),
      (['init', '--x', '--dry-run', '--dry-run'], "opción desconocida: '--x'"),
    ]) {
      test('$arguments: $reason', () => expectInitError(arguments, reason));
    }

    test('--json después de un token inválido sigue eligiendo JSON', () {
      expectInitError([
        'init',
        '--bogus',
        '--json',
      ], "opción desconocida: '--bogus'");
      expectInitError([
        'init',
        '--json',
        '--bogus',
      ], "opción desconocida: '--bogus'");
    });

    test('un error de init no pide reconocer', () {
      expect(parseCliCommand(['init']), isA<StaticCommand>());
      expect(parseCliCommand(['init', '--dry-run', 'x']), isA<StaticCommand>());
    });
  });
}
