import 'package:test/test.dart';

import 'cli_support.dart';

void main() {
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
}
