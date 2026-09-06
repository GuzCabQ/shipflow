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

    test('un sujeto no puede estar cubierto y omitido a la vez', () {
      // «Lo cubrí» y «no lo cubrí» del mismo sujeto en el mismo testigo: la
      // misma clase de afirmación contradictoria que el salto sobre un
      // sujeto del stack, pero del lado del testigo.
      expect(
          () => Witness(
                invocation: 'herramienta --sobre lib',
                subjects: const ['lib/a.fuente'],
                omitted: [Omission(subject: 'lib/a.fuente', reason: 'x')],
                exitCode: 0,
                finishedAt: DateTime.utc(2026),
              ),
          throwsArgumentError);
    });
  });

  group('invariantes de constructor de las variantes que un verificador '
      'NO puede devolver', () {
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

    test('un intento sobre un alcance vacío no se construye', () {
      // Calca la cláusula del puerto: un alcance vacío es precondición
      // violada, no un desenlace que el tipo tenga que poder representar.
      expect(
          () => Attempt(
                invocation: 'h',
                subjects: const [],
                termination: Termination.tiempoAgotado,
                exitCode: 1,
                note: 'x',
                finishedAt: DateTime.utc(2026),
              ),
          throwsArgumentError);
    });

    test('un salto sin sujetos ajenos no es un salto', () {
      expect(() => Skipped(notOfStack: const []), throwsArgumentError);
    });

    test('un salto no acepta un sujeto que el observador declaró del stack', () {
      // El falso verde de la premisa, mudado un nivel arriba: el desenlace
      // que afirma «ninguno de estos era mío» no puede listar uno que sí lo
      // era.
      expect(
          () => Skipped(notOfStack: [
                ObservedSubject(subject: 'lib', ofStack: true, files: 4),
              ]),
          throwsArgumentError);
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

  group('las variantes que un verificador NO puede devolver, en la '
      'jerarquía', () {
    // Ninguno de los casos de arriba afirma esto: todos prueban invariantes
    // de constructor, no la forma del árbol de tipos. Si mañana `Skipped`
    // pasara a extender `VerificationOutcome`, esos casos seguirían verdes.
    test('un salto no es un desenlace que un verificador pueda devolver', () {
      final StepOutcome s = Skipped(notOfStack: [
        ObservedSubject(
            subject: 'a', ofStack: false, files: 0, reason: 'no es de acá')
      ]);
      expect(s, isNot(isA<VerificationOutcome>()));
    });

    test('lo no observable no es un desenlace que un verificador pueda '
        'devolver', () {
      final StepOutcome u = Unobservable(
          causes: [UnobservedSubject(subject: 'a', cause: 'no existe')]);
      expect(u, isNot(isA<VerificationOutcome>()));
    });

    test('lo roto no es un desenlace que un verificador pueda devolver', () {
      final StepOutcome b =
          Broken(component: 'A', error: 'x', context: 'y');
      expect(b, isNot(isA<VerificationOutcome>()));
    });

    test('un ejecutado sí es un desenlace que un verificador puede devolver',
        () {
      final StepOutcome e = Executed(witness: testigo(), diagnostics: []);
      expect(e, isA<VerificationOutcome>());
    });

    test('un abortado sí es un desenlace que un verificador puede devolver',
        () {
      final StepOutcome a = Aborted(
          attempt: Attempt(
        invocation: 'h',
        subjects: const ['lib'],
        termination: Termination.tiempoAgotado,
        exitCode: 1,
        note: 'x',
        finishedAt: DateTime.utc(2026),
      ));
      expect(a, isA<VerificationOutcome>());
    });
  });

  group('el despacho por discriminador', () {
    late Attempt intento;

    setUp(() {
      intento = Attempt(
        invocation: 'h',
        subjects: const ['lib'],
        termination: Termination.tiempoAgotado,
        exitCode: 1,
        note: 'x',
        finishedAt: DateTime.utc(2026),
      );
    });

    test('StepOutcome.fromJson despacha cada variante por su kind', () {
      expect(
          StepOutcome.fromJson(
              Executed(witness: testigo(), diagnostics: []).toJson()),
          isA<Executed>());
      expect(StepOutcome.fromJson(Aborted(attempt: intento).toJson()),
          isA<Aborted>());
      expect(
          StepOutcome.fromJson(Skipped(notOfStack: [
            ObservedSubject(
                subject: 'a', ofStack: false, files: 0, reason: 'ajeno')
          ]).toJson()),
          isA<Skipped>());
      expect(
          StepOutcome.fromJson(Unobservable(
              causes: [UnobservedSubject(subject: 'a', cause: 'no existe')])
              .toJson()),
          isA<Unobservable>());
      expect(
          StepOutcome.fromJson(
              Broken(component: 'A', error: 'x', context: 'y').toJson()),
          isA<Broken>());
    });

    test('un discriminador desconocido lanza, no cae en la variante más '
        'benigna', () {
      expect(() => StepOutcome.fromJson(const {'kind': 'inventado'}),
          throwsArgumentError);
    });

    test('cada variante rechaza un discriminador que no es el suyo', () {
      final json = Executed(witness: testigo(), diagnostics: [])
          .toJson()
          .map((k, v) => MapEntry(k, k == 'kind' ? 'aborted' : v));
      expect(() => Executed.fromJson(json), throwsArgumentError);
    });

    test('VerificationOutcome.fromJson despacha lo ejecutado y lo abortado',
        () {
      expect(
          VerificationOutcome.fromJson(
              Executed(witness: testigo(), diagnostics: []).toJson()),
          isA<Executed>());
      expect(VerificationOutcome.fromJson(Aborted(attempt: intento).toJson()),
          isA<Aborted>());
    });

    test('VerificationOutcome.fromJson lanza ante lo que un verificador NO '
        'puede devolver, al deserializar y no en el sitio del cast', () {
      final salto = Skipped(notOfStack: [
        ObservedSubject(
            subject: 'a', ofStack: false, files: 0, reason: 'ajeno')
      ]).toJson();
      expect(() => VerificationOutcome.fromJson(salto), throwsArgumentError);

      final inobservable = Unobservable(
              causes: [UnobservedSubject(subject: 'a', cause: 'no existe')])
          .toJson();
      expect(() => VerificationOutcome.fromJson(inobservable),
          throwsArgumentError);

      final roto =
          Broken(component: 'A', error: 'x', context: 'y').toJson();
      expect(() => VerificationOutcome.fromJson(roto), throwsArgumentError);
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
