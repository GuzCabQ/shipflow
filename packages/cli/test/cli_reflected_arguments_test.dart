import 'dart:convert';

import 'package:test/test.dart';

import 'cli_support.dart';
import 'static_evaluation.dart';

void main() {
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
        final response = evaluate([raw], version: version);
        expect(response.payload, humanError("argumento inesperado: '$shown'"));
        expect('\n'.allMatches(response.payload).length, 2);
      });
    }
  });

  group('truncamiento', () {
    String reflected(String argument) {
      final firstLine = evaluate([
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
      final payload = evaluate(['x' * (1 << 20)], version: version).payload;
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
}
