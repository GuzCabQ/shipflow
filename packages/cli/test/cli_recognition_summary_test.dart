import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'human_expectations.dart';
import 'recognition_reports.dart';

void main() {
  group('cortes del resumen', () {
    test('20 paquetes se listan y el 21 se cuenta', () {
      expect(human(wide(units: 20)), isNot(contains('adicional')));
      final payload = human(wide(units: 21));
      expect(payload, contains('Paquetes observados: 21\n'));
      expect(payload, contains('  p19 · packages/p19\n'));
      expect(payload, isNot(contains('p20 ·')));
      expect(
        payload,
        contains('  Hay 1 paquete adicional; consulta la salida JSON.\n'),
      );
    });

    List<RecognitionConflict> conflicts(int n) => [
      for (var i = 0; i < n; i++)
        RecognitionConflict(
          code: 'c${i.toString().padLeft(2, '0')}',
          message: 'conflicto $i',
          evidenceIds: const ['e0000'],
        ),
    ];

    test('10 conflictos se listan enteros', () {
      final payload = human(wide(conflicts: conflicts(10)));
      for (var i = 0; i < 10; i++) {
        expect(payload, contains('  - conflicto $i · fuentes:'));
      }
      expect(payload, isNot(contains('Hay ')));
    });

    test('el conflicto 11 se cuenta, no se lista', () {
      final payload = human(wide(conflicts: conflicts(11)));
      expect(payload, contains('  - conflicto 9 · fuentes:'));
      expect(payload, isNot(contains('conflicto 10 ')));
      expect(
        payload,
        contains('  Hay 1 conflicto adicional; consulta la salida JSON.\n'),
      );
      expect(
        human(wide(conflicts: conflicts(12))),
        contains('  Hay 2 conflictos adicionales; consulta la salida JSON.\n'),
      );
    });

    test('un bloqueo después de las diez filas sigue anunciado', () {
      final payload = human(
        wide(
          units: 1,
          limitations: [
            for (var i = 0; i < 10; i++)
              limitation('a${i.toString().padLeft(2, '0')}', blocking: false),
            limitation('z_bloquea'),
          ],
        ),
      );
      expect(payload, isNot(contains('mensaje z_bloquea')));
      expect(
        payload,
        contains('  Hay 1 limitación adicional; consulta la salida JSON.\n'),
      );
      expect(payload, contains(expectedBlocked));
    });
  });

  test('cada valor dinámico ocupa una línea segura de 240 runes', () {
    final payload = human(report(unitName: 'a\nb\u202Ec\x1b[2J${'x' * 300}'));
    expect(payload, contains(r'a\nb\u{202e}c\x1b[2J'));
    expect(payload, isNot(contains('\u202E')));
    expect(payload, isNot(contains('\x1b')));
    final name = report(unitName: 'x' * 300);
    final line = human(name).split('\n').firstWhere((l) => l.contains('x'));
    expect(line, '  ${'x' * 240}… · packages/b');
  });

  test('ninguna variante afirma persistencia, salud ni IDs internos', () {
    for (final payload in [
      human(report()),
      human(wide(units: 3, limitations: [limitation('x')])),
    ]) {
      for (final claim in [
        'se guardó',
        'guardado',
        'sano',
        'saludable',
        'se instaló',
        'doctor',
        'e0001',
        'u0001',
        'sha256',
        'plugin',
      ]) {
        expect(payload, isNot(contains(claim)), reason: claim);
      }
    }
  });

  test('el formato no cambia el estado ni lo que guarda el JSON', () {
    final source = wide(units: 25);
    final json = presentRecognition(source, json: true);
    final text = presentRecognition(source, json: false);
    expect(text.exitCode, json.exitCode);
    expect(json.payload, contains('"name":"p24"'));
  });
}
