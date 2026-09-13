/// Los tipos de la superficie de verificación, y sus invariantes.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('EstadoDeCorrida vive en core', () {
    // Se muda porque cruza un puerto: el artefacto de revisión lo lleva, y un
    // puerto de `core` no puede nombrar un tipo de `orchestration`.
    expect(EstadoDeCorrida.values, hasLength(4));
    expect(EstadoDeCorrida.verde.name, 'verde');
    expect(EstadoDeCorrida.values, contains(EstadoDeCorrida.errorInterno));
  });

  group('una afirmación declara su límite', () {
    test('los tres campos son obligatorios y ninguno va en blanco', () {
      expect(
        () => Afirmacion(id: ' ', demuestra: 'x', noDemuestra: 'y'),
        throwsArgumentError,
      );
      expect(
        () => Afirmacion(id: 'a', demuestra: '  ', noDemuestra: 'y'),
        throwsArgumentError,
      );
      expect(
        () => Afirmacion(id: 'a', demuestra: 'x', noDemuestra: ''),
        throwsArgumentError,
        reason:
            'una afirmación sin límite es una prohibición sin alternativa: '
            'le dice al revisor que se saltee algo sin decirle qué queda sin '
            'mirar',
      );
    });

    test('una afirmación completa se construye', () {
      final a = Afirmacion(
        id: 'formato.conforme',
        demuestra: 'coincide con la salida del formateador',
        noDemuestra: 'comportamiento, lógica ni criterios',
      );
      expect(a.id, 'formato.conforme');
    });
  });
}
