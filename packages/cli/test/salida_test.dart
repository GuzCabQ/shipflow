/// Los invariantes del protocolo de salida, sin pasar por ningún comando.
///
/// «Exactamente un resultado, y último» es una promesa que nadie comprobaba:
/// la primera versión solo impedía el segundo, y dejaba pasar cero resultados
/// y eventos posteriores.
library;

import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'apoyo.dart';

Impresora _impresora() =>
    Impresora(salida: StringBuffer(), error: StringBuffer(), json: true);

const _result = ResultEnvelope(
  command: 'verify',
  exitCode: 0,
  verdict: 'ok',
  data: {},
);

void main() {
  group('el protocolo con --json', () {
    test('todo es JSON Lines, y hay EXACTAMENTE un result, último', () async {
      final (_, salida) = await correr(
        const ['--json'],
        [Paso.rojo('A'), Paso.verde('B')],
      );
      final objetos = lineas(salida);
      expect(objetos.where((o) => o['type'] == 'result'), hasLength(1));
      expect(objetos.last['type'], 'result');
      expect(objetos.every((o) => o['schema'] == esquemaDeSalida), isTrue);
    });

    test('un error de uso TAMBIÉN sale como envelope', () async {
      // Imprimía texto humano y con `--json` eso rompe a cualquier consumidor:
      // la primera línea no es JSON y no hay resultado que leer.
      final (c, salida) = await correr(const [
        '--json',
        '--inventada',
      ], const []);
      expect(c, 5);
      final r = lineas(salida).single;
      expect(r['type'], 'result');
      expect(r['exitCode'], 5);
      expect(r['nextAction'], isNotNull);
      expect(
        r['verdict'],
        isNull,
        reason:
            'un error de uso no alcanzó el dominio: no tiene veredicto '
            'que dar, y la superficie no declara ninguno para el código 5',
      );
      expect(
        r['runId'],
        isNull,
        reason:
            'un error de uso no llegó a componer ninguna cascada, así '
            'que no hay ninguna corrida que identificar',
      );
    });

    test('el result lleva registrados Y ejecutados', () async {
      final (_, salida) = await correr(
        const ['--json'],
        [Paso.verde('A'), Paso('B', lanza: StateError('x'))],
      );
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      final registrados = (data['registered']! as List)
          .cast<Map<String, Object?>>()
          .map((e) => e['id'])
          .toList();
      expect(registrados, ['A', 'B']);
      expect(data['executed'], ['A']);
      final outcomes = data['outcomes']! as Map<String, Object?>;
      expect((outcomes['A']! as Map<String, Object?>)['kind'], 'executed');
      expect((outcomes['B']! as Map<String, Object?>)['kind'], 'broken');
    });

    test('cada paso registrado lleva su alcance esperado', () async {
      final (_, salida) = await correr(const ['--json'], [Paso.verde('A')]);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      final registrados = data['registered']! as List;
      expect(registrados.single, {
        'id': 'A',
        'expectedScope': ['.'],
      });
    });

    test('un resultado normal SÍ lleva runId', () async {
      final (_, salida) = await correr(const ['--json'], [Paso.verde('A')]);
      final r = lineas(salida).last;
      expect(r['runId'], isNotNull);
    });

    test('no se cuela texto suelto', () async {
      final (_, salida) = await correr(const ['--json'], [Paso.rojo('A')]);
      for (final l in salida.trim().split('\n')) {
        expect(() => jsonDecode(l), returnsNormally, reason: '«$l»');
      }
    });

    test('emitir un segundo resultado es un error, no una línea de más', () {
      final imp = _impresora();
      imp.resultado(_result, 'x');
      expect(() => imp.resultado(_result, 'x'), throwsA(isA<ProtocoloRoto>()));
    });

    test('CERO resultados también incumple el contrato', () {
      // «Uno solo» no dice nada sobre «al menos uno», y un comando que no
      // emite ninguno deja al consumidor esperando algo que no llega.
      expect(_impresora().cerrar, throwsA(isA<ProtocoloRoto>()));
    });

    test('un evento DESPUÉS del resultado también', () {
      final imp = _impresora();
      imp.resultado(_result, 'x');
      expect(
        () => imp.evento(
          EventEnvelope(command: 'verify', type: 'progress', data: const {}),
          'x',
        ),
        throwsA(isA<ProtocoloRoto>()),
      );
    });
  });

  group('el runId que genera el comando entra en el marcador de la forja', () {
    test('lo que produce `generarRunId` construye un borrador de PR', () {
      // **La atadura entre el generador y el invariante del dominio.** Desde
      // la ronda 6, `PullRequestDraft` rechaza un runId con `<!--`, `-->` o un
      // salto de línea: ese valor viaja adentro del comentario HTML del
      // marcador estable, que es además la clave de la búsqueda idempotente.
      // El invariante lo prueba `core`; lo que solo se puede probar acá —el
      // único paquete que ve el generador y el dominio a la vez— es que lo que
      // ESTE árbol produce lo cumple. Sin esto, endurecer la guarda rompería
      // toda corrida y ninguna suite lo notaría hasta ejecutar una.
      final artefacto = ArtefactoDeRevision(
        superficie: SuperficieDeVerificacion(
          cubierto: const [],
          requiereCriterio: const [],
          estado: EstadoDeCorrida.verde,
        ),
        candidato: CandidateIdentity(
          contentRevision: 'arbol-1',
          baseRevision: 'base-1',
        ),
        intent: 'atar el generador al invariante',
        plan: null,
        sinPlanPorque: 'no hay elementos de trabajo',
        alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
      );

      for (var i = 0; i < 3; i++) {
        final runId = generarRunId();
        expect(
          () => PullRequestDraft(
            runId: runId,
            branch: 'rama-1',
            base: 'main',
            artefacto: artefacto,
          ),
          returnsNormally,
          reason: 'el generador produjo «$runId», que el dominio rechaza',
        );
      }
    });
  });

  group('la última salida va por la corriente de error', () {
    test('si ni siquiera se puede emitir el resultado', () {
      // El contrato la reserva para «un fallo que impida incluso serializar el
      // resultado», y nadie escribía en ella: el rescate reintentaba sobre la
      // misma salida que acababa de fallar.
      final err = StringBuffer();
      Impresora(
        salida: StringBuffer(),
        error: err,
      ).ultimoRecurso('se rompió', 'hacé esto');
      expect(err.toString(), contains('se rompió'));
      expect(err.toString(), contains('→ hacé esto'));
    });
  });

  group('Codigo.deShip', () {
    test('la tabla de §12, fila por fila', () {
      final esperado = <int, ShipOutcome>{
        0: ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.previewOnly,
          verificacion: EstadoDeCorrida.verde,
        ),
        1: ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.secretDetected,
          verificacion: EstadoDeCorrida.verde,
        ),
        2: ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.verificationGate,
          verificacion: EstadoDeCorrida.noConcluyente,
        ),
        3: ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'a' * 40),
        6: ShipOutcome.publicacionIncompletaParaLaPrueba(
          remoto: PushUnknown(causa: CausaDePublicacion.red),
          verificacion: EstadoPublicable.verde,
        ),
        70: ShipOutcome.localInconsistenteParaLaPrueba(revision: 'b' * 40),
      };
      for (final fila in esperado.entries) {
        expect(Codigo.deShip(fila.value), fila.key, reason: fila.value.kind);
      }
    });

    test('confirmationMissing sale 0, y con un secreto sale 1', () {
      expect(
        Codigo.deShip(
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.confirmationMissing,
            verificacion: EstadoDeCorrida.verde,
          ),
        ),
        0,
      );
      expect(
        Codigo.deShip(
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.secretDetected,
            verificacion: EstadoDeCorrida.verde,
          ),
        ),
        1,
      );
    });

    test('la compuerta lleva el código del estado que la cerró', () {
      for (final par in {
        EstadoDeCorrida.rojo: 1,
        EstadoDeCorrida.noConcluyente: 2,
        EstadoDeCorrida.errorInterno: 70,
      }.entries) {
        expect(
          Codigo.deShip(
            ShipOutcome.noIntentadoParaLaPrueba(
              causa: CausaDeNoIntento.verificationGate,
              verificacion: par.key,
            ),
          ),
          par.value,
          reason: par.key.name,
        );
      }
    });

    test('Publicado lleva el código de su verificación', () {
      for (final par in {
        EstadoPublicable.verde: 0,
        EstadoPublicable.rojo: 1,
        EstadoPublicable.noConcluyente: 2,
      }.entries) {
        expect(
          Codigo.deShip(
            ShipOutcome.publicadoParaLaPrueba(
              pr: PullRequestOpen(url: 'https://forja/pr/1'),
              verificacion: par.key,
            ),
          ),
          par.value,
          reason: par.key.name,
        );
      }
    });

    test('la entrega incompleta sale 6 AUNQUE la verificación sea roja', () {
      // Deliberado: `1` dice «el cambio no verificó» y `6` dice «el efecto
      // remoto no se completó», y la segunda es la que decide qué hacer
      // después. El precio está declarado: el estado viaja en `verdict` y en
      // `data`, no en el código.
      expect(
        Codigo.deShip(
          ShipOutcome.publicacionIncompletaParaLaPrueba(
            remoto: PullRequestUnknown(causa: CausaDePublicacion.red),
            verificacion: EstadoPublicable.rojo,
          ),
        ),
        6,
      );
    });
  });
}
