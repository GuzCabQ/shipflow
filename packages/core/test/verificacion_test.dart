/// INV-2: un paso sin testigo NO es verde. Es no concluyente, y se trata como
/// rojo (`D-001`, `D-003`).
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

Diagnostic diag(Severity s) => Diagnostic(
      file: 'lib/algo.fuente',
      severity: s,
      ruleId: 'R-1',
      message: const QuotedText('m', source: 'herramienta'),
    );

Witness testigo({
  List<String> sujetos = const ['lib/algo.fuente'],
  String invocacion = 'verificador',
  int exitCode = 0,
  Termination termination = Termination.completa,
  List<String> omitido = const [],
}) =>
    Witness(
      invocation: invocacion,
      subjects: sujetos,
      omitted: omitido,
      exitCode: exitCode,
      termination: termination,
      finishedAt: DateTime.utc(2026, 8, 29),
    );

void main() {
  test('declarar una omisión NO invalida el testigo', () {
    // Un paso que cubrió parte del alcance y lo dice atestigua. Uno que cubrió
    // todo y no lo dice no es mejor: por eso `omitted` no entra en `attests`.
    expect(testigo(omitido: const ['lib/otro: no existe']).attests, isTrue);
  });

  test('un motivo en blanco no es un motivo', () {
    // Mismo criterio que las evasiones de `Rule`: una cadena vacía ocupa lugar
    // en la lista y no dice qué quedó afuera.
    expect(() => testigo(omitido: const ['  ']), throwsArgumentError);
  });

  test('un conteo negativo de lo propio no significa nada', () {
    // `null` ya significa «no lo puedo contar». Un negativo no significa nada,
    // y dejarlo entrar daría un tercer valor sin lectura para quien clasifica.
    expect(
        () => Witness(
              invocation: 'x',
              subjects: const ['a'],
              omitted: const [],
              termination: Termination.completa,
              exitCode: 0,
              ownSubjects: -1,
              finishedAt: DateTime.utc(2026),
            ),
        throwsArgumentError);
  });

  test('cuántos eran suyos NO cambia si el testigo atestigua', () {
    // Deliberado: distinguir «no había nada mío» de «no pude mirar» es de
    // quien compone la corrida, no del testigo. ADR-011 corolario 4 — ningún
    // verificador juzga su propia cobertura. Acá solo declara el número.
    final conCero = Witness(
      invocation: 'herramienta',
      subjects: const ['lib/a.fuente'],
      omitted: const [],
      termination: Termination.completa,
      exitCode: 0,
      ownSubjects: 0,
      finishedAt: DateTime.utc(2026),
    );
    expect(conCero.attests, isTrue);
  });

  test('un paso no puede haber invocado Y no haber tenido nada que hacer', () {
    // Declarar las dos cosas deja a quien lea el resultado eligiendo cuál
    // creer, que es peor que no declarar ninguna.
    expect(
        () => VerificationOutcome(
              verifierId: 'V',
              diagnostics: const [],
              witness: testigo(),
              notApplicable: NotApplicable(
                subjects: const ['lib/'],
                reasons: const ['no había nada mío'],
                decidedAt: DateTime.utc(2026),
              ),
            ),
        throwsArgumentError);
  });

  test('un «no tenía nada que hacer» SIN motivo no se puede construir', () {
    // ADR-011 corolario 1: el salto nunca es silencioso. La promesa estaba en
    // la prosa del tipo y el constructor la dejaba romper.
    expect(
        () => NotApplicable(
              subjects: const ['lib/'],
              reasons: const ['  '],
              decidedAt: DateTime.utc(2026),
            ),
        throwsArgumentError);
  });

  test('un motivo en blanco entre motivos válidos tampoco se acepta', () {
    // `Witness.omitted` rechaza cualquier blanco; esto aceptaba la lista si
    // al menos un motivo era válido. Dos reglas para el mismo hecho.
    expect(
        () => NotApplicable(
              subjects: const ['lib/'],
              reasons: const ['no es de este stack', '   '],
              decidedAt: DateTime.utc(2026),
            ),
        throwsArgumentError);
  });

  test('una lista de motivos vacía sigue sin aceptarse', () {
    // El control negativo del arreglo: `any` sobre una lista vacía es falso,
    // así que cambiar `every` por `any` sin esto abre el agujero que el
    // cambio venía a cerrar.
    expect(
        () => NotApplicable(
              subjects: const ['lib/'],
              reasons: const [],
              decidedAt: DateTime.utc(2026),
            ),
        throwsArgumentError);
  });

  test('sin testigo: no concluyente, aunque no haya diagnósticos', () {
    final r = VerificationOutcome(verifierId: 'V', diagnostics: []);
    expect(r.verdict, equals(Verdict.noConcluyente));
  });

  test('con testigo que no atestigua sobre nada: no concluyente', () {
    // Es el corolario 5 de ADR-011: un testigo sin sujetos no distingue
    // «no encontré nada» de «no miré ahí».
    final r = VerificationOutcome(
        verifierId: 'V', diagnostics: [], witness: testigo(sujetos: []));
    expect(r.verdict, equals(Verdict.noConcluyente));
  });

  test('con testigo y sin diagnósticos bloqueantes: verde', () {
    final r = VerificationOutcome(
        verifierId: 'V',
        diagnostics: [diag(Severity.reporta)],
        witness: testigo());
    expect(r.verdict, equals(Verdict.verde));
  });

  test('con testigo y un diagnóstico bloqueante: rojo', () {
    final r = VerificationOutcome(
        verifierId: 'V',
        diagnostics: [diag(Severity.bloquea)],
        witness: testigo());
    expect(r.verdict, equals(Verdict.rojo));
  });

  group('ADR-011 · no poder ejecutarse nunca es verde', () {
    // El agujero que tenía este tipo: `attests` miraba solo si había sujetos,
    // así que una herramienta ausente producía VERDE mientras alguien hubiera
    // escrito sobre qué iba a correr.
    for (final t in [
      Termination.herramientaAusente,
      Termination.tiempoAgotado,
      Termination.interrumpida,
    ]) {
      test('$t → no concluyente', () {
        final r = VerificationOutcome(
            verifierId: 'V', diagnostics: [], witness: testigo(termination: t));
        expect(r.verdict, equals(Verdict.noConcluyente));
      });
    }

    test('sin invocación: no concluyente, aunque haya sujetos', () {
      final r = VerificationOutcome(
          verifierId: 'V',
          diagnostics: [],
          witness: testigo(invocacion: '   '));
      expect(r.verdict, equals(Verdict.noConcluyente));
    });

    test('un código de salida distinto de cero NO es «no se ejecutó»', () {
      // Muchas herramientas salen con 1 cuando encuentran algo: eso significa
      // que CORRIERON. Interpretar el código como fallo de ejecución sería el
      // error simétrico, y perdería la distinción que este tipo existe para
      // sostener. El resultado lo dan los diagnósticos, no el código.
      final r = VerificationOutcome(
          verifierId: 'V', diagnostics: [], witness: testigo(exitCode: 1));
      expect(r.verdict, equals(Verdict.verde));
    });
  });

  group('los invariantes son del tipo, no del momento de construirlo', () {
    test('vaciar la lista original no cambia el veredicto', () {
      final sujetos = ['lib/algo.fuente'];
      final r = VerificationOutcome(
          verifierId: 'V', diagnostics: [], witness: testigo(sujetos: sujetos));
      expect(r.verdict, equals(Verdict.verde));
      sujetos.clear();
      expect(r.verdict, equals(Verdict.verde),
          reason: 'el testigo copió sus sujetos; mutar el original no lo toca');
    });

    test('la lista de diagnósticos no se puede ampliar desde afuera', () {
      final diags = <Diagnostic>[];
      final r = VerificationOutcome(
          verifierId: 'V', diagnostics: diags, witness: testigo());
      diags.add(diag(Severity.bloquea));
      expect(r.verdict, equals(Verdict.verde));
      expect(() => r.diagnostics.add(diag(Severity.bloquea)),
          throwsUnsupportedError);
    });

    test('los criterios de un WorkItem no se pueden vaciar desde afuera', () {
      final criterios = [
        AcceptanceCriterion(
            id: 'A',
            statement: QuotedText('c', source: 'f'),
            assertionForm: 'forma'),
      ];
      final w = WorkItem(
        id: 'W',
        title: QuotedText('t', source: 'f'),
        description: QuotedText('d', source: 'f'),
        criteria: criterios,
      );
      expect(w.allCriteriaMapped, isTrue);
      criterios.clear();
      expect(w.allCriteriaMapped, isTrue);
    });
  });

  test('INV-1 · una forma de aserción vacía no es una forma', () {
    expect(
      () => AcceptanceCriterion(
          id: 'A',
          statement: QuotedText('c', source: 'f'),
          assertionForm: '  '),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('el veredicto no es un campo: no hay forma de fijarlo en verde', () {
    // Si esto dejara de compilar porque alguien agregó un `verdict` asignable,
    // el invariante se perdió. La prueba es que el resultado se DERIVA.
    final r = VerificationOutcome(
        verifierId: 'V',
        diagnostics: [diag(Severity.bloquea)],
        witness: testigo());
    expect(r.toJson().containsKey('verdict'), isFalse);
  });

  test('un Finding no tiene dónde escribir una severidad', () {
    final f = Finding(
      sensorId: 'S',
      criterionId: 'C',
      file: 'lib/algo.fuente',
      note: const QuotedText('n', source: 'sensor'),
    );
    expect(f.toJson().containsKey('severity'), isFalse);
  });

  test('INV-1 · un WorkItem con un criterio sin forma no está mapeado', () {
    final sinForma = WorkItem(
      id: 'W',
      title: const QuotedText('t', source: 'f'),
      description: const QuotedText('d', source: 'f'),
      criteria: [
        AcceptanceCriterion(id: 'A', statement: QuotedText('c', source: 'f')),
      ],
    );
    expect(sinForma.allCriteriaMapped, isFalse);
  });

  test('INV-1 · un WorkItem sin criterios tampoco está mapeado', () {
    final sinCriterios = WorkItem(
      id: 'W',
      title: const QuotedText('t', source: 'f'),
      description: const QuotedText('d', source: 'f'),
      criteria: const [],
    );
    expect(sinCriterios.allCriteriaMapped, isFalse);
  });
}
