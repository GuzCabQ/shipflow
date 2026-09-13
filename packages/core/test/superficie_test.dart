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
}
