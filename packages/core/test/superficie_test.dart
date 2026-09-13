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
    final afirmacion = Afirmacion(
      id: 'ctrl.limpio',
      demuestra: 'que la herramienta no encontró nada',
      noDemuestra: 'comportamiento',
    );

    Executed limpio(List<String> sujetos) => Executed(
      witness: Witness(
        invocation: 'herramienta --sobre ${sujetos.join(" ")}',
        subjects: sujetos,
        exitCode: 0,
        finishedAt: DateTime.utc(2026),
        omitted: const [],
      ),
      diagnostics: const [],
    );

    test('un desenlace limpio produce la afirmación del control', () {
      final c = _ControlDeclarado('ctrl', afirmacion);
      final a = AfirmacionCubierta.desde(
        control: c,
        desenlace: limpio(['lib']),
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
        witness: limpio(['lib']).witness,
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
          control: _ControlDeclarado('ctrl', afirmacion),
          desenlace: rojo,
          sujeto: 'lib',
        ),
        isNull,
      );
    });

    test('un sujeto que el testigo no cubre no produce ninguna', () {
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', afirmacion),
          desenlace: limpio(['lib']),
          sujeto: 'test',
        ),
        isNull,
      );
    });

    test('un desenlace que no es Executed no produce ninguna', () {
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', afirmacion),
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
}
