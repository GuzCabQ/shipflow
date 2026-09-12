/// El desenlace de aplicar un candidato: **lo que no se puede construir**.
///
/// Cada prueba de acá corresponde a un estado que se llegó a producir. La
/// revisión en blanco no es una posibilidad teórica: el adapter la devolvía
/// cuando el usuario cambiaba de rama entre preparar y aplicar, y el tipo la
/// aceptaba sin decir nada. Un desenlace que puede representar «no se aplicó
/// esto» sin decir qué es exactamente la clase de dato que este proyecto
/// persigue.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  const base = 'base0000000000000000000000000000000000000';
  const otra = 'otra0000000000000000000000000000000000000';
  const rev = 'rev00000000000000000000000000000000000000';

  group('Committed', () {
    test('sin revisión no se construye', () {
      expect(() => Committed('  '), throwsA(isA<ArgumentError>()));
    });
  });

  group('NotApplied', () {
    NotApplied porBase({String revision = rev}) => NotApplied(
        revision: revision,
        causa: CausaDeNoAplicacion.baseMovida,
        baseEsperada: base,
        headObservado: otra);

    test('se construye con las dos revisiones y la causa', () {
      final d = porBase();
      expect(d.revision, rev);
      expect(d.ramaObservada, isNull);
    });

    test('**sin revisión no se construye**', () {
      // El caso que de verdad pasó.
      expect(() => porBase(revision: ''), throwsA(isA<ArgumentError>()));
    });

    test('sin base o sin HEAD observado no se construye', () {
      expect(
          () => NotApplied(
              revision: rev,
              causa: CausaDeNoAplicacion.baseMovida,
              baseEsperada: '',
              headObservado: otra),
          throwsA(isA<ArgumentError>()));
      expect(
          () => NotApplied(
              revision: rev,
              causa: CausaDeNoAplicacion.baseMovida,
              baseEsperada: base,
              headObservado: '  '),
          throwsA(isA<ArgumentError>()));
    });

    test('la rama observada acompaña a `ramaCambiada`, y solo a ella', () {
      // Las dos direcciones. Antes esto era un solo campo que unas veces traía
      // una revisión y otras una frase sobre la rama, así que quien lo leía
      // tenía que adivinar cuál de las dos le había tocado.
      expect(
          () => NotApplied(
              revision: rev,
              causa: CausaDeNoAplicacion.baseMovida,
              baseEsperada: base,
              headObservado: otra,
              ramaObservada: 'main'),
          throwsA(isA<ArgumentError>()),
          reason: 'la base movida no habla de ninguna rama observada');
      expect(
          () => NotApplied(
              revision: rev,
              causa: CausaDeNoAplicacion.ramaCambiada,
              baseEsperada: base,
              headObservado: otra),
          throwsA(isA<ArgumentError>()),
          reason: 'y decir que la rama cambió sin decir a cuál no informa');
      expect(
          NotApplied(
                  revision: rev,
                  causa: CausaDeNoAplicacion.ramaCambiada,
                  baseEsperada: base,
                  headObservado: otra,
                  ramaObservada: '')
              .ramaObservada,
          '',
          reason: 'vacía SÍ vale: es HEAD suelto, que es un estado y no un '
              'campo que falta');
    });
  });

  group('LocalInconsistent', () {
    test('sin revisión no se construye: el commit existe y hay que repararlo',
        () {
      expect(() => LocalInconsistent(revision: '', detalle: 'x'),
          throwsA(isA<ArgumentError>()));
    });

    test('sin detalle no se construye: no diría qué reparar', () {
      expect(() => LocalInconsistent(revision: rev, detalle: ' '),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('RutaNoMaterializada', () {
    test('sin detalle no se construye', () {
      expect(
          () => RutaNoMaterializada(
              ruta: 'x',
              motivo: MotivoDeNoMaterializacion.referenciaAOtroRepositorio,
              detalle: ''),
          throwsA(isA<ArgumentError>()));
    });

    test('el motivo es del dominio, no el modo de git', () {
      // `CandidateIdentity` declara opaca la representación del sistema de
      // versiones. Que esta clase expusiera `120000` la contradecía.
      expect(MotivoDeNoMaterializacion.values, hasLength(2));
    });
  });

  group('CandidateIdentity', () {
    test('en blanco no identifica nada', () {
      expect(() => CandidateIdentity(contentRevision: '', baseRevision: base),
          throwsA(isA<ArgumentError>()));
    });
  });
}
