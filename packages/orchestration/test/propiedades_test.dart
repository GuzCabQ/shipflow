/// Lo que las pruebas dirigidas no pueden demostrar: que **todo** estado
/// construible tiene semántica, y que ninguno sin evidencia termina verde.
///
/// El generador es exhaustivo y no aleatorio: el espacio es chico y una
/// corrida reproducible vale más que una muestra.
///
/// **Notas de adaptación.** El brief de esta tarea se escribió antes de tres
/// cosas que este archivo tiene que respetar:
///
/// 1. `ResultadoDeCascada.registrados` pasó de `List<String>` a
///    `List<RegisteredStep>`, y el constructor valida coherencia entre el
///    alcance esperado de cada paso y lo utilizable de la observación. Cada
///    resultado de este archivo se arma con
///    `RegisteredStep(expectedScope: alcance.usable())` — construirlo con
///    cualquier otra cosa haría que el generador pruebe una excepción de
///    construcción, no la propiedad buscada.
/// 2. El brief importaba `ObservadorDeAlcanceFalso` de `plugin_fake`, pero
///    `orchestration` no puede ver ningún plugin (lo hace cumplir un check de
///    arquitectura propio). El doble vive acá, copiado de la suite de la
///    cascada por la misma razón que esa suite ya documenta: cada una
///    necesita el suyo, no el de `plugin_fake`.
/// 3. `Termination` y `Attempt` no estaban en el archivo de desenlace que el
///    brief conocía: la terminación distinta de completa y el intento viven
///    en `Aborted`, no sueltas en `Witness`.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

const sujetos = ['a.fuente', 'b.fuente'];

/// Un observador de alcance que responde de una tabla. **No toca el disco.**
/// Copiado de la suite de la cascada: `orchestration` no puede depender de
/// ningún plugin, así que cada suite trae el suyo.
class ObservadorDeAlcanceFalso implements ScopeObserver {
  final Map<String, ObservedSubject> observados;

  ObservadorDeAlcanceFalso({required Map<String, ObservedSubject> observados})
      : observados = Map.unmodifiable(observados);

  @override
  Future<ScopeObservation> observe(List<String> requested) async {
    final vistos = <ObservedSubject>[];
    for (final s in requested) {
      final o = observados[s];
      if (o == null) {
        throw ArgumentError.value(
            s,
            'requested',
            'El fake no tiene declarado este sujeto. Declaralo en '
                '`observados`: adivinar sería clasificar por su cuenta');
      }
      vistos.add(o);
    }
    return ScopeObservation(
      requested: requested,
      observed: vistos,
      unobserved: const [],
      observedAt: DateTime.utc(2026),
    );
  }
}

/// Todos los desenlaces que un paso puede tener, con su cobertura.
///
/// **Solo tres de los cinco `StepKind`.** El alcance fijo de este archivo
/// declara los dos sujetos del stack: no hay ningún ajeno ni ningún no
/// observado con el que `Skipped` o `Unobservable` pudieran construirse sin
/// violar la coherencia que `ResultadoDeCascada` exige entre un desenlace y
/// la observación de su corrida (ver el grupo «el desenlace no puede
/// contradecir a la observación» en la suite de la cascada). Forzarlos acá
/// probaría una excepción de construcción ajena a esta propiedad, no un
/// estado real.
Iterable<(String, StepOutcome)> desenlacesPosibles() sync* {
  final coberturas = <List<String>>[
    const [],
    const ['a.fuente'],
    sujetos,
  ];
  final diagnosticos = <List<Diagnostic>>[
    const [],
    [_diag(Severity.reporta)],
    [_diag(Severity.bloquea)],
  ];
  final omisiones = <List<Omission>>[
    const [],
    [Omission(reason: 'residuo general')],
    [Omission(subject: 'b.fuente', reason: 'no lo leí')],
  ];
  for (final c in coberturas) {
    for (final d in diagnosticos) {
      for (final o in omisiones) {
        if (c.isEmpty && o.isEmpty) continue; // el tipo lo prohíbe
        // Un sujeto no puede estar cubierto Y omitido puntualmente a la vez
        // (invariante de `Witness`): la única combinación de esta rejilla que
        // lo pisa es cubrir los DOS sujetos y, a la vez, omitir puntualmente
        // ese mismo `b.fuente`. No es un caso que este archivo tenga que
        // representar dos veces —`Witness` ya lo prueba en su propia suite—
        // así que se saltea acá.
        if (o.any((om) => om.subject != null && c.contains(om.subject))) {
          continue;
        }
        yield (
          'executed·${c.length}·${d.length}·${o.length}',
          Executed(
            witness: Witness(
              invocation: 'herramienta',
              subjects: c,
              omitted: o,
              exitCode: 0,
              finishedAt: DateTime.utc(2026),
            ),
            diagnostics: d,
          )
        );
      }
    }
  }
  yield (
    'aborted',
    Aborted(
        attempt: Attempt(
      invocation: 'herramienta',
      subjects: sujetos,
      termination: Termination.tiempoAgotado,
      exitCode: -1,
      note: 'se acabó el presupuesto',
      finishedAt: DateTime.utc(2026),
    ))
  );
  yield ('broken', Broken(component: 'X', error: 'se rompió', context: 'lib'));
}

Diagnostic _diag(Severity s) => Diagnostic(
      file: 'a.fuente',
      severity: s,
      ruleId: 'r',
      message: const QuotedText('m', source: 'test'),
    );

/// Arma un `ResultadoDeCascada` de un único paso `A` con desenlace [d], sobre
/// [alcance]. **Coherente por construcción**: el alcance esperado del paso es
/// exactamente `alcance.usable()`, que es la única forma que el constructor
/// acepta hoy (sin aplicabilidad por paso, ver el archivo de la cascada).
ResultadoDeCascada _resultadoCon(ScopeObservation alcance, StepOutcome d) =>
    ResultadoDeCascada(
      registrados: [RegisteredStep(id: 'A', expectedScope: alcance.usable())],
      alcance: alcance,
      desenlaces: {'A': d},
    );

void main() {
  final observador = ObservadorDeAlcanceFalso(observados: {
    for (final s in sujetos)
      s: ObservedSubject(subject: s, ofStack: true, files: 1),
  });

  test('a · todo desenlace construible tiene estado y causa. Función total',
      () async {
    final alcance = await observador.observe(sujetos);
    for (final (nombre, d) in desenlacesPosibles()) {
      final r = _resultadoCon(alcance, d);
      expect(() => r.estado, returnsNormally, reason: nombre);
      expect(() => r.causas, returnsNormally, reason: nombre);
      expect(EstadoDeCorrida.values, contains(r.estado), reason: nombre);
    }
  });

  test('b · verde implica toda obligación saldada y nada sin concluir',
      () async {
    final alcance = await observador.observe(sujetos);
    for (final (nombre, d) in desenlacesPosibles()) {
      final r = _resultadoCon(alcance, d);
      if (r.estado != EstadoDeCorrida.verde) continue;
      expect(r.obligacionesSinSaldar, isEmpty, reason: nombre);
      expect(r.causas, isEmpty, reason: nombre);
      expect(d, isA<Executed>(), reason: nombre);
      expect((d as Executed).verdict, Verdict.verde, reason: nombre);
    }
  });

  test('c · la cuenta de diagnósticos es la suma de los ejecutados', () async {
    final alcance = await observador.observe(sujetos);
    for (final (nombre, d) in desenlacesPosibles()) {
      final r = _resultadoCon(alcance, d);
      final esperados = d is Executed ? d.diagnostics.length : 0;
      expect(r.diagnosticos, hasLength(esperados), reason: nombre);
    }
  });

  test('d · ningún desenlace sin cobertura completa termina verde', () async {
    // La propiedad que cierra el falso verde: cubrir la mitad sin explicar el
    // resto no puede dar verde, sea cual sea el resto de la combinación.
    final alcance = await observador.observe(sujetos);
    var ejercitados = 0;
    for (final (nombre, d) in desenlacesPosibles()) {
      if (d is! Executed) continue;
      final saldados = {
        ...d.witness.subjects,
        for (final o in d.witness.omitted)
          if (o.subject != null) o.subject!,
      };
      if (saldados.containsAll(sujetos)) continue;
      ejercitados++;
      final r = _resultadoCon(alcance, d);
      expect(r.estado, isNot(EstadoDeCorrida.verde), reason: nombre);
    }
    // **La guardia que sostiene esta propiedad.** Si el generador no produce
    // ningún caso con cobertura incompleta sobre sujetos reales, el `for` de
    // arriba no ejecuta ningún `expect` y la propiedad pasa sin haber
    // probado nada — exactamente el falso verde que esta rebanada existe
    // para cazar, pero en el propio archivo de propiedades. `sujetos` tiene
    // dos elementos reales y la rejilla de `desenlacesPosibles` incluye
    // cobertura vacía y cobertura parcial, así que esto tiene que ser mayor
    // que cero; si baja a cero, el generador dejó de ejercitar la propiedad
    // y hay que arreglarlo, no relajar el `expect`.
    expect(ejercitados, greaterThan(0),
        reason: 'el generador tiene que producir al menos un desenlace con '
            'cobertura incompleta sobre sujetos reales, o esta propiedad no '
            'está probando nada');
  });

  test('e · un registrado sin desenlace no se puede construir', () async {
    // `await` no puede ir dentro de `expect`: se saca la observación afuera.
    final alcance = await observador.observe(sujetos);
    expect(
        () => ResultadoDeCascada(
              registrados: [
                RegisteredStep(id: 'A', expectedScope: alcance.usable()),
                RegisteredStep(id: 'B', expectedScope: alcance.usable()),
              ],
              alcance: alcance,
              desenlaces: {'A': desenlacesPosibles().first.$2},
            ),
        throwsArgumentError);
  });
}
