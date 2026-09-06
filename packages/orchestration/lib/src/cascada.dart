/// La cascada: un registro ordenado de pasos, y lo que resulta de correrlos.
///
/// **No sabe qué pasos existen.** Solo que son [Verifier]. Quién los compone es
/// el composition root, y una regla de arquitectura lo hace cumplir: este
/// paquete no puede ver ningún plugin. Esa ignorancia es la que permite que
/// cambiar de stack no toque la orquestación.
///
/// **Clasifica sobre hechos, no sobre conclusiones del paso.** El salto y lo
/// no observable ya no salen de lo que un verificador declaró sobre sí mismo
/// —eso era pedirle que juzgara su propia cobertura, ADR-011 corolario 4— sino
/// de lo que devolvió el [ScopeObserver]: hechos por sujeto, mirados una sola
/// vez para toda la corrida.
library;

import 'package:core/core.dart';

/// Se lanza cuando un registro de pasos no se puede usar como registro.
class CascadaNoRegistrable implements Exception {
  final String reason;
  const CascadaNoRegistrable(this.reason);

  @override
  String toString() => 'CascadaNoRegistrable: $reason';
}

/// Cómo terminó una corrida entera. **No es [Verdict]**, y la diferencia es
/// el punto: un veredicto es de un paso, y una corrida puede terminar por
/// cosas que no son veredictos de nadie.
///
/// Faltan estados que el producto va a necesitar —una detención por
/// presupuesto agotado (ADR-014)— y **no se declaran todavía**: no hay
/// presupuestos, y un estado que nada produce es una promesa, no un dato.
enum EstadoDeCorrida {
  verde,
  rojo,

  /// Algo no se pudo observar, o algo quedó sin explicar. Se trata como rojo
  /// (ADR-011).
  noConcluyente,

  /// El arnés se rompió. **Distinto de «el cambio no verificó»**: acá no se
  /// puede afirmar nada sobre el cambio.
  errorInterno,
}

/// Un paso tal como quedó registrado **para una corrida dada**: su id y el
/// alcance que se esperaba que cubriera.
///
/// **La cascada lo arma adentro, después de observar.** No se construye al
/// componer el registro —ahí todavía no hay alcance observado— sino dentro de
/// `correr`, y por eso su [expectedScope] puede depender de la observación de
/// esa corrida.
///
/// **Hoy el alcance esperado de TODOS los pasos es el mismo: el alcance
/// utilizable de la corrida entera.** No hay todavía aplicabilidad por paso
/// —un paso que declare que un sujeto, aunque sea del stack, no es asunto
/// suyo—. Cuando llegue, el constructor gana un parámetro **opcional** que
/// estrecha este campo para el paso que lo declare, y eso no rompe a nadie:
/// todo lo que hoy lo construye sigue construyendo exactamente lo mismo.
class RegisteredStep {
  final String id;
  final List<String> expectedScope;

  RegisteredStep({required this.id, required List<String> expectedScope})
      : expectedScope = List.unmodifiable(expectedScope) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Un paso sin id no es registrable');
    }
  }
}

/// Un par paso-sujeto que el paso tenía que cubrir o explicar.
typedef Obligacion = ({String paso, String sujeto});

/// Por qué una corrida no puede afirmar cobertura. **Es una lista, no un
/// valor**: pueden concurrir, y la acción siguiente sale de la primera.
enum CausaNoConcluyente {
  sinVerificadores,
  nadaEjecutado,
  alcanceNoObservable,
  pasoAbortado,
  pasoNoConcluyente,
  obligacionSinSaldar,
}

/// Lo que resulta de correr una cascada.
///
/// [estado] se **deriva**, igual que `Executed.verdict`. No hay campo donde
/// escribirlo, así que no hay forma de poner una corrida en verde desde
/// afuera.
class ResultadoDeCascada {
  /// Los pasos que la corrida registró, con el alcance que se esperaba que
  /// cada uno cubriera. **Es el denominador**: todo paso de acá tiene su
  /// desenlace, y el libro de obligaciones lee su [RegisteredStep.expectedScope]
  /// en vez de una noción global de «lo utilizable».
  final List<RegisteredStep> registrados;

  /// La foto única del alcance de esta corrida.
  final ScopeObservation alcance;

  /// Lo que produjo cada paso, por su id.
  final Map<String, StepOutcome> desenlaces;

  ResultadoDeCascada({
    required List<RegisteredStep> registrados,
    required this.alcance,
    required Map<String, StepOutcome> desenlaces,
  })  : registrados = List.unmodifiable(registrados),
        desenlaces = Map.unmodifiable(desenlaces) {
    // **El id es una CLAVE, y dos registros con la misma clave no son un
    // registro.** `Cascada` ya rechaza ids duplicados al construirse, pero
    // eso es un invariante del PRODUCTOR y este tipo es público y exportado:
    // quien lo arme por otro camino tiene que chocar con el mismo muro.
    //
    // El agujero estaba en el `.toSet()` de abajo, que colapsaba la
    // multiplicidad antes de comparar contra los desenlaces: dos registros
    // 'A' quedaban saldados por un solo desenlace 'A', «ninguno falta» y
    // «ninguno sobra» pasaban las dos, y un paso podía no haber corrido sin
    // que la cuenta lo notara. Es exactamente lo que el constructor de
    // `Cascada` explica para su propia comprobación, un nivel más arriba.
    final repetidos = <String>{};
    final unaVez = <String>{};
    for (final r in this.registrados) {
      if (!unaVez.add(r.id)) repetidos.add(r.id);
    }
    if (repetidos.isNotEmpty) {
      throw ArgumentError.value(
          repetidos.toList(),
          'registrados',
          'Estos ids están registrados más de una vez. Se comparan '
              'registrados contra desenlaces por id, así que un desenlace '
              'saldaría a los dos y un paso podría no haber corrido sin que '
              'nadie se entere');
    }
    final ids = unaVez;
    // **`sinEjecutar` desaparece porque no puede existir.** Antes era una
    // resta que podía dar distinto de cero; ahora todo registrado tiene su
    // desenlace o el resultado no se construye.
    final faltan = ids.where((id) => !this.desenlaces.containsKey(id));
    if (faltan.isNotEmpty) {
      throw ArgumentError.value(
          faltan.toList(),
          'desenlaces',
          'Estos pasos están registrados y no tienen desenlace. Un `started` '
              'sin cerrar deja esperando a quien consuma el protocolo');
    }
    final sobran = this.desenlaces.keys.where((id) => !ids.contains(id));
    if (sobran.isNotEmpty) {
      throw ArgumentError.value(sobran.toList(), 'desenlaces',
          'Hay desenlaces de pasos que no están registrados');
    }

    // **El alcance esperado deja de ser gratis.** Antes el denominador del
    // libro de obligaciones era literalmente `alcance.usable()`, y su
    // corrección salía gratis de que `ScopeObservation` valida su partición
    // contra lo pedido. `expectedScope` es un campo libre en cada
    // [RegisteredStep], así que esa garantía hay que reponerla acá, a mano,
    // en las dos direcciones:
    //
    // - **Ningún sujeto en blanco.** No nombra nada, y no se le puede pedir
    //   cuenta de él a nadie.
    // - **Ni más chico ni más grande que lo utilizable de esta corrida.** Un
    //   `expectedScope` más CHICO —el caso límite es la lista vacía— deja
    //   sujetos utilizables sin obligación: el libro los saltea en silencio y
    //   la corrida puede salir verde sobre algo que nadie prometió cubrir. Uno
    //   más GRANDE fabrica una obligación sobre un sujeto que la observación
    //   nunca dio como utilizable. Hoy —sin aplicabilidad por paso— el único
    //   valor que no incurre en ninguno de los dos es la igualdad exacta con
    //   `alcance.usable()`, y es lo que el comentario de [RegisteredStep] ya
    //   documenta: «el alcance esperado de TODOS los pasos es el mismo: el
    //   utilizable». El día que un paso pueda declarar que un sujeto no es su
    //   incumbencia, esta comprobación se afloja para permitir un subconjunto
    //   propio DECLARADO — no uno que se coló por no validarse.
    final utilizable = alcance.usable().toSet();
    for (final registro in this.registrados) {
      final enBlanco =
          registro.expectedScope.where((s) => s.trim().isEmpty).toList();
      if (enBlanco.isNotEmpty) {
        throw ArgumentError.value(
            registro.expectedScope,
            'registrados',
            'El paso «${registro.id}» espera un sujeto en blanco. Un sujeto '
                'en blanco no nombra nada, y el libro de obligaciones no le '
                'puede pedir cuenta de él a nadie.');
      }
      final esperado = registro.expectedScope.toSet();
      final excedentes = esperado.difference(utilizable);
      final faltantes = utilizable.difference(esperado);
      if (excedentes.isNotEmpty || faltantes.isNotEmpty) {
        throw ArgumentError.value(
            registro.expectedScope,
            'registrados',
            'El alcance esperado del paso «${registro.id}» no coincide con '
                'lo utilizable de esta corrida (${utilizable.join(", ")}).'
                '${excedentes.isEmpty ? '' : ' Espera sujetos que la '
                    'observación no dio como utilizables: '
                    '${excedentes.join(", ")}.'}'
                '${faltantes.isEmpty ? '' : ' No incluye sujetos utilizables '
                    'que esta corrida sí observó: ${faltantes.join(", ")}.'}'
                ' Sin aplicabilidad por paso todavía, el alcance esperado de '
                'todo paso registrado tiene que ser exactamente el '
                'utilizable: uno más chico deja obligaciones sin nombrar, y '
                'uno más grande fabrica obligaciones sobre algo que nadie '
                'observó.');
      }
    }

    // **Un desenlace tampoco es gratis contra la observación de esta
    // corrida.** `Skipped` y `Unobservable` validan su PROPIA forma —sus
    // constructores ya rechazan la lista vacía, y `Skipped` rechaza un
    // sujeto que el propio desenlace marca como del stack— pero ninguno de
    // los dos puede saber si lo que declara es lo que esta corrida
    // observó de verdad: eso solo lo tiene [alcance]. Mientras el único
    // productor de este tipo sea [Cascada.correr], la correspondencia sale
    // gratis. El día que alguien arme un [ResultadoDeCascada] por otro
    // lado —y la tarea siguiente lo va a hacer, para sus propiedades— un
    // `Skipped` con un sujeto ajeno inventado, o un `Unobservable` con una
    // causa inventada, hace `ejecutados` vacío y `causas` vacía a la vez:
    // verde sobre una corrida que no verificó nada. Es el mismo error que
    // el alcance esperado ya cerró más arriba, en la otra mitad del tipo.
    final ajenosDeLaObservacion = {
      for (final o in alcance.observed)
        if (!o.ofStack) o.subject,
    };
    final noObservadosDeLaObservacion = {
      for (final u in alcance.unobserved) u.subject,
    };
    for (final entrada in this.desenlaces.entries) {
      final d = entrada.value;
      if (d is Skipped) {
        final inventados = d.notOfStack
            .map((o) => o.subject)
            .where((s) => !ajenosDeLaObservacion.contains(s))
            .toList();
        if (inventados.isNotEmpty) {
          final reales = ajenosDeLaObservacion.isEmpty
              ? '(ninguno)'
              : ajenosDeLaObservacion.join(", ");
          throw ArgumentError.value(
              inventados,
              'desenlaces',
              'El paso «${entrada.key}» se saltó declarando ajenos a '
                  '${inventados.join(", ")}, pero la observación de esta '
                  'corrida no los tiene como ajenos al stack (los ajenos '
                  'reales son: $reales). Un salto no puede nombrar un sujeto '
                  'que esta corrida no observó como ajeno.');
        }
      } else if (d is Unobservable) {
        final inventados = d.causes
            .map((c) => c.subject)
            .where((s) => !noObservadosDeLaObservacion.contains(s))
            .toList();
        if (inventados.isNotEmpty) {
          final reales = noObservadosDeLaObservacion.isEmpty
              ? '(ninguno)'
              : noObservadosDeLaObservacion.join(", ");
          throw ArgumentError.value(
              inventados,
              'desenlaces',
              'El paso «${entrada.key}» declara no observable a '
                  '${inventados.join(", ")}, pero la observación de esta '
                  'corrida no los tiene como no observados (los no '
                  'observados reales son: $reales). Un desenlace no '
                  'observable no puede nombrar un sujeto que esta corrida sí '
                  'pudo observar.');
        }
      }
    }
  }

  /// Qué pasos ejecutaron de verdad, es decir, corrieron hasta el final.
  List<String> get ejecutados => List.unmodifiable([
        for (final e in desenlaces.entries)
          if (e.value is Executed) e.key
      ]);

  /// Todos los diagnósticos, en el orden en que los pasos los produjeron.
  List<Diagnostic> get diagnosticos => List.unmodifiable([
        for (final d in desenlaces.values)
          if (d is Executed) ...d.diagnostics,
      ]);

  /// **El libro.** Para cada paso registrado, cada sujeto de su alcance
  /// esperado tiene que estar cubierto por su testigo o nombrado por una de
  /// sus omisiones. Un paso que no ejecutó no tiene testigo del que leer
  /// cobertura, así que no puede saldar NADA de lo suyo: si su alcance
  /// esperado no está vacío, cada uno de sus sujetos queda abierto.
  ///
  /// **Es por PAR paso-sujeto, no por unión.** Que otro paso haya cubierto el
  /// sujeto no salda la obligación de este. La versión existencial —«algún
  /// paso cubrió cada sujeto»— dejaba pasar exactamente el caso que esta
  /// rebanada existe para cerrar: un paso que cubre la mitad del alcance
  /// mientras otro cubre todo, y la corrida sale verde sobre una obligación
  /// que ese primer paso nunca saldó.
  ///
  /// **Por tipo de desenlace, no por cobertura, era la misma puerta con otra
  /// forma.** La versión anterior saltaba entero todo desenlace que no fuera
  /// `Executed` —`if (desenlace is! Executed) continue`—, así que un paso
  /// saltado o no observable con alcance esperado NO VACÍO no contraía
  /// ninguna obligación: quedaba invisible para este libro exactamente igual
  /// que el paso tapado por otro que el párrafo de arriba existe para
  /// cerrar. Hoy no es alcanzable desde [Cascada.correr] —un `Skipped`/
  /// `Unobservable` solo sale cuando lo utilizable está vacío, y ahí el
  /// alcance esperado de todos los pasos también lo está— pero sí
  /// construyendo el resultado a mano, y el día que exista aplicabilidad por
  /// paso (ver el comentario de [RegisteredStep]) un paso podrá saltarse
  /// legítimamente CONVIVIENDO con un alcance esperado propio no vacío. La
  /// puerta se hubiera abierto sola.
  ///
  /// **El borde que sí sigue sin contraer nada: un alcance esperado VACÍO.**
  /// Un paso saltado o no observable sobre un alcance enteramente ajeno o
  /// enteramente no observado no tiene ningún sujeto propio del que dar
  /// cuenta —su `expectedScope` es `[]`— así que el `for` de abajo no agrega
  /// nada por él. Es el caso legítimo de «todo saltado» / «todo no
  /// observable» que ya prueban la suite de la cascada y este mismo archivo,
  /// y sigue exactamente igual: lo que cambió es qué pasa cuando el alcance
  /// esperado SÍ tiene algo y el paso, aun así, no ejecutó.
  List<Obligacion> get obligacionesSinSaldar {
    final abiertas = <Obligacion>[];
    for (final registro in registrados) {
      final desenlace = desenlaces[registro.id]!;
      final saldados = desenlace is Executed
          ? {
              ...desenlace.witness.subjects,
              for (final o in desenlace.witness.omitted)
                if (o.subject != null) o.subject!,
            }
          : const <String>{};
      for (final sujeto in registro.expectedScope) {
        if (!saldados.contains(sujeto)) {
          abiertas.add((paso: registro.id, sujeto: sujeto));
        }
      }
    }
    return List.unmodifiable(abiertas);
  }

  /// Las causas, en el orden del flujo de decisión. La acción siguiente sale
  /// de la primera, y por eso solo puede nombrar evidencia presente.
  ///
  /// **Regla de esta lista, para la próxima causa que se agregue: una causa
  /// solo se agrega si existe la evidencia que su acción va a nombrar.** No
  /// es una jerarquía por posición — es un catálogo de cosas que salieron
  /// mal, y reordenarlo apuesta a que la próxima combinación problemática
  /// involucre una causa que hoy está más abajo, sin nada que lo garantice
  /// según crezca el enum. La condición correcta ata el disparo al CONTENIDO
  /// que el texto de esa causa va a citar, no a su posición relativa a otra.
  ///
  /// Las otras cinco ya lo hacían así: `alcanceNoObservable` solo dispara si
  /// `alcance.unobserved` tiene algo; `pasoAbortado`, si hay un `Aborted`
  /// real; `pasoNoConcluyente`, si hay un `Executed` no concluyente real;
  /// `obligacionSinSaldar`, si el libro tiene una obligación real.
  /// `nadaEjecutado` era la excepción: su texto enumera los sujetos ajenos
  /// al stack, y disparaba con solo `ejecutados.isEmpty`, sin mirar si había
  /// alguno que nombrar. Con un alcance sano —todo de stack, nada
  /// inobservable— donde todos los pasos abortan, `ejecutados` también
  /// queda vacío, y esa causa nombraba una lista vacía: el error original
  /// exacto, con otra combinación. Un review lo encontró después de que
  /// reordenar la lista ya había tapado la combinación anterior sin cerrar
  /// la clase de bug.
  List<CausaNoConcluyente> get causas {
    final c = <CausaNoConcluyente>[];
    if (registrados.isEmpty) c.add(CausaNoConcluyente.sinVerificadores);
    if (alcance.unobserved.isNotEmpty) {
      c.add(CausaNoConcluyente.alcanceNoObservable);
    }
    // **Solo si hay al menos un ajeno que nombrar.** Sin este `&&`, «nada
    // ejecutó» disparaba también cuando la razón real era que todo abortó,
    // no observó o se rompió sobre un alcance perfectamente sano — y su
    // texto habría enumerado una lista vacía. Que quede vacía la lista de
    // causas enteras no es un riesgo acá: si nada ejecutó y no hay ningún
    // ajeno, ningún paso pudo haber sido saltado (`Skipped` exige al menos
    // un sujeto ajeno para construirse), así que todos abortaron, no
    // observaron o se rompieron — y cada uno de esos dispara su propia
    // causa más abajo.
    final hayAjenos = alcance.observed.any((o) => !o.ofStack);
    if (ejecutados.isEmpty && registrados.isNotEmpty && hayAjenos) {
      c.add(CausaNoConcluyente.nadaEjecutado);
    }
    if (desenlaces.values.any((d) => d is Aborted)) {
      c.add(CausaNoConcluyente.pasoAbortado);
    }
    if (desenlaces.values
        .any((d) => d is Executed && d.verdict == Verdict.noConcluyente)) {
      c.add(CausaNoConcluyente.pasoNoConcluyente);
    }
    if (obligacionesSinSaldar.isNotEmpty) {
      c.add(CausaNoConcluyente.obligacionSinSaldar);
    }
    return List.unmodifiable(c);
  }

  /// **No hay rama por defecto.** El verde es la hoja que queda cuando todas
  /// las preguntas negativas se contestaron que no.
  EstadoDeCorrida get estado {
    if (desenlaces.values.any((d) => d is Broken)) {
      return EstadoDeCorrida.errorInterno;
    }
    if (causas.isNotEmpty) return EstadoDeCorrida.noConcluyente;
    if (desenlaces.values
        .any((d) => d is Executed && d.verdict == Verdict.rojo)) {
      return EstadoDeCorrida.rojo;
    }
    return EstadoDeCorrida.verde;
  }
}

/// Un registro ordenado de pasos.
///
/// El orden es de costo creciente y lo decide quien compone. **No hay corte
/// temprano todavía**: todos los pasos corren. `D-099` lo congeló — aparece dos
/// veces en el corpus y ninguna dice **cuándo** corta—, y su precondición sí
/// está: un paso que no ejecuta y no es una falla.
///
/// **El orden no está «medido», aunque `D-050` lo pida.** Los tiempos salen de
/// la línea base A0, que el plan declara fuera de alcance; se declara a mano y
/// queda dicho (`D-100`).
class Cascada {
  final List<Verifier> pasos;

  /// Quién mira el alcance. **No lo mira ningún paso**: ADR-011 corolario 4,
  /// y por eso es la cascada —no `Verifier`— quien lo consulta.
  final ScopeObserver observador;

  Cascada(List<Verifier> pasos, {required this.observador})
      : pasos = List.unmodifiable(pasos) {
    // **El id de un paso es una CLAVE**, no una etiqueta: es con lo que se
    // arma el libro de obligaciones y se comparan registrados contra
    // ejecutados. Dos pasos con el mismo id dejarían esa cuenta ciega —uno
    // taparía al otro— y un paso podría no correr sin que nada lo note.
    //
    // Es la misma lección que el motor de checks aprendió con las clases
    // homónimas de `core`, y por eso se rechaza al construir en vez de
    // esperar a que alguien se acuerde.
    final vistos = <String>{};
    for (final p in this.pasos) {
      if (p.id.trim().isEmpty) {
        throw const CascadaNoRegistrable(
            'Hay un paso sin id. El id es con lo que se comprueba que el paso '
            'corrió: sin él no se puede saber si faltó.');
      }
      if (!vistos.add(p.id)) {
        throw CascadaNoRegistrable(
            'El id «${p.id}» está registrado más de una vez. Se comparan '
            'registrados contra ejecutados por id, así que uno taparía al otro '
            'y un paso podría no correr sin que nadie se entere.');
      }
    }
  }

  /// Los ids registrados, en orden. **Sin alcance**: eso solo se sabe al
  /// correr, y de ahí sale [ResultadoDeCascada.registrados].
  List<String> get registrados =>
      List.unmodifiable([for (final p in pasos) p.id]);

  /// Corre todos los pasos y devuelve lo que resultó.
  ///
  /// **[alEmpezar] y [alTerminar] se llaman mientras la corrida ocurre**, no
  /// después. La primera versión devolvía todo junto y el CLI recorría los
  /// resultados al final: no había nada que mirar mientras una herramienta
  /// tardaba, y los eventos llevaban la hora de cuando se armó el reporte, no
  /// la del paso. La superficie pide que una operación de más de tres segundos
  /// muestre el paso en curso, y eso no se puede hacer desde el final.
  Future<ResultadoDeCascada> correr(
    List<String> sujetos, {
    void Function(String id)? alEmpezar,
    void Function(String id, StepOutcome desenlace)? alTerminar,
  }) async {
    // **Un alcance pedido vacío es precondición violada, no un desenlace.**
    // Se rechaza ACÁ, antes de llamar al observador y sin condicionar al
    // registro: verificar nada no es ni verde ni no concluyente, es un error
    // de quien llama, igual que un alcance sin sujetos utilizables lo es para
    // un paso (`PasoDeCascada.run` ya lo rechaza así, un nivel más abajo). Sin
    // esto había una asimetría: con pasos registrados, la nada escapaba como
    // una excepción de OTRO tipo —el invariante de `Skipped`, que no le habla
    // a quien llamó—, y con el registro vacío ni siquiera eso: devolvía un
    // resultado no concluyente en silencio.
    //
    // **No es el contrato del observador lo que cambia.** `ScopeObserver`
    // sabe particionar la nada —una lista vacía es una partición válida de sí
    // misma— y eso sigue valiendo: acá no se lo llama, así que no se le pide
    // que decida nada.
    if (sujetos.isEmpty) {
      throw ArgumentError.value(
          sujetos,
          'sujetos',
          'No hay ningún sujeto para verificar. Correr una cascada sobre una '
              'lista de sujetos vacía no es un desenlace de nadie: es una '
              'precondición violada de quien llama.');
    }

    // **Se congela al entrar.** La lista es del llamador, que puede mutarla
    // mientras la corrida está en curso.
    final alcance = List<String>.unmodifiable(sujetos);

    // **Una sola foto para toda la corrida, y ahora de verdad.** Dos lecturas
    // pueden diferir, y entonces dos pasos verifican alcances distintos que
    // el reporte declara iguales: es la cláusula 4 del contrato de
    // `ScopeObserver`.
    //
    // Este comentario decía «de ESTE lado» y confesaba que cada paso volvía a
    // observar por su cuenta, apoyándose en que el paso abortaba si su
    // lectura discrepaba. Esa salvaguarda comparaba nombres y no tamaños, así
    // que no salvaba nada. Se cerró donde correspondía: `Verifier.run` recibe
    // esta observación y ningún paso tiene con qué pedir otra, así que la
    // línea de abajo es la única lectura del árbol en toda la corrida por
    // construcción y no por disciplina.
    final observacion = await observador.observe(alcance);
    final utilizables = observacion.usable();
    final ajenos = [
      for (final o in observacion.observed)
        if (!o.ofStack) o
    ];

    // **Se arma acá, no al componer el registro.** Recién ahora hay una
    // observación de la que sacar el alcance esperado. Hoy es el mismo para
    // todos los pasos: el utilizable de la corrida entera.
    final registrados = [
      for (final paso in pasos)
        RegisteredStep(id: paso.id, expectedScope: utilizables),
    ];

    final desenlaces = <String, StepOutcome>{};

    for (final paso in pasos) {
      alEmpezar?.call(paso.id);
      // No `final`: el analizador no infiere asignación única a través de un
      // `try`/`catch` anidado en una rama de `if`. La garantía de que las dos
      // ramas asignan exactamente una vez la sostienen las pruebas, no el
      // compilador.
      StepOutcome desenlace;
      if (utilizables.isEmpty) {
        // **No pude mirar gana sobre no había nada mío.** Para afirmar que no
        // había nada hay que haber podido mirar todo: un sujeto que no se
        // pudo observar puede resultar del stack, y entonces «ninguno era
        // mío» sería un hecho que nadie comprobó.
        desenlace = observacion.unobserved.isNotEmpty
            ? Unobservable(causes: observacion.unobserved)
            : Skipped(notOfStack: ajenos);
      } else {
        try {
          desenlace = await paso.run(observacion);
        } on Object catch (e) {
          // Se atrapa cualquier excepción a propósito, y solo acá: un paso
          // que se rompe es un error del arnés, no un veredicto sobre el
          // cambio.
          desenlace = Broken(
              component: paso.id,
              error: '$e',
              context: 'alcance: $utilizables');
        }
      }
      desenlaces[paso.id] = desenlace;
      // Fuera del `try`: una excepción del observador de progreso es del
      // arnés, no del verificador que hizo su trabajo.
      alTerminar?.call(paso.id, desenlace);
    }

    return ResultadoDeCascada(
      registrados: registrados,
      alcance: observacion,
      desenlaces: desenlaces,
    );
  }
}
