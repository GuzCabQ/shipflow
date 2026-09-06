/// Lo que las pruebas dirigidas no pueden demostrar: que **todo** estado
/// construible tiene semántica, y que ninguno sin evidencia termina verde.
///
/// El generador es exhaustivo y no aleatorio: el espacio es chico y una
/// corrida reproducible vale más que una muestra.
///
/// **Cuatro escenarios, para cubrir los cinco `StepKind` SIN enmascarar
/// mutaciones entre sí.** El escenario A tiene dos sujetos y los dos son del
/// stack: sobre él se puede construir `Executed`, `Aborted` y `Broken`, pero
/// NO `Skipped` ni `Unobservable` —esos dos exigen, respectivamente, un
/// ajeno y un no observado que la coherencia desenlace↔observación de
/// `ResultadoDeCascada` (ver «el desenlace no puede contradecir a la
/// observación» en la suite de la cascada) rechazaría si se inventaran sobre
/// este alcance.
///
/// Ronda 1 de revisión pidió cubrir esas dos variantes con el precedente que
/// lo decide: el tercero de los tres falsos verdes que esta rebanada cierra
/// fue justo un salto incoherente con su observación. La primera versión de
/// esa cobertura juntaba un ajeno Y un no observado en la MISMA observación
/// —un solo escenario B para los dos—, y ronda 2 encontró que eso es
/// cobertura HUECA: con un ajeno y un no observado presentes a la vez, las
/// causas `nadaEjecutado` y `alcanceNoObservable` se disparan siempre
/// juntas para cualquier desenlace que no sea `Executed`, así que son
/// redundantes entre sí ahí. Romper cualquiera de las dos por separado —el
/// bug realista, de una línea— quedaba enmascarado por la otra: la mutación
/// de mordida «contar un salto como ejecutado» dejaba las cinco propiedades
/// en verde, y lo mismo «desactivar la causa del alcance no observable»; solo
/// romper las DOS a la vez —un fallo compuesto que no es el que ocurre en la
/// práctica— hacía caer alguna.
///
/// Por eso son DOS escenarios angostos, no uno:
///
/// - [alcanceSalto] tiene un único sujeto, y es ajeno al stack. No hay ningún
///   no observado, así que `alcanceNoObservable` no puede dispararse nunca
///   ahí — la única causa que le queda disponible a un `Skipped` mal tratado
///   es `nadaEjecutado`, y romperla sola queda expuesto.
/// - [alcanceNoObservable] tiene un único sujeto, y no se pudo observar. No
///   hay ningún ajeno, así que `nadaEjecutado` no puede dispararse —exige al
///   menos un ajeno REAL, ver el comentario de `causas` en el archivo de la
///   cascada—, y lo simétrico vale acá: romper la detección de
///   `alcanceNoObservable` tampoco tiene dónde esconderse.
///
/// Cada uno construye su `Skipped`/`Unobservable` reusando el
/// `ObservedSubject`/`UnobservedSubject` que la propia observación
/// clasificó, no sujetos inventados: no repiten la guardia de coherencia que
/// ya prueba la suite de la cascada, solo llenan el hueco de variantes de
/// este archivo.
///
/// **Ronda 3 encontró un tercer par de guardias que se disparaban juntas,
/// esta vez ADENTRO del escenario A.** `pasoNoConcluyente` y
/// `obligacionSinSaldar` se disparaban siempre a la vez: la rejilla de
/// omisiones de [desenlacesPosiblesA] solo nombraba UN sujeto por vez, así
/// que con cobertura vacía siempre quedaba el otro sujeto sin saldar —una
/// obligación real tapando cualquier ruptura de la detección de lo no
/// concluyente—. Un `grep` global confirmó que ninguna prueba del
/// repositorio, ni de propiedades ni dirigida, ejercitaba `pasoNoConcluyente`
/// aislada. La rejilla ahora agrega una omisión que nombra los DOS sujetos:
/// con cobertura vacía y los dos saldados por omisión, no queda ninguna
/// obligación abierta y `pasoNoConcluyente` deja de tener quién la tape.
///
/// **Un cuarto escenario, [Mixto], para la puerta que los otros tres no
/// pueden abrir.** Es una observación con un sujeto DEL STACK y uno AJENO a
/// la vez —lo utilizable no es ni todo ni nada—, y la rejilla la arma con
/// DOS pasos, no uno: un paso `P1` que ejecuta de verdad y cubre lo único
/// utilizable, conviviendo con un paso `P2` que se SALTA nombrando el ajeno
/// real. Ningún escenario anterior podía representar esta combinación —A
/// tiene los dos sujetos del stack, y Salto/NoObservable tienen lo utilizable
/// vacío, así que un salto ahí nunca contrae obligación alguna— y es
/// exactamente la combinación que encontró la revisión: un `Skipped` sobre un
/// alcance esperado NO vacío quedaba invisible para `obligacionesSinSaldar`,
/// que saltaba todo desenlace que no fuera `Executed` sin mirar si tenía algo
/// que saldar. Antes del arreglo, `P1 ejecuta y cubre · P2 se salta` salía
/// VERDE: la propiedad d) —«ningún desenlace sin cobertura completa termina
/// verde»— es la que lo cazaba, y por eso este archivo se comprobó en rojo
/// contra el código sin arreglar antes de tocar el archivo de la cascada.
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

/// Escenario del salto: un único sujeto, ajeno al stack. Sin ningún no
/// observado, `alcanceNoObservable` no puede dispararse acá — la mutación
/// que rompe `nadaEjecutado` no tiene otra causa que la tape.
const sujetoDelSalto = 'y.ajeno';

/// Escenario de lo no observable: un único sujeto, que no se pudo mirar. Sin
/// ningún ajeno, `nadaEjecutado` no puede dispararse acá —exige al menos un
/// ajeno real— así que la mutación simétrica tampoco tiene dónde esconderse.
const sujetoPerdido = 'z.perdido';

/// Escenario mixto: dos sujetos en la MISMA observación, uno del stack y uno
/// ajeno. Ninguno de los otros tres escenarios puede representar esta forma
/// —A tiene sus dos sujetos del stack; Salto y NoObservable tienen lo
/// utilizable vacío— y por eso ninguno podía exponer un paso saltado
/// CONVIVIENDO con un alcance utilizable no vacío. Ver el comentario del
/// escenario mixto más arriba en el archivo.
const sujetoMixtoDelStack = 'd.fuente';
const sujetoMixtoAjeno = 'w.ajeno';

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
    // **La que separa `pasoNoConcluyente` de `obligacionSinSaldar`.** Nombra
    // los DOS sujetos: combinada con cobertura vacía, saldan las dos
    // obligaciones por omisión y no queda ninguna abierta. Sin este caso, la
    // rejilla nunca producía un `Executed` no concluyente CON el libro
    // saldado, así que las dos causas se disparaban siempre juntas y romper
    // la detección de una quedaba tapado por la otra (ronda 3 de revisión).
    [
      Omission(subject: 'a.fuente', reason: 'no lo leí'),
      Omission(subject: 'b.fuente', reason: 'no lo leí'),
    ],
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

/// El único desenlace del escenario del salto: `Skipped`, coherente con
/// [alcanceSalto] por construcción — reusa el `ObservedSubject` ajeno que la
/// propia observación clasificó.
(String, StepOutcome) desenlaceDeSalto(ScopeObservation alcanceSalto) =>
    ('skipped', Skipped(notOfStack: [alcanceSalto.observed.single]));

/// El único desenlace del escenario de lo no observable: `Unobservable`,
/// coherente con [alcanceNoObservable] por construcción — reusa el
/// `UnobservedSubject` que la propia observación produjo.
(String, StepOutcome) desenlaceDeNoObservable(
        ScopeObservation alcanceNoObservable) =>
    (
      'unobservable',
      Unobservable(causes: [alcanceNoObservable.unobserved.single])
    );

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

/// Arma un `ResultadoDeCascada` de DOS pasos —`P1` y `P2`— sobre [alcance],
/// con desenlaces [p1] y [p2]. Los dos comparten `expectedScope`, igual que
/// en una corrida real: sin aplicabilidad por paso, es la única forma que el
/// constructor acepta (mismo comentario que [_resultadoCon]).
ResultadoDeCascada _resultadoMixto(
        ScopeObservation alcance, StepOutcome p1, StepOutcome p2) =>
    ResultadoDeCascada(
      registrados: [
        RegisteredStep(id: 'P1', expectedScope: alcance.usable()),
        RegisteredStep(id: 'P2', expectedScope: alcance.usable()),
      ],
      alcance: alcance,
      desenlaces: {'P1': p1, 'P2': p2},
    );

/// Los casos del escenario mixto. [alcance] tiene un único sujeto utilizable
/// —el otro es ajeno— así que el alcance esperado de P1 y P2 es ese único
/// sujeto: [_resultadoMixto] rechazaría cualquier otra cosa.
Iterable<(String, ResultadoDeCascada)> casosMixtos(
    ScopeObservation alcance) sync* {
  final ajenoReal = alcance.observed.singleWhere((o) => !o.ofStack);

  Executed cubreLoUtilizable() => Executed(
        witness: Witness(
          invocation: 'herramienta',
          subjects: const [sujetoMixtoDelStack],
          exitCode: 0,
          omitted: const [],
          finishedAt: DateTime.utc(2026),
        ),
        diagnostics: const [],
      );
  Skipped seSalta() => Skipped(notOfStack: [ajenoReal]);

  // **La mordida de C1.** P1 ejecuta de verdad y cubre lo único utilizable;
  // P2 se salta nombrando el ajeno real —coherente con la observación, no
  // inventado—. Antes del arreglo, `obligacionesSinSaldar` saltaba todo
  // desenlace que no fuera `Executed` sin mirar su `expectedScope`, así que
  // P2 no contraía ninguna obligación pese a que la suya —`d.fuente`— seguía
  // sin cubrir ni explicar. La corrida salía VERDE con un paso que ni
  // ejecutó ni dio cuenta de lo suyo.
  yield (
    'P1 ejecuta y cubre · P2 se salta',
    _resultadoMixto(alcance, cubreLoUtilizable(), seSalta())
  );

  // Control negativo: los dos ejecutan y cubren. Tiene que seguir dando
  // VERDE — sin este caso, la propiedad d) no distinguiría un arreglo
  // correcto de uno que además rompe el verde legítimo.
  yield (
    'los dos ejecutan y cubren',
    _resultadoMixto(alcance, cubreLoUtilizable(), cubreLoUtilizable())
  );

  // Los dos se saltan: ninguno cubre lo utilizable, así que el libro tiene
  // que quedar con las DOS obligaciones abiertas, no solo una.
  yield ('los dos se saltan', _resultadoMixto(alcance, seSalta(), seSalta()));
}

/// Todos los casos de los cuatro escenarios, cada uno con SU PROPIA
/// observación: un desenlace de un escenario no tiene sentido evaluado
/// contra el alcance de otro. Devuelve el `ResultadoDeCascada` ya armado —no
/// el (alcance, desenlace) suelto— porque el escenario mixto necesita DOS
/// pasos y un solo desenlace ya no alcanza para nombrar un caso.
Iterable<(String, ResultadoDeCascada)> todosLosCasos(
    ScopeObservation alcanceA,
    ScopeObservation alcanceSalto,
    ScopeObservation alcanceNoObservable,
    ScopeObservation alcanceMixto) sync* {
  for (final (nombre, d) in desenlacesPosiblesA()) {
    yield ('A·$nombre', _resultadoCon(alcanceA, d));
  }
  final (nombreSalto, salto) = desenlaceDeSalto(alcanceSalto);
  yield ('Salto·$nombreSalto', _resultadoCon(alcanceSalto, salto));
  final (nombreNoObs, noObs) = desenlaceDeNoObservable(alcanceNoObservable);
  yield (
    'NoObservable·$nombreNoObs',
    _resultadoCon(alcanceNoObservable, noObs)
  );
  for (final (nombre, r) in casosMixtos(alcanceMixto)) {
    yield ('Mixto·$nombre', r);
  }
}

void main() {
  final observadorA = ObservadorDeAlcanceFalso(observados: {
    for (final s in sujetosA)
      s: ObservedSubject(subject: s, ofStack: true, files: 1),
  });
  final observadorSalto = ObservadorDeAlcanceFalso(observados: {
    sujetoDelSalto: ObservedSubject(
        subject: sujetoDelSalto,
        ofStack: false,
        files: 0,
        reason: 'no es de este stack'),
  });
  final observadorNoObservable = ObservadorDeAlcanceFalso(
    observados: const {},
    noObservados: const {sujetoPerdido: 'no se pudo mirar'},
  );
  final observadorMixto = ObservadorDeAlcanceFalso(observados: {
    sujetoMixtoDelStack:
        ObservedSubject(subject: sujetoMixtoDelStack, ofStack: true, files: 1),
    sujetoMixtoAjeno: ObservedSubject(
        subject: sujetoMixtoAjeno,
        ofStack: false,
        files: 0,
        reason: 'no es de este stack'),
  });

  late ScopeObservation alcanceA;
  late ScopeObservation alcanceSalto;
  late ScopeObservation alcanceNoObservable;
  late ScopeObservation alcanceMixto;

  setUpAll(() async {
    alcanceA = await observadorA.observe(sujetosA);
    alcanceSalto = await observadorSalto.observe(const [sujetoDelSalto]);
    alcanceNoObservable =
        await observadorNoObservable.observe(const [sujetoPerdido]);
    alcanceMixto = await observadorMixto
        .observe(const [sujetoMixtoDelStack, sujetoMixtoAjeno]);
  });

  Iterable<(String, ResultadoDeCascada)> todos() =>
      todosLosCasos(alcanceA, alcanceSalto, alcanceNoObservable, alcanceMixto);

  test('a · todo desenlace construible tiene estado y causa. Función total',
      () {
    // **Esta propiedad no tiene una guardia que se le pueda quitar.** No es
    // una debilidad de la prueba: `estado` y `causas` (en el archivo de la
    // cascada) son funciones sin ningún camino parcial —ni `.first` sin
    // resguardo, ni `as` inseguro, ni acceso a una clave que pudiera
    // faltar— sobre un conjunto de variantes que `sealed` cierra para
    // siempre: nada fuera de el archivo de desenlace puede agregar un sexto
    // `StepOutcome`. Y si alguna vez se agregara uno ADENTRO de ese archivo,
    // los `switch` exhaustivos sobre `StepKind` que ya existen
    // —`StepOutcome.fromJson` acá, `_etapaDe` y `_desenlaceEnTexto` en
    // `cli`— dejan de compilar hasta que alguien lo atienda en cada uno. La
    // totalidad de esta función la sostiene el compilador, no un `if` que
    // esta prueba pueda desarmar; por eso el ejercicio de mordida de esta
    // rebanada la deja aparte, y por eso sigue acá: sin este comentario, el
    // próximo que lo revise la va a encontrar muda —sin nada que remover y
    // ver caer— y la va a borrar por inútil, cuando lo que pasa es lo
    // contrario: el invariante es más fuerte que una prueba.
    for (final (nombre, r) in todos()) {
      expect(() => r.estado, returnsNormally, reason: nombre);
      expect(() => r.causas, returnsNormally, reason: nombre);
      expect(EstadoDeCorrida.values, contains(r.estado), reason: nombre);
    }
  });

  test('b · verde implica toda obligación saldada y nada sin concluir', () {
    for (final (nombre, r) in todos()) {
      if (r.estado != EstadoDeCorrida.verde) continue;
      expect(r.obligacionesSinSaldar, isEmpty, reason: nombre);
      expect(r.causas, isEmpty, reason: nombre);
      // Generalizado a TODOS los desenlaces del resultado, no a uno solo: el
      // escenario mixto registra dos pasos, y verde exige que los dos hayan
      // ejecutado con veredicto verde —cualquiera que no sea `Executed` deja
      // sin saldar su propio `expectedScope`, que acá nunca es vacío—.
      for (final d in r.desenlaces.values) {
        expect(d, isA<Executed>(), reason: nombre);
        expect((d as Executed).verdict, Verdict.verde, reason: nombre);
      }
    }
  });

  test('c · la cuenta de diagnósticos es la suma de los ejecutados', () {
    for (final (nombre, r) in todos()) {
      final esperados = r.desenlaces.values
          .whereType<Executed>()
          .fold<int>(0, (n, e) => n + e.diagnostics.length);
      expect(r.diagnosticos, hasLength(esperados), reason: nombre);
    }
  });

  test('d · ningún desenlace sin cobertura completa termina verde', () {
    // La propiedad que cierra el falso verde: cubrir la mitad sin explicar el
    // resto no puede dar verde, sea cual sea el resto de la combinación.
    // **Por REGISTRO, no por resultado**: cada `RegisteredStep` tiene que
    // saldar SU PROPIO `expectedScope` con SU PROPIO desenlace —el escenario
    // mixto tiene dos pasos y cada uno debe su propia cuenta—. Un desenlace
    // que no es `Executed` no puede saldar nada; solo pasa si su
    // `expectedScope` ya es vacío, que es el caso legítimo de un salto sobre
    // un alcance enteramente ajeno (escenarios Salto y NoObservable). Esta
    // cuenta se computa INDEPENDIENTE de `obligacionesSinSaldar` —es lo que
    // se está probando— y por eso la mordida contra el código sin arreglar sí
    // la puede cazar.
    var ejercitados = 0;
    for (final (nombre, r) in todos()) {
      final incompleto = r.registrados.any((registro) {
        final d = r.desenlaces[registro.id]!;
        if (d is! Executed) return registro.expectedScope.isNotEmpty;
        final saldados = {
          ...d.witness.subjects,
          for (final o in d.witness.omitted)
            if (o.subject != null) o.subject!,
        };
        return !saldados.containsAll(registro.expectedScope);
      });
      if (!incompleto) continue;
      ejercitados++;
      expect(r.estado, isNot(EstadoDeCorrida.verde), reason: nombre);
    }
    // **La guardia que sostiene esta propiedad.** Si el generador no produce
    // ningún caso con cobertura incompleta sobre sujetos reales, el `for` de
    // arriba no ejecuta ningún `expect` y la propiedad pasa sin haber
    // probado nada — exactamente el falso verde que esta rebanada existe
    // para cazar, pero en el propio archivo de propiedades. El escenario A y
    // el escenario mixto tienen sujetos reales y sus rejillas incluyen
    // cobertura vacía y parcial, así que esto tiene que ser mayor que cero;
    // si baja a cero, el generador dejó de ejercitar la propiedad y hay que
    // arreglarlo, no relajar el `expect`.
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
