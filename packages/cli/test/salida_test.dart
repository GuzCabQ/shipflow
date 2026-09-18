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

/// Las cinco variantes de [ShipOutcome]: las causas y los estados completos,
/// los cuerpos remotos por muestra.
///
/// `Codigo.deShip` y `accionDe` son funciones totales sobre el tipo cerrado, y
/// las dos pruebas que las cubren afirman propiedades sobre el dominio ENTERO
/// —«seis códigos», «ningún código distinto de cero se queda mudo»—. Con una
/// muestra elegida a mano, una variante nueva se quedaría fuera de la lista y
/// las dos afirmaciones seguirían en verde cubriendo menos de lo que dicen.
/// Por eso las causas y los estados salen de `values` y no de una lista.
///
/// **Los cuerpos remotos NO están completos, y no hace falta que lo estén**:
/// hay dos de los cinco [PublicacionNoUtilizable] y un solo valor de
/// [CausaDePublicacion]. Ni el código ni la acción de un [ShipOutcome] miran
/// adentro del desenlace remoto —lo que miran es de qué lado del corte
/// utilizable/no utilizable cae—, así que agregar los otros tres cuerpos
/// repetiría filas sin ejercitar una rama más. Los dos
/// [PublicacionUtilizable] sí están los dos, porque son dos.
List<ShipOutcome> todosLosDesenlaces() => [
  for (final causa in CausaDeNoIntento.values)
    for (final estado in EstadoDeCorrida.values)
      ShipOutcome.noIntentadoParaLaPrueba(causa: causa, verificacion: estado),
  ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'a' * 40),
  ShipOutcome.localInconsistenteParaLaPrueba(revision: 'b' * 40),
  for (final publicable in EstadoPublicable.values) ...[
    ShipOutcome.publicadoParaLaPrueba(
      pr: PullRequestOpen(url: 'https://forja/pr/1'),
      verificacion: publicable,
    ),
    ShipOutcome.publicadoParaLaPrueba(
      pr: PullRequestMerged(url: 'https://forja/pr/2'),
      verificacion: publicable,
    ),
    ShipOutcome.publicacionIncompletaParaLaPrueba(
      remoto: PushUnknown(causa: CausaDePublicacion.red),
      verificacion: publicable,
    ),
    ShipOutcome.publicacionIncompletaParaLaPrueba(
      remoto: PullRequestClosed(url: 'https://forja/pr/3'),
      verificacion: publicable,
    ),
  ],
];

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

    test('deShip produce SEIS códigos, y son los que la superficie nombra', () {
      // El doc comment de `ResultEnvelope.verdict` los enumera. Enumerar
      // vence: esta prueba ata la cifra al `switch` real, así que una
      // variante nueva con un código nuevo la pone roja y obliga a tocar la
      // oración en vez de dejarla envejecer en silencio.
      expect(
        {for (final d in todosLosDesenlaces()) Codigo.deShip(d)},
        {0, 1, 2, 3, 6, 70},
      );
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

  group('accionDe', () {
    // Esta función pública —nueve ramas y siete mensajes cuando se la
    // encontró— no la referenciaba nada en el árbol, y el README afirmaba que
    // su propia suite la ejercitaba. Reemplazar el cuerpo entero por
    // `=> null` dejaba las 1061 pruebas en verde.

    test('el switch cubre las CINCO variantes, y ninguna lanza', () {
      final desenlaces = todosLosDesenlaces();
      expect(
        {for (final d in desenlaces) d.runtimeType},
        hasLength(5),
        reason:
            'si nace una sexta variante y la lista no crece, las propiedades '
            'de abajo vuelven a prometer «todo desenlace» cubriendo menos',
      );
      for (final d in desenlaces) {
        expect(() => accionDe(d), returnsNormally, reason: d.kind);
      }
    });

    test('ningún código distinto de 0 se queda sin acción siguiente', () {
      // Es la promesa de `ResultEnvelope.nextAction`: toda salida que no sea
      // verde tiene que poder decir qué hacer. Antes no valía —un `Publicado`
      // con la verificación en rojo salía `1` con `nextAction` nulo— y el doc
      // comment la afirmaba igual.
      for (final d in todosLosDesenlaces()) {
        if (Codigo.deShip(d) == Codigo.exito) continue;
        expect(
          accionDe(d),
          isNotNull,
          reason: '${d.kind} sale ${Codigo.deShip(d)} y no dice qué hacer',
        );
        expect(accionDe(d), isNotEmpty, reason: d.kind);
      }
    });

    test('los únicos desenlaces sin acción son la previsualización y el '
        'publicado verde', () {
      // El control por el otro lado: sin esto, una `accionDe` que devolviera
      // un mensaje para TODA variante pasaría la prueba de arriba.
      final mudos = [
        for (final d in todosLosDesenlaces())
          if (accionDe(d) == null) d,
      ];
      expect(mudos, isNotEmpty);
      for (final d in mudos) {
        expect(
          switch (d) {
            NoIntentado(causa: CausaDeNoIntento.previewOnly) => true,
            Publicado(verificacion: EstadoPublicable.verde) => true,
            _ => false,
          },
          isTrue,
          reason: '${d.kind} se quedó mudo y no es uno de los dos que pueden',
        );
      }
    });

    test('NoAplicado y LocalInconsistente NO dicen lo mismo, y el cruce '
        'sería una instrucción prohibida', () {
      // Intercambiar los dos mensajes compila —los dos llevan un `String`
      // interpolado— y le diría a quien perdió el CAS que repare el índice y
      // corra `--retry-publication`, que es justo lo que su mensaje correcto
      // prohíbe: no hay entrega que recuperar.
      final perdioElCas = accionDe(
        ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'c' * 40),
      )!;
      expect(perdioElCas, contains('c' * 40));
      expect(perdioElCas, contains('Volvé a correr ship'));
      expect(
        perdioElCas,
        contains('No sirve --retry-publication'),
        reason: 'mandarlo a reintentar la publicación no tiene qué recuperar',
      );
      expect(perdioElCas, isNot(contains('índice')));

      final indiceSucio = accionDe(
        ShipOutcome.localInconsistenteParaLaPrueba(revision: 'd' * 40),
      )!;
      expect(indiceSucio, contains('d' * 40));
      expect(indiceSucio, contains('índice'));
      expect(indiceSucio, contains('--retry-publication'));
      expect(
        indiceSucio,
        isNot(contains('No sirve')),
        reason: 'acá el reintento SÍ es el camino, después de reparar',
      );
    });

    test('la compuerta distingue el arnés roto del cambio que no verificó', () {
      // Los dos salen por `verificationGate`, y la diferencia importa:
      // `--allow-incomplete` autoriza uno y no autoriza el otro. Con los dos
      // mensajes intercambiados, a quien se le rompió el arnés se le ofrece
      // una bandera que no lo autoriza.
      final arnesRoto = accionDe(
        ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.verificationGate,
          verificacion: EstadoDeCorrida.errorInterno,
        ),
      )!;
      expect(arnesRoto, contains('arnés'));
      expect(arnesRoto, contains('--allow-incomplete no autoriza esto'));

      for (final estado in [
        EstadoDeCorrida.rojo,
        EstadoDeCorrida.noConcluyente,
      ]) {
        final verificoMal = accionDe(
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.verificationGate,
            verificacion: estado,
          ),
        )!;
        expect(verificoMal, isNot(contains('arnés')), reason: estado.name);
        expect(
          verificoMal,
          contains('--allow-incomplete'),
          reason: '${estado.name}: la bandera SÍ autoriza este caso',
        );
        expect(
          verificoMal,
          isNot(contains('no autoriza esto')),
          reason: estado.name,
        );
      }
    });

    test('la confirmación que falta y el secreto no comparten mensaje', () {
      expect(
        accionDe(
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.confirmationMissing,
            verificacion: EstadoDeCorrida.verde,
          ),
        ),
        contains('--yes'),
      );
      final secreto = accionDe(
        ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.secretDetected,
          verificacion: EstadoDeCorrida.verde,
        ),
      )!;
      expect(secreto, contains('secreto'));
      expect(
        secreto,
        isNot(contains('--yes')),
        reason: 'confirmar no saca el secreto del cambio',
      );
    });

    test('un publicado que NO es verde dice qué hacer, y no manda a '
        'reintentar la publicación', () {
      // `Codigo.deShip(Publicado(rojo))` da 1 y `accionDe` daba nulo: un
      // código distinto de cero sin acción siguiente, contra lo que
      // `ResultEnvelope.nextAction` promete. El desenlace es alcanzable con
      // `--allow-incomplete`.
      for (final estado in [
        EstadoPublicable.rojo,
        EstadoPublicable.noConcluyente,
      ]) {
        final accion = accionDe(
          ShipOutcome.publicadoParaLaPrueba(
            pr: PullRequestOpen(url: 'https://forja/pr/7'),
            verificacion: estado,
          ),
        )!;
        expect(accion, contains('https://forja/pr/7'), reason: estado.name);
        expect(accion, contains(estado.name), reason: estado.name);
        expect(
          accion,
          contains('No sirve --retry-publication'),
          reason: 'la publicación se completó: no hay nada que reintentar',
        );
      }
      expect(
        accionDe(
          ShipOutcome.publicadoParaLaPrueba(
            pr: PullRequestOpen(url: 'https://forja/pr/7'),
            verificacion: EstadoPublicable.verde,
          ),
        ),
        isNull,
        reason: 'el verde publicado no tiene nada pendiente',
      );
    });

    test('la publicación incompleta manda al reintento, y dice que no '
        'duplica', () {
      final accion = accionDe(
        ShipOutcome.publicacionIncompletaParaLaPrueba(
          remoto: PushUnknown(causa: CausaDePublicacion.red),
          verificacion: EstadoPublicable.verde,
        ),
      )!;
      expect(accion, contains('--retry-publication'));
      expect(
        accion,
        contains('No se creará otro commit ni un segundo pull request'),
        reason:
            'sin esa promesa, el reintento se lee como «volvé a correr todo»',
      );
    });
  });
}
