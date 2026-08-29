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

Witness testigo({List<String> sujetos = const ['lib/algo.fuente']}) => Witness(
      invocation: 'verificador',
      subjects: sujetos,
      exitCode: 0,
      finishedAt: DateTime.utc(2026, 8, 29),
    );

void main() {
  test('sin testigo: no concluyente, aunque no haya diagnósticos', () {
    const r = VerificationOutcome(verifierId: 'V', diagnostics: []);
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
      criteria: const [
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
