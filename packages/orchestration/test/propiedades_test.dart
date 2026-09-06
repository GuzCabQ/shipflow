/// Lo que las pruebas dirigidas no pueden demostrar: que **todo** estado
/// construible tiene semántica, y que ninguno sin evidencia termina verde.
///
/// El generador es exhaustivo y no aleatorio: el espacio es chico y una
/// corrida reproducible vale más que una muestra.
///
/// **Dos escenarios, para cubrir los cinco `StepKind`.** El escenario A tiene
/// dos sujetos y los dos son del stack: sobre él se puede construir
/// `Executed`, `Aborted` y `Broken`, pero NO `Skipped` ni `Unobservable` —esos
/// dos exigen, respectivamente, un ajeno y un no observado que la
/// coherencia desenlace↔observación de `ResultadoDeCascada` (ver «el
/// desenlace no puede contradecir a la observación» en la suite de la
/// cascada) rechazaría si se inventaran sobre este alcance. El escenario B
/// agrega un tercer sujeto de cada clase —uno del stack, uno ajeno, uno no
/// observado— para que esas dos variantes también entren al generador.
///
/// Ronda 1 de revisión lo pidió con el precedente que lo decide: el tercero
/// de los tres falsos verdes que esta rebanada cierra fue justo un salto
/// incoherente con su observación. Sin el escenario B, la propiedad «todo
/// estado construible tiene semántica» cubría 3 de 5 variantes, y un mañana
/// que rompiera cómo se tratan un salto o un no observable solo lo cazarían
/// las pruebas dirigidas —casos puntuales, no el espacio—. El escenario B no
/// repite esa guardia de coherencia: construye un `Skipped`/`Unobservable`
/// coherentes A PROPÓSITO, reusando los mismos `ObservedSubject`/
/// `UnobservedSubject` que la propia observación produjo, así que no hay
/// invención de sujetos que discutir.
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

/// Escenario A: dos sujetos, los dos del stack.
const sujetosA = ['a.fuente', 'b.fuente'];

/// Escenario B: uno del stack, uno ajeno, uno no observado.
const sujetoDelStackB = 'x.fuente';
const sujetoAjenoB = 'y.ajeno';
const sujetoPerdidoB = 'z.perdido';
const sujetosB = [sujetoDelStackB, sujetoAjenoB, sujetoPerdidoB];

/// Un observador de alcance que responde de una tabla. **No toca el disco.**
/// Copiado de la suite de la cascada: `orchestration` no puede depender de
/// ningún plugin, así que cada suite trae el suyo.
class ObservadorDeAlcanceFalso implements ScopeObserver {
  final Map<String, ObservedSubject> observados;
  final Map<String, String> noObservados;

  ObservadorDeAlcanceFalso({
    required Map<String, ObservedSubject> observados,
    Map<String, String> noObservados = const {},
  })  : observados = Map.unmodifiable(observados),
        noObservados = Map.unmodifiable(noObservados);

  @override
  Future<ScopeObservation> observe(List<String> requested) async {
    final vistos = <ObservedSubject>[];
    final ciegos = <UnobservedSubject>[];
    for (final s in requested) {
      final causa = noObservados[s];
      if (causa != null) {
        ciegos.add(UnobservedSubject(subject: s, cause: causa));
        continue;
      }
      final o = observados[s];
      if (o == null) {
        throw ArgumentError.value(
            s,
            'requested',
            'El fake no tiene declarado este sujeto. Declaralo en '
                '`observados` o en `noObservados`: adivinar sería '
                'clasificar por su cuenta');
      }
      vistos.add(o);
    }
    return ScopeObservation(
      requested: requested,
      observed: vistos,
      unobserved: ciegos,
      observedAt: DateTime.utc(2026),
    );
  }
}

/// Los desenlaces del escenario A: `Executed`, `Aborted` y `Broken`.
///
/// Es la rejilla completa de cobertura × diagnósticos × omisiones sobre los
/// dos sujetos del escenario A, más un `Aborted` y un `Broken` sueltos.
Iterable<(String, StepOutcome)> desenlacesPosiblesA() sync* {
  final coberturas = <List<String>>[
    const [],
    const ['a.fuente'],
    sujetosA,
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
      subjects: sujetosA,
      termination: Termination.tiempoAgotado,
      exitCode: -1,
      note: 'se acabó el presupuesto',
      finishedAt: DateTime.utc(2026),
    ))
  );
  yield ('broken', Broken(component: 'X', error: 'se rompió', context: 'lib'));
}

/// Los desenlaces del escenario B: `Skipped` y `Unobservable`, coherentes con
/// [alcanceB] por construcción — se arman a partir de lo que la propia
/// observación clasificó, no de sujetos inventados.
Iterable<(String, StepOutcome)> desenlacesPosiblesB(
    ScopeObservation alcanceB) sync* {
  final ajeno = alcanceB.observed.singleWhere((o) => !o.ofStack);
  yield ('skipped', Skipped(notOfStack: [ajeno]));

  final perdido = alcanceB.unobserved.single;
  yield ('unobservable', Unobservable(causes: [perdido]));
}

Diagnostic _diag(Severity s) => Diagnostic(
      file: 'a.fuente',
      severity: s,
      ruleId: 'r',
      message: const QuotedText('m', source: 'test'),
    );

/// Todos los casos de los dos escenarios, cada uno con SU PROPIA observación:
/// un desenlace del escenario B no tiene sentido evaluado contra el alcance
/// del escenario A, y viceversa.
Iterable<(String, ScopeObservation, StepOutcome)> todosLosCasos(
    ScopeObservation alcanceA, ScopeObservation alcanceB) sync* {
  for (final (nombre, d) in desenlacesPosiblesA()) {
    yield ('A·$nombre', alcanceA, d);
  }
  for (final (nombre, d) in desenlacesPosiblesB(alcanceB)) {
    yield ('B·$nombre', alcanceB, d);
  }
}

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
  final observadorA = ObservadorDeAlcanceFalso(observados: {
    for (final s in sujetosA)
      s: ObservedSubject(subject: s, ofStack: true, files: 1),
  });
  final observadorB = ObservadorDeAlcanceFalso(
    observados: {
      sujetoDelStackB:
          ObservedSubject(subject: sujetoDelStackB, ofStack: true, files: 1),
      sujetoAjenoB: ObservedSubject(
          subject: sujetoAjenoB,
          ofStack: false,
          files: 0,
          reason: 'no es de este stack'),
    },
    noObservados: const {sujetoPerdidoB: 'no se pudo mirar'},
  );

  late ScopeObservation alcanceA;
  late ScopeObservation alcanceB;

  setUpAll(() async {
    alcanceA = await observadorA.observe(sujetosA);
    alcanceB = await observadorB.observe(sujetosB);
  });

  test('a · todo desenlace construible tiene estado y causa. Función total',
      () {
    // **Esta propiedad no tiene una guardia que se le pueda quitar.** No es
    // una debilidad de la prueba: `estado` y `causas` (en el archivo de la cascada) son
    // funciones sin ningún camino parcial —ni `.first` sin resguardo, ni
    // `as` inseguro, ni acceso a una clave que pudiera faltar— sobre un
    // conjunto de variantes que `sealed` cierra para siempre: nada fuera de
    // el archivo de desenlace puede agregar un sexto `StepOutcome`. Y si
    // alguna vez se agregara uno ADENTRO de ese archivo, los `switch`
    // exhaustivos sobre `StepKind` que ya existen —`StepOutcome.fromJson`
    // acá, `_etapaDe` y `_desenlaceEnTexto` en `cli`— dejan de compilar
    // hasta que alguien lo
    // atienda en cada uno. La totalidad de esta función la sostiene el
    // compilador, no un `if` que esta prueba pueda desarmar; por eso el
    // ejercicio de mordida de esta rebanada la deja aparte, y por eso sigue
    // acá: sin este comentario, el próximo que lo revise la va a encontrar
    // muda —sin nada que remover y ver caer— y la va a borrar por inútil,
    // cuando lo que pasa es lo contrario: el invariante es más fuerte que
    // una prueba.
    for (final (nombre, alcance, d) in todosLosCasos(alcanceA, alcanceB)) {
      final r = _resultadoCon(alcance, d);
      expect(() => r.estado, returnsNormally, reason: nombre);
      expect(() => r.causas, returnsNormally, reason: nombre);
      expect(EstadoDeCorrida.values, contains(r.estado), reason: nombre);
    }
  });

  test('b · verde implica toda obligación saldada y nada sin concluir', () {
    for (final (nombre, alcance, d) in todosLosCasos(alcanceA, alcanceB)) {
      final r = _resultadoCon(alcance, d);
      if (r.estado != EstadoDeCorrida.verde) continue;
      expect(r.obligacionesSinSaldar, isEmpty, reason: nombre);
      expect(r.causas, isEmpty, reason: nombre);
      expect(d, isA<Executed>(), reason: nombre);
      expect((d as Executed).verdict, Verdict.verde, reason: nombre);
    }
  });

  test('c · la cuenta de diagnósticos es la suma de los ejecutados', () {
    for (final (nombre, alcance, d) in todosLosCasos(alcanceA, alcanceB)) {
      final r = _resultadoCon(alcance, d);
      final esperados = d is Executed ? d.diagnostics.length : 0;
      expect(r.diagnosticos, hasLength(esperados), reason: nombre);
    }
  });

  test('d · ningún desenlace sin cobertura completa termina verde', () {
    // La propiedad que cierra el falso verde: cubrir la mitad sin explicar el
    // resto no puede dar verde, sea cual sea el resto de la combinación.
    // **Contra `alcance.usable()`, no contra una constante**: en el escenario
    // B lo utilizable es solo `sujetoDelStackB` —el ajeno y el no observado
    // no son utilizables por definición—, así que medir contra una lista fija
    // de sujetos sería incorrecto ahí. Solo el escenario A aporta `Executed`,
    // así que en la práctica es el único que ejercita esta propiedad, pero la
    // expresión vale para los dos.
    var ejercitados = 0;
    for (final (nombre, alcance, d) in todosLosCasos(alcanceA, alcanceB)) {
      if (d is! Executed) continue;
      final saldados = {
        ...d.witness.subjects,
        for (final o in d.witness.omitted)
          if (o.subject != null) o.subject!,
      };
      if (saldados.containsAll(alcance.usable())) continue;
      ejercitados++;
      final r = _resultadoCon(alcance, d);
      expect(r.estado, isNot(EstadoDeCorrida.verde), reason: nombre);
    }
    // **La guardia que sostiene esta propiedad.** Si el generador no produce
    // ningún caso con cobertura incompleta sobre sujetos reales, el `for` de
    // arriba no ejecuta ningún `expect` y la propiedad pasa sin haber
    // probado nada — exactamente el falso verde que esta rebanada existe
    // para cazar, pero en el propio archivo de propiedades. El escenario A
    // tiene sujetos reales y su rejilla incluye cobertura vacía y parcial,
    // así que esto tiene que ser mayor que cero; si baja a cero, el
    // generador dejó de ejercitar la propiedad y hay que arreglarlo, no
    // relajar el `expect`.
    expect(ejercitados, greaterThan(0),
        reason: 'el generador tiene que producir al menos un desenlace con '
            'cobertura incompleta sobre sujetos reales, o esta propiedad no '
            'está probando nada');
  });

  test('e · un registrado sin desenlace no se puede construir', () {
    expect(
        () => ResultadoDeCascada(
              registrados: [
                RegisteredStep(id: 'A', expectedScope: alcanceA.usable()),
                RegisteredStep(id: 'B', expectedScope: alcanceA.usable()),
              ],
              alcance: alcanceA,
              desenlaces: {'A': desenlacesPosiblesA().first.$2},
            ),
        throwsArgumentError);
  });
}
