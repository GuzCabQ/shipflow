/// Los tipos de la superficie de verificación, y sus invariantes.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Un control que solo declara: no ejecuta. La fábrica no lo invoca — recibe
/// el desenlace ya producido— así que `run` no hace falta para probarla.
class _ControlDeclarado implements Verifier {
  @override
  final String id;
  @override
  final Afirmacion afirmacion;

  _ControlDeclarado(this.id, this.afirmacion);

  @override
  Future<VerificationOutcome> run(VerificationScope alcance) =>
      throw UnsupportedError('este doble solo declara');
}

final _afirmacion = Afirmacion(
  id: 'ctrl.limpio',
  demuestra: 'que la herramienta no encontró nada',
  noDemuestra: 'comportamiento',
);

/// Un desenlace ejecutado **sin ningún diagnóstico**, que es la única forma de
/// que la fábrica afirme algo.
Executed _limpio(List<String> sujetos) => Executed(
  witness: Witness(
    invocation: 'herramienta --sobre ${sujetos.join(" ")}',
    subjects: sujetos,
    exitCode: 0,
    finishedAt: DateTime.utc(2026),
    omitted: const [],
  ),
  diagnostics: const [],
);

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

  group('la fábrica de afirmaciones cubiertas', () {
    test('un desenlace limpio produce la afirmación del control', () {
      final c = _ControlDeclarado('ctrl', _afirmacion);
      final a = AfirmacionCubierta.desde(
        control: c,
        desenlace: _limpio(['lib']),
        sujeto: 'lib',
      );
      expect(a, isNotNull);
      expect(a!.controlId, 'ctrl');
      expect(a.afirmacion.id, 'ctrl.limpio');
      expect(a.testigo.subjects, contains('lib'));
    });

    test('un desenlace ROJO no produce ninguna', () {
      // Es la regla central de §3, y no es prudencia: está medido que el
      // veredicto es global al paso y que los diagnósticos no tienen relación
      // validada con los sujetos del testigo. No se sabe cuál sujeto lo
      // originó, así que ninguno se puede declarar cubierto.
      final rojo = Executed(
        witness: _limpio(['lib']).witness,
        diagnostics: [
          Diagnostic(
            file: 'lib/a.fuente',
            severity: Severity.bloquea,
            ruleId: 'r',
            message: const QuotedText('algo', source: 'herramienta'),
          ),
        ],
      );
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', _afirmacion),
          desenlace: rojo,
          sujeto: 'lib',
        ),
        isNull,
      );
    });

    test('un desenlace con un diagnóstico QUE SOLO REPORTA tampoco', () {
      // El crítico de la revisión final: `verdict` solo mira los bloqueantes,
      // así que un paso con un diagnóstico informativo salía verde y sus
      // sujetos quedaban cubiertos. La regla del rojo se extiende: el
      // argumento que la sostiene —el veredicto es global al paso y los
      // diagnósticos no tienen relación validada con los sujetos del
      // testigo— no depende de la severidad. Con un informativo tampoco se
      // sabe cuál sujeto lo originó, y decirle al revisor que se saltee un
      // sujeto donde el arnés SÍ encontró algo es el fallo que esta
      // superficie existe para cerrar.
      final informativo = Executed(
        witness: _limpio(['lib']).witness,
        diagnostics: [
          Diagnostic(
            file: 'lib/a.fuente',
            severity: Severity.reporta,
            ruleId: 'r',
            message: const QuotedText('algo menor', source: 'herramienta'),
          ),
        ],
      );
      expect(informativo.verdict, Verdict.verde, reason: 'el veredicto NO ve');
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', _afirmacion),
          desenlace: informativo,
          sujeto: 'lib',
        ),
        isNull,
      );
    });

    test('un desenlace con un diagnóstico SILENCIADO tampoco', () {
      // La severidad más baja del enum, por el mismo argumento: el arnés
      // encontró algo y no se sabe sobre cuál sujeto.
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', _afirmacion),
          desenlace: Executed(
            witness: _limpio(['lib']).witness,
            diagnostics: [
              Diagnostic(
                file: 'lib/a.fuente',
                severity: Severity.silencia,
                ruleId: 'r',
                message: const QuotedText('telemetría', source: 'herramienta'),
              ),
            ],
          ),
          sujeto: 'lib',
        ),
        isNull,
      );
    });

    test('un sujeto que el testigo no cubre no produce ninguna', () {
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', _afirmacion),
          desenlace: _limpio(['lib']),
          sujeto: 'test',
        ),
        isNull,
      );
    });

    test('un desenlace que no es Executed no produce ninguna', () {
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', _afirmacion),
          desenlace: Aborted(
            attempt: Attempt(
              invocation: 'herramienta',
              subjects: const ['lib'],
              termination: Termination.tiempoAgotado,
              exitCode: -1,
              note: 'no llegó',
              finishedAt: DateTime.utc(2026),
            ),
          ),
          sujeto: 'lib',
        ),
        isNull,
      );
    });
  });

  group('el invariante de la superficie', () {
    // Este `throw` es el que reventaba en una corrida ordinaria —un sujeto no
    // observable mezclado con uno verde— y que un crítico obligó a arreglar
    // aguas arriba, en la derivación. Nunca se había ejercitado acá: el tipo
    // que lo declara no tenía prueba de que lo declarara.
    AfirmacionCubierta cubierta() => AfirmacionCubierta.desde(
      control: _ControlDeclarado('ctrl', _afirmacion),
      desenlace: _limpio(['lib']),
      sujeto: 'lib',
    )!;

    test('no verde, con cobertura y sin criterio: no se construye', () {
      for (final estado in [
        EstadoDeCorrida.rojo,
        EstadoDeCorrida.noConcluyente,
        EstadoDeCorrida.errorInterno,
      ]) {
        expect(
          () => SuperficieDeVerificacion(
            cubierto: [cubierta()],
            requiereCriterio: const [],
            estado: estado,
          ),
          throwsArgumentError,
          reason:
              'una corrida $estado que afirma cobertura sin nombrar lo que '
              'falta autoriza a saltear sin decir qué quedó sin verificar',
        );
      }
    });

    test('las tres combinaciones vecinas SÍ se construyen', () {
      // El invariante es una sola condición de tres términos: si cualquiera
      // de los tres no se cumple, no hay nada que prohibir. Sin esto, un
      // `throw` de más pasaría por invariante.
      expect(
        SuperficieDeVerificacion(
          cubierto: [cubierta()],
          requiereCriterio: const [],
          estado: EstadoDeCorrida.verde,
        ).cubierto,
        hasLength(1),
        reason: 'verde sin nada que mirar es exactamente lo que se espera',
      );
      expect(
        SuperficieDeVerificacion(
          cubierto: const [],
          requiereCriterio: const [],
          estado: EstadoDeCorrida.noConcluyente,
        ).requiereCriterio,
        isEmpty,
        reason: 'sin cobertura no autoriza a saltear nada',
      );
      expect(
        SuperficieDeVerificacion(
          cubierto: [cubierta()],
          requiereCriterio: [
            EntradaDeCriterio(
              motivo: MotivoDeCriterio.noSePudoMirar,
              detalle: 'bin no existe',
            ),
          ],
          estado: EstadoDeCorrida.noConcluyente,
        ).requiereCriterio,
        hasLength(1),
        reason: 'no verde con cobertura es legítimo si nombra lo que falta',
      );
    });

    test('las dos listas quedan inmodificables', () {
      final s = SuperficieDeVerificacion(
        cubierto: [cubierta()],
        requiereCriterio: const [],
        estado: EstadoDeCorrida.verde,
      );
      expect(() => s.cubierto.clear(), throwsUnsupportedError);
      expect(() => s.requiereCriterio.clear(), throwsUnsupportedError);
    });
  });

  group('una entrada de criterio', () {
    test('el detalle nunca va en blanco', () {
      expect(
        () => EntradaDeCriterio(
          motivo: MotivoDeCriterio.residuoGeneral,
          detalle: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('el motivo es un enum cerrado de DIEZ', () {
      // Ocho de §3, más los dos que la enmienda agregó con la rebanada del
      // entorno: hechos que la cascada no conoce y que igual vuelven no
      // concluyente la corrida.
      expect(MotivoDeCriterio.values, hasLength(10));
      expect(
        MotivoDeCriterio.values,
        contains(MotivoDeCriterio.entornoNoDerivado),
      );
      expect(
        MotivoDeCriterio.values,
        contains(MotivoDeCriterio.candidatoAlterado),
      );
    });
  });

  group('el artefacto de revisión', () {
    final superficie = SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: [
        EntradaDeCriterio(
          motivo: MotivoDeCriterio.residuoGeneral,
          detalle: 'algo quedó afuera',
        ),
      ],
      estado: EstadoDeCorrida.noConcluyente,
    );
    final candidato = CandidateIdentity(
      contentRevision: 'arbol',
      baseRevision: 'base',
    );

    ArtefactoDeRevision armar({
      String? plan,
      String? sinPlanPorque,
      String alcance = 'lo que se afirmó',
      String intent = 'por qué existe',
    }) => ArtefactoDeRevision(
      superficie: superficie,
      candidato: candidato,
      intent: intent,
      plan: plan,
      sinPlanPorque: sinPlanPorque,
      alcanceDeLoAfirmado: alcance,
    );

    test('la ausencia de plan se DECLARA, no se inventa', () {
      // Sin plan y sin motivo, el artefacto afirmaría por omisión que no hacía
      // falta ninguno. Y con los dos, diría dos cosas incompatibles.
      expect(() => armar(), throwsArgumentError);
      expect(
        () => armar(plan: 'el plan', sinPlanPorque: 'no hay'),
        throwsArgumentError,
      );
      expect(
        armar(sinPlanPorque: 'el modo solo-PR no tiene tareas').plan,
        isNull,
      );
      expect(armar(plan: 'el plan').sinPlanPorque, isNull);
    });

    test('un plan o un motivo presentes pero en blanco se rechazan igual que '
        'ausentes', () {
      // Un `sinPlanPorque: ''` afirma por omisión exactamente lo mismo que
      // su ausencia —que no hacía falta ningún motivo—, que es lo que este
      // invariante existe para impedir. Lo mismo para `plan`.
      expect(() => armar(plan: '  '), throwsArgumentError);
      expect(() => armar(sinPlanPorque: ''), throwsArgumentError);
    });

    test('el alcance de lo afirmado y la intención nunca van en blanco', () {
      expect(() => armar(plan: 'p', alcance: '  '), throwsArgumentError);
      expect(() => armar(plan: 'p', intent: ''), throwsArgumentError);
    });

    test(
      'el texto de alcance para el modo solo-PR nombra su límite medido',
      () {
        // La segunda frase no es adorno: es el límite de la materialización, y
        // sin ella el revisor lee «el objeto commiteado es el que se verificó»
        // como si valiera sin condiciones.
        expect(ArtefactoDeRevision.alcanceSoloPR, contains('revisión humana'));
        expect(ArtefactoDeRevision.alcanceSoloPR, contains('filtros'));
      },
    );

    test('no lleva la revisión: el artefacto existe ANTES del commit', () {
      final a = armar(plan: 'p');
      expect(a.toJson().containsKey('revision'), isFalse);
      expect(a.candidato.contentRevision, 'arbol');
    });
  });
}
