import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

const version = '1.2.3-rc.1+build.7';

const helpText =
    'Shipflow supervisa cambios de software verificables y recuperables.\n'
    '\n'
    'Uso:\n'
    '  shipflow [--help] [--json]\n'
    '  shipflow --version [--json]\n'
    '\n'
    'Opciones:\n'
    '  -h, --help  Muestra esta ayuda.\n'
    '  --version   Muestra la versión del ejecutable.\n'
    '  --json      Emite una única respuesta JSON.\n';

const helpJson =
    '{"schemaVersion":1,"type":"help","name":"shipflow","usage":["shipflow '
    '[--help] [--json]","shipflow --version [--json]"],"options":[{"flags":'
    '["-h","--help"],"description":"Muestra esta ayuda."},{"flags":'
    '["--version"],"description":"Muestra la versión del ejecutable."},'
    '{"flags":["--json"],"description":"Emite una única respuesta JSON."}],'
    '"exitCode":0}\n';

const versionJson =
    '{"schemaVersion":1,"type":"version","name":"shipflow",'
    '"version":"1.2.3-rc.1+build.7","exitCode":0}\n';

String humanError(String reason) =>
    "shipflow: $reason\nUsa 'shipflow --help'.\n";

String jsonError(String quotedReason) =>
    '{"schemaVersion":1,"type":"error","code":"invalid_usage",'
    '"message":$quotedReason,"exitCode":64}\n';

void expectResponse(
  List<String> arguments, {
  required int exitCode,
  required CliOutputChannel channel,
  required String payload,
}) {
  final response = evaluateCli(arguments, version: version);
  expect(response.exitCode, exitCode, reason: '$arguments');
  expect(response.channel, channel, reason: '$arguments');
  expect(response.payload, payload, reason: '$arguments');
}

void expectHumanError(List<String> arguments, String reason) => expectResponse(
  arguments,
  exitCode: 64,
  channel: CliOutputChannel.stderr,
  payload: humanError(reason),
);

void expectJsonError(List<String> arguments, String quotedReason) =>
    expectResponse(
      arguments,
      exitCode: 64,
      channel: CliOutputChannel.stdout,
      payload: jsonError(quotedReason),
    );

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
        evaluateCli(['--version'], version: '0.0.0-dev').payload,
        'shipflow 0.0.0-dev\n',
      );
    });
  });

  group('uso inválido humano', () {
    test('un flag desconocido junto a --help no produce ayuda', () {
      expectHumanError([
        '--inventada',
        '--help',
      ], "opción desconocida: '--inventada'");
      expectHumanError([
        '--help',
        '--inventada',
      ], "opción desconocida: '--inventada'");
    });

    test('--help y --version son contradictorios', () {
      expectHumanError([
        '--help',
        '--version',
      ], "'--help' y '--version' no se pueden combinar");
      expectHumanError([
        '--version',
        '-h',
      ], "'--version' y '-h' no se pueden combinar");
    });

    test('repetir --version es un duplicado visible', () {
      expectHumanError([
        '--version',
        '--version',
      ], "opción repetida: '--version'");
    });

    test('repetir --help o -h es un duplicado visible', () {
      expectHumanError(['--help', '--help'], "opción repetida: '--help'");
      expectHumanError(['-h', '-h'], "opción repetida: '-h'");
    });

    test('-h y --help juntos son la misma opción duplicada', () {
      expectHumanError(['-h', '--help'], "'-h' y '--help' son la misma opción");
      expectHumanError(['--help', '-h'], "'--help' y '-h' son la misma opción");
    });

    test('--json=true es desconocido y no activa JSON', () {
      expectHumanError([
        '--json=true',
        '--version',
      ], "opción desconocida: '--json=true'");
    });

    for (final flag in [
      '--',
      '-',
      '--hel',
      '--vers',
      '--Help',
      '--HELP',
      '-v',
      '-V',
      '-hj',
      '--help=1',
      '--version=1.0.0',
      '--no-json',
      '--init',
    ]) {
      test('$flag es una opción desconocida', () {
        expectHumanError([flag], "opción desconocida: '$flag'");
      });
    }

    for (final positional in ['init', 'help', 'version', 'analyze']) {
      test('$positional es un argumento posicional inesperado', () {
        expectHumanError([positional], "argumento inesperado: '$positional'");
      });
    }

    test('un posicional después de una acción válida es inválido', () {
      expectHumanError(['--version', 'extra'], "argumento inesperado: 'extra'");
    });

    test('un argumento vacío es un posicional inesperado', () {
      expectHumanError([''], "argumento inesperado: ''");
    });

    test('el primer problema en orden de aparición es el que se nombra', () {
      expectHumanError([
        '--help',
        '--version',
        '--inventada',
      ], "'--help' y '--version' no se pueden combinar");
      expectHumanError([
        '--inventada',
        '--help',
        '--version',
      ], "opción desconocida: '--inventada'");
    });
  });

  group('uso inválido JSON', () {
    test('--json --inventada produce un único objeto de error', () {
      expectJsonError([
        '--json',
        '--inventada',
      ], '"opción desconocida: \'--inventada\'"');
    });

    test('--json después del inválido también produce JSON', () {
      expectJsonError([
        '--inventada',
        '--json',
      ], '"opción desconocida: \'--inventada\'"');
    });

    test('--json repetido es un duplicado reportado en JSON', () {
      expectJsonError(['--json', '--json'], '"opción repetida: \'--json\'"');
    });

    test('una contradicción con --json se reporta en JSON', () {
      expectJsonError([
        '--json',
        '--help',
        '--version',
      ], '"\'--help\' y \'--version\' no se pueden combinar"');
    });

    test('un argumento con escapes viaja en una sola línea JSON', () {
      expectJsonError(
        ['--json', 'a\nb'],
        r'''"argumento inesperado: 'a\\nb'"''',
      );
    });
  });

  group('argumentos reflejados', () {
    for (final (raw, shown) in [
      ('línea\nnueva', r'línea\nnueva'),
      ('a\tb\rc', r'a\tb\rc'),
      ('\x1b[31mrojo\x1b[0m', r'\x1b[31mrojo\x1b[0m'),
      ('\x00', r'\x00'),
      ('\x7f', r'\x7f'),
      ('\u0085', r'\x85'),
      ('\u009b', r'\x9b'),
      ('a\u2028b', r'a\u{2028}b'),
      ('a\u2029b', r'a\u{2029}b'),
      ('\u202Eabc', r'\u{202e}abc'),
      ('\u2066x\u2069', r'\u{2066}x\u{2069}'),
      ("it's", r"it\'s"),
      (r'a\b', r'a\\b'),
      ('\uD800', r'\u{d800}'),
    ]) {
      test('${jsonEncode(raw)} se refleja escapado en una línea', () {
        final response = evaluateCli([raw], version: version);
        expect(response.payload, humanError("argumento inesperado: '$shown'"));
        expect('\n'.allMatches(response.payload).length, 2);
      });
    }
  });

  group('truncamiento', () {
    String reflected(String argument) {
      final firstLine = evaluateCli([
        argument,
      ], version: version).payload.split('\n').first;
      final start = firstLine.indexOf("'") + 1;
      final end = firstLine.lastIndexOf("'");
      return firstLine.substring(start, end);
    }

    test('160 caracteres se reflejan completos', () {
      expect(reflected('a' * 160), 'a' * 160);
    });

    test('161 caracteres se truncan a 160 más …', () {
      expect(reflected('a' * 161), '${'a' * 160}…');
    });

    test('un argumento de un megabyte se trunca a 160 más …', () {
      final payload = evaluateCli(['x' * (1 << 20)], version: version).payload;
      expect(payload, humanError("argumento inesperado: '${'x' * 160}…'"));
    });

    test('se cuentan caracteres Unicode, no unidades de código', () {
      expect(reflected('ñ' * 200), '${'ñ' * 160}…');
      expect(reflected('😀' * 200), '${'😀' * 160}…');
    });

    test('un escape no se corta a la mitad', () {
      expect(reflected('${'a' * 159}\n'), '${'a' * 159}…');
      expect(reflected('${'a' * 158}\n'), '${'a' * 158}\\n');
    });

    test('los escapes cuentan dentro del límite', () {
      expect(reflected('\n' * 100), '${r'\n' * 80}…');
    });
  });

  group('invariantes de toda respuesta', () {
    final cases = <List<String>>[
      [],
      ['--help'],
      ['-h'],
      ['--json'],
      ['--version'],
      ['--version', '--json'],
      ['--inventada'],
      ['--json', '--inventada'],
      ['--help', '--version'],
      ['-h', '--help'],
      ['--json=true'],
      ['a\nb'],
      ['--json', 'a\nb'],
      ['x' * 5000],
    ];

    for (final arguments in cases) {
      test('${jsonEncode(arguments).substring(0, 1)}… '
          '${arguments.length} argumento(s): una sola nueva línea final', () {
        final payload = evaluateCli(arguments, version: version).payload;
        expect(payload.endsWith('\n'), isTrue);
        expect(payload.endsWith('\n\n'), isFalse);
      });
    }

    for (final arguments in cases.where((a) => a.contains('--json'))) {
      test('${arguments.length} argumento(s) con --json: una línea JSON '
          'decodificable con exitCode coherente', () {
        final response = evaluateCli(arguments, version: version);
        expect(response.channel, CliOutputChannel.stdout);
        final lines = const LineSplitter().convert(response.payload);
        expect(lines, hasLength(1));
        final decoded = jsonDecode(lines.single) as Map<String, Object?>;
        expect(decoded['schemaVersion'], 1);
        expect(decoded['exitCode'], response.exitCode);
        expect(decoded.values, isNot(contains(null)));
      });
    }

    test('ninguna respuesta se identifica como sdlc', () {
      for (final arguments in cases) {
        final payload = evaluateCli(arguments, version: version).payload;
        expect(payload.toLowerCase(), isNot(contains('sdlc')));
        if (!payload.contains('"type":"error"')) {
          expect(payload, contains('shipflow'));
        }
      }
    });

    test('los únicos códigos son 0 y 64', () {
      for (final arguments in cases) {
        expect([
          0,
          64,
        ], contains(evaluateCli(arguments, version: version).exitCode));
      }
    });

    test('la misma entrada produce la misma respuesta', () {
      for (final arguments in cases) {
        final a = evaluateCli(arguments, version: version);
        final b = evaluateCli(List.of(arguments), version: version);
        expect(
          [a.exitCode, a.channel, a.payload],
          [b.exitCode, b.channel, b.payload],
        );
      }
    });
  });

  test('la evaluación no importa entrada y salida del SDK', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:cli/src/cli_application.dart'),
    );
    final source = File.fromUri(uri!).readAsStringSync();
    final imports = RegExp(
      r'''^import\s+'([^']+)';''',
      multiLine: true,
    ).allMatches(source).map((m) => m.group(1)).toSet();
    expect(imports, {'dart:convert', 'cli_response.dart'});
  });
}
