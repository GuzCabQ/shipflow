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
  List<String> sujetos = const ['lib/a.fuente'],
  String invocacion = 'herramienta --sobre lib',
  int exitCode = 0,
  List<Omission> omitido = const [],
}) =>
    Witness(
      invocation: invocacion,
      subjects: sujetos,
      omitted: omitido,
      exitCode: exitCode,
      finishedAt: DateTime.utc(2026),
    );

void main() {
  group('el veredicto de un paso ejecutado se deriva', () {
    test('con cobertura y sin bloqueantes: verde', () {
      expect(Executed(witness: testigo(), diagnostics: []).verdict, Verdict.verde);
    });

    test('con cobertura y un bloqueante: rojo', () {
      expect(
          Executed(witness: testigo(), diagnostics: [diag(Severity.bloquea)])
              .verdict,
          Verdict.rojo);
    });

    test('lo informativo no lo pone rojo', () {
      expect(
          Executed(witness: testigo(), diagnostics: [diag(Severity.reporta)])
              .verdict,
          Verdict.verde);
    });

    test('sin cobertura: no concluyente, aunque no haya diagnósticos', () {
      expect(
          Executed(
                  witness: testigo(
                      sujetos: const [],
                      omitido: [Omission(reason: 'no miró nada')]),
                  diagnostics: [])
              .verdict,
          Verdict.noConcluyente);
    });

    test('un código de salida distinto de cero NO es no se ejecutó', () {
      // Muchas herramientas salen con 1 cuando encuentran algo: eso significa
      // que corrieron. El resultado lo dan los diagnósticos, no el código.
      expect(Executed(witness: testigo(exitCode: 1), diagnostics: []).verdict,
          Verdict.verde);
    });

    test('el veredicto no es un campo: no hay dónde fijarlo', () {
      expect(
          Executed(witness: testigo(), diagnostics: [])
              .toJson()
              .containsKey('verdict'),
          isFalse);
    });
  });

  group('un testigo que no cubre nada TIENE que decir por qué', () {
    test('sin cobertura y sin omisión no se construye', () {
      // Cierra la acción imposible: hoy un paso queda no concluyente sin decir
      // por qué, y el CLI manda a leer una lista vacía.
      expect(() => testigo(sujetos: const []), throwsArgumentError);
    });

    test('una invocación en blanco no atestigua nada', () {
      expect(() => testigo(invocacion: '  '), throwsArgumentError);
    });

    test('una omisión con motivo en blanco no es una omisión', () {
      expect(() => Omission(subject: 'a', reason: ' '), throwsArgumentError);
    });

    test('una omisión puede no nombrar sujeto: es residuo general', () {
      final o = Omission(reason: 'la herramienta no informa qué archivos leyó');
      expect(o.subject, isNull);
    });

    test('el testigo ya no lleva terminación ni conteo', () {
      // Eran los dos campos con los que se fabricaba un hecho falso.
      final json = testigo().toJson();
      expect(json.containsKey('termination'), isFalse);
      expect(json.containsKey('ownSubjects'), isFalse);
    });
  });

  group('las variantes que un verificador NO puede devolver', () {
    test('un intento nunca es una terminación completa', () {
      expect(
          () => Attempt(
                invocation: 'h',
                subjects: const ['lib'],
                termination: Termination.completa,
                exitCode: 0,
                note: 'x',
                finishedAt: DateTime.utc(2026),
              ),
          throwsArgumentError);
    });

    test('un salto sin sujetos ajenos no es un salto', () {
      expect(() => Skipped(notOfStack: const []), throwsArgumentError);
    });

    test('un salto no tiene dónde llevar un diagnóstico', () {
      // No se puede escribir la prueba: no existe el campo. Este caso queda
      // como aserción sobre el JSON, que es lo que un consumidor ve.
      final s = Skipped(notOfStack: [
        ObservedSubject(
            subject: 'a', ofStack: false, files: 0, reason: 'no es de acá')
      ]);
      expect(s.toJson().containsKey('diagnostics'), isFalse);
    });

    test('lo no observable sin causa tampoco', () {
      expect(() => Unobservable(causes: const []), throwsArgumentError);
    });

    test('un roto sin componente ni error no dice nada', () {
      expect(() => Broken(component: ' ', error: 'x', context: 'y'),
          throwsArgumentError);
      expect(() => Broken(component: 'A', error: '  ', context: 'y'),
          throwsArgumentError);
    });
  });

  test('cada variante declara su clase, y son cinco', () {
    expect(StepKind.values, hasLength(5));
  });

  test('mutar la lista original no cambia el veredicto', () {
    final sujetos = ['lib/a.fuente'];
    final e = Executed(witness: testigo(sujetos: sujetos), diagnostics: []);
    sujetos.clear();
    expect(e.verdict, Verdict.verde);
  });
}
