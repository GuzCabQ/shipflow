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
}) =>
    Witness(
      invocation: invocacion,
      subjects: sujetos,
      exitCode: exitCode,
      termination: termination,
      finishedAt: DateTime.utc(2026, 8, 29),
    );

void main() {
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
