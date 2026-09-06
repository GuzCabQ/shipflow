/// El comando `verify`: corre la cascada sobre un alcance y reporta.
///
/// **Es el composition root de la cascada.** Acá y solo acá se sabe qué pasos
/// existen: `orchestration` los recibe como `Verifier` y no puede ver ningún
/// plugin. Cambiar de stack cambia esta lista y nada más.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_dart/plugin_dart.dart';

import 'salida.dart';
import 'uso.dart';

const nombreDelComando = 'verify';

/// Los pasos, en orden de costo creciente.
///
/// **El orden es política de quien compone**, no del plugin. Formatear es más
/// barato que analizar, así que va primero — pero los dos corren igual: no hay
/// corte temprano todavía, y su ausencia está declarada en `orchestration`.
///
/// **Hueco declarado:** `docs/03` §6 le asigna el orden a `orchestration`, y
/// hoy vive acá como una lista literal. Para derivarlo allá haría falta que
/// `Verifier` declare su costo, y ese campo no existe. Se cierra cuando el
/// costo importe, no antes.
Cascada cascadaPorDefecto({
  required String directorio,
  EjecutorDeProceso ejecutor = const EjecutorDelSistema(),
  ScopeObserver? observador,
  Duration presupuesto = const Duration(minutes: 5),
}) {
  final obs = observador ?? ObservadorDeAlcanceDart(directorio: directorio);
  return Cascada([
    PasoDeFormato(
        ejecutor: ejecutor,
        directorio: directorio,
        observador: obs,
        presupuesto: presupuesto),
    PasoDeAnalisis(
        ejecutor: ejecutor,
        directorio: directorio,
        observador: obs,
        presupuesto: presupuesto),
  ], observador: obs);
}

/// Lo que `verify` entendió de la línea de comandos.
///
/// **No interpreta banderas**: eso ya lo hizo la frontera, una sola vez. Acá
/// solo se resuelve el alcance y se rechaza lo que ningún subcomando puede
/// aceptar. Dos intérpretes para las mismas banderas fue lo que dejó la
/// frontera aceptando `--inventada`.
class OpcionesDeVerify {
  final List<String> sujetos;
  final bool json;
  final bool silencioso;
  final bool detallado;
  final bool ayuda;

  OpcionesDeVerify({
    required List<String> sujetos,
    this.json = false,
    this.silencioso = false,
    this.detallado = false,
    this.ayuda = false,
  }) : sujetos = List.unmodifiable(sujetos);
}

const ayudaDeVerify = r'''
shipflow verify [rutas...] — corre la cascada y reporta con testigo.

  --json        Protocolo de salida: eventos y resultado en JSON Lines por la
                salida estándar, incluidos los diagnósticos.
  --verbose     Incluye el testigo de cada paso: qué corrió, sobre qué, y qué
                omitió.
  --quiet, -q   Solo errores: lo que bloquea.
  --help, -h    Esto.

Sin rutas, el alcance es el directorio actual.''';

/// Resuelve el alcance a partir de lo que la frontera ya interpretó.
///
/// **`verify` no tiene banderas propias**, así que cualquier bandera que haya
/// sobrado no la puede aceptar nadie.
OpcionesDeVerify opcionesDe(Globales g) {
  final sobrante = g.restantes.where((a) => a.startsWith('-')).toList();
  if (sobrante.isNotEmpty) {
    throw UsoInvalido('bandera desconocida: «${sobrante.first}»',
        'Corré `shipflow verify --help` para ver las que hay.');
  }
  final sujetos = g.restantes.where((a) => !a.startsWith('-')).toList();

  // **Sin alcance explícito, el directorio actual.** No es un default cómodo:
  // es el único alcance que se puede nombrar sin adivinar, y de todos modos el
  // testigo va a decir qué cubrió de verdad.
  return OpcionesDeVerify(
    sujetos: sujetos.isEmpty ? const ['.'] : sujetos,
    json: g.json,
    silencioso: g.silencioso,
    detallado: g.detallado,
    ayuda: g.ayuda,
  );
}

/// Corre `verify` y devuelve el código de proceso.
///
/// **Recibe la impresora**, no la construye: la frontera es una sola y vive en
/// `comando.dart`. Las excepciones tampoco se atrapan acá — suben a esa
/// frontera, que es la que sabe convertirlas en un `70` con su resultado.
Future<int> correrVerify(
  Globales globales, {
  required String directorio,
  required Impresora impresora,
  Cascada Function(String directorio)? construirCascada,
  void Function(String id, StepOutcome desenlace)? alTerminarDeProgreso,
}) async {
  final OpcionesDeVerify o;
  try {
    o = opcionesDe(globales);
  } on UsoInvalido catch (e) {
    impresora.resultado(
      ResultEnvelope(
        command: nombreDelComando,
        exitCode: Codigo.errorDeUso,
        verdict: null,
        nextAction: e.queHacer,
        data: {'error': e.reason},
      ),
      'shipflow verify: ${e.reason}\n  → ${e.queHacer}',
    );
    impresora.cerrar();
    return Codigo.errorDeUso;
  }

  if (o.ayuda) {
    // La ayuda gana sobre `--quiet`, igual que en la frontera: si alguien la
    // pidió, callarla es no hacer lo que se pidió. Y se CIERRA la misma que
    // emitió — cerrar la otra dejaba el resultado emitido en una y la cuenta
    // en cero en la otra, que es justamente lo que el guardia detecta.
    final sinSilencio = Impresora(
        salida: impresora.salida, error: impresora.error, json: o.json);
    sinSilencio.resultado(
      ResultEnvelope(
        command: nombreDelComando,
        exitCode: Codigo.exito,
        verdict: 'ok',
        data: const {'help': ayudaDeVerify},
      ),
      ayudaDeVerify,
    );
    sinSilencio.cerrar();
    return Codigo.exito;
  }

  final imp = impresora;

  final cascada =
      (construirCascada ?? (d) => cascadaPorDefecto(directorio: d))(directorio);

  // **Identifica esta corrida.** Nulo hasta acá: ni el error de uso ni la
  // ayuda llegaron a componer una cascada, así que no había nada que
  // correlacionar.
  final runId = generarRunId();

  // **Ningún desenlace queda sin declarar, ni siquiera cuando el canal se
  // rompe.** `alTerminar` imprime el progreso y compone el observador externo
  // que el llamador haya dado —existe solo para poder romper el canal a
  // propósito en una prueba—. Si cualquiera de los dos lanza, el paso YA
  // corrió y su desenlace es real: perderlo del todo sería peor que avisar
  // que su entrega falló. Se registra el id y se sigue, en vez de dejar que
  // la excepción tire abajo el resto de la corrida.
  final sinTerminalEntregado = <String>[];

  // **Los eventos salen mientras la corrida ocurre**, no al final. Antes se
  // recorrían los resultados después de que todo había terminado: no había
  // nada que mirar mientras una herramienta tardaba, y la marca de tiempo era
  // la de armar el reporte y no la del paso.
  final r = await cascada.correr(
    o.sujetos,
    alEmpezar: (id) => imp.evento(
      EventEnvelope(
        command: nombreDelComando,
        type: 'progress',
        runId: runId,
        data: {'verifier': id, 'stage': 'started'},
      ),
      '  ...       $id',
    ),
    alTerminar: (id, desenlace) {
      try {
        // **Cada uno de los cinco desenlaces se dice como lo que es.** Antes
        // solo se avisaba de los pasos con resultado, así que un salto y un
        // fallo interno dejaban su `started` sin cerrar.
        imp.evento(
          EventEnvelope(
            command: nombreDelComando,
            type: 'progress',
            runId: runId,
            data: {
              'verifier': id,
              'stage': _etapaDe(desenlace),
              ...desenlace.toJson(),
            },
          ),
          _desenlaceEnTexto(id, desenlace, detallado: o.detallado),
        );
        final diagnosticos = switch (desenlace) {
          Executed(:final diagnostics) => diagnostics,
          _ => const <Diagnostic>[],
        };
        for (final d in diagnosticos
            .where((d) => seMuestra(d, silencioso: o.silencioso))) {
          imp.evento(
            EventEnvelope(
                command: nombreDelComando,
                type: 'diagnostic',
                runId: runId,
                data: d.toJson()),
            '  ${d.severity.name} ${d.file}${d.line == null ? '' : ':${d.line}'} '
            '· ${d.ruleId} · ${d.message.content}',
          );
        }
        alTerminarDeProgreso?.call(id, desenlace);
      } on Object {
        sinTerminalEntregado.add(id);
      }
    },
  );

  final huboFalloDeEntrega = sinTerminalEntregado.isNotEmpty;
  final estado = r.estado;
  final exitCode =
      huboFalloDeEntrega ? Codigo.errorInterno : Codigo.deCorrida(estado);
  final verdict = huboFalloDeEntrega
      ? veredictoDe(EstadoDeCorrida.errorInterno)
      : veredictoDe(estado);
  final accion = huboFalloDeEntrega
      ? 'El canal de progreso se rompió antes de entregar el desenlace final '
          'de estos pasos: ${sinTerminalEntregado.join(", ")}. La cascada sí '
          'terminó de correr: `outcomes`, en este mismo documento, tiene lo '
          'que cada uno produjo.'
      : _queHacer(r);

  imp.resultado(
    ResultEnvelope(
      command: nombreDelComando,
      exitCode: exitCode,
      verdict: verdict,
      nextAction: accion,
      runId: runId,
      data: {
        // **Ya no es una lista de ids.** Cada paso registrado trae el
        // alcance que se esperaba que cubriera, y sin eso el libro de
        // obligaciones que sigue no se podría leer desde este documento.
        'registered': [
          for (final reg in r.registrados)
            {'id': reg.id, 'expectedScope': reg.expectedScope},
        ],
        'executed': r.ejecutados,
        // **Conteo, no la lista.** Cada diagnóstico ya viajó en su propio
        // evento mientras la corrida ocurría; repetirlo acá sería carga
        // redundante. Lo que necesita ser verificable desde este documento
        // es la CANTIDAD que cita `nextAction`, y para eso alcanza con los
        // dos números.
        'diagnostics': r.diagnosticos.length,
        'blockingDiagnostics':
            r.diagnosticos.where((d) => d.severity == Severity.bloquea).length,
        // **La causa estructurada, no solo su texto.** Es lo que permite que
        // `nextAction` nombre evidencia y que quien lo consuma no tenga que
        // volver a correr nada para confirmarla.
        'inconclusiveBecause': [for (final c in r.causas) c.name],
        'obligations': [
          for (final ob in r.obligacionesSinSaldar)
            {'step': ob.paso, 'subject': ob.sujeto},
        ],
        // **El libro completo, por paso.** Un `Attempt` roto, un testigo
        // ciego o un paso `Broken` viven acá con todos sus campos: es de
        // donde `nextAction` saca lo que nombra, y de donde lo puede leer
        // cualquiera que quiera comprobarlo sin correr nada de nuevo.
        'outcomes': {
          for (final e in r.desenlaces.entries) e.key: e.value.toJson(),
        },
        // **La foto del alcance, completa.** Es de donde `nextAction` saca
        // lo ajeno y lo no observable: sin esto, esas dos ramas nombrarían
        // algo que este documento no contiene.
        'scope': r.alcance.toJson(),
        if (huboFalloDeEntrega) 'unterminated': sinTerminalEntregado,
      },
    ),
    _resumenEnTexto(r, accion),
  );
  imp.cerrar();

  return exitCode;
}

/// Qué diagnósticos se muestran. **La decisión es de la severidad, no del tipo
/// de evento.**
///
/// `Severity.silencia` dice de sí misma «registra para telemetría y no se
/// muestra»: no se imprime nunca, ni siquiera sin banderas. Y `--quiet` dice
/// «solo errores», así que deja pasar lo que bloquea y nada más — mostraba lo
/// informativo, y también lo silenciado.
bool seMuestra(Diagnostic d, {required bool silencioso}) =>
    d.severity != Severity.silencia &&
    (!silencioso || d.severity == Severity.bloquea);

/// La etapa del protocolo que le corresponde a cada uno de los cinco
/// desenlaces. **El `switch` es exhaustivo**: un sexto desenlace no compila
/// hasta que alguien le decida su etapa acá.
String _etapaDe(StepOutcome d) => switch (d) {
      Executed() => 'executed',
      Aborted() => 'aborted',
      Skipped() => 'skipped',
      Unobservable() => 'unobservable',
      Broken() => 'internalError',
    };

/// El desenlace de un paso, en texto. **Los cinco se dicen distinto**: un
/// salto que se imprimiera como un veredicto sería exactamente la confusión
/// que el tipo vino a deshacer.
String _desenlaceEnTexto(String id, StepOutcome d, {required bool detallado}) =>
    switch (d) {
      Executed() => _ejecutadoEnTexto(id, d, detallado: detallado),
      Aborted(:final attempt) => [
          '  ABORTADO $id',
          if (detallado) '            ${attempt.note}',
        ].join('\n'),
      Skipped(:final notOfStack) => [
          '  SALTADO   $id',
          if (detallado)
            for (final o in notOfStack)
              '            ajeno: ${o.subject} (${o.reason})',
        ].join('\n'),
      Unobservable(:final causes) => [
          '  NO OBS.   $id',
          if (detallado)
            for (final c in causes) '            ${c.subject}: ${c.cause}',
        ].join('\n'),
      Broken(:final component, :final error) => [
          '  ROTO      $id',
          '            $component: $error',
        ].join('\n'),
    };

String _ejecutadoEnTexto(String id, Executed e, {required bool detallado}) {
  final marca = switch (e.verdict) {
    Verdict.verde => 'ok        ',
    Verdict.rojo => 'FALLA     ',
    Verdict.noConcluyente => 'NO CONCL. ',
  };
  final linea = '  $marca$id';
  if (!detallado) return linea;
  final w = e.witness;
  return [
    linea,
    '            invocación: ${w.invocation}',
    '            cubrió: ${w.subjects.isEmpty ? "(nada)" : w.subjects.join(", ")}',
    for (final o in w.omitted)
      '            omitió: ${o.subject == null ? '' : '${o.subject}: '}'
          '${o.reason}',
  ].join('\n');
}

/// **Toda salida que no sea verde dice qué hacer.** Es lo mismo que INV-8 le
/// exige a una regla que bloquea: detener sin poder decir qué hacer deja a
/// quien lo choca sin salida.
///
/// **El error interno se atiende ANTES que las causas.** Con
/// [EstadoDeCorrida.errorInterno] la lista de causas puede venir no vacía —un
/// paso roto no impide que otro haya quedado no concluyente— y leer la
/// primera causa en ese caso hablaría de otra cosa que la que de verdad
/// interrumpió la corrida: el arnés, no la verificación del cambio.
String? _queHacer(ResultadoDeCascada r) {
  if (r.estado == EstadoDeCorrida.verde) return null;

  if (r.estado == EstadoDeCorrida.errorInterno) {
    final rotos = [
      for (final e in r.desenlaces.entries)
        if (e.value is Broken) e.key,
    ];
    return 'Se rompió un paso del arnés, no la verificación del cambio. '
        'Reportalo con la traza: ${rotos.join(", ")}.';
  }

  // **Rojo, o no concluyente: la acción sale de la primera causa.** El rojo
  // sin causas concurrentes no tiene ninguna que leer —`causas` viene vacía—
  // y por eso el `null` del `switch` es también su rama. `causas` viene en
  // el orden del flujo de decisión, así que solo puede nombrar evidencia
  // presente.
  final causa = r.causas.isEmpty ? null : r.causas.first;
  return switch (causa) {
    null => 'Hay '
        '${r.diagnosticos.where((d) => d.severity == Severity.bloquea).length} '
        'diagnóstico(s) bloqueante(s). Arreglalos y volvé a correr `verify`.',
    CausaNoConcluyente.sinVerificadores =>
      'No hay ningún verificador registrado, así que no se miró nada. Los '
          'pasos se registran en el composition root: `cli`.',
    // **Si `alcanceNoObservable` no ganó ya más arriba, acá SIEMPRE hay
    // algún ajeno que nombrar.** `causas` pone lo no observable antes que
    // nada ejecutado (ver su comentario en `cascada.dart`): que
    // `nadaEjecutado` sea la primera causa significa que no hubo ningún
    // sujeto inobservable, y sin utilizables ni inobservables lo único que
    // puede haber dejado al alcance vacío es que todo lo pedido resultó
    // ajeno al stack.
    CausaNoConcluyente.nadaEjecutado =>
      'Ningún sujeto del alcance es de este stack: '
          '${r.alcance.observed.where((o) => !o.ofStack).map((o) => o.subject).join(", ")}. '
          'No es un fallo, pero tampoco se verificó nada. Revisá el alcance.',
    CausaNoConcluyente.alcanceNoObservable => _accionDeAlcanceNoObservable(r),
    CausaNoConcluyente.pasoAbortado => _accionDeAborto(r),
    CausaNoConcluyente.pasoNoConcluyente => _accionDeNoConcluyente(r),
    CausaNoConcluyente.obligacionSinSaldar => () {
        final ob = r.obligacionesSinSaldar.first;
        return '${ob.paso} no cubrió ${ob.sujeto} y no dijo por qué. Un '
            'sujeto que nadie miró no puede quedar en verde.';
      }(),
  };
}

String _accionDeAlcanceNoObservable(ResultadoDeCascada r) =>
    'No se pudo observar '
    '${r.alcance.unobserved.map((u) => '${u.subject}: ${u.cause}').join('; ')}. '
    'Corregí la ruta o los permisos y volvé a correr.';

/// Nombra el paso abortado y **la nota de su propio `Attempt`**: es lo que
/// hace que la acción no pueda nombrar algo ausente, porque sale del
/// desenlace y no de una constante.
String _accionDeAborto(ResultadoDeCascada r) {
  final entrada = r.desenlaces.entries.firstWhere((e) => e.value is Aborted);
  final abortado = entrada.value as Aborted;
  return '${entrada.key} no llegó a terminar: ${abortado.attempt.note} '
      'Revisá eso antes de volver a correr `verify`.';
}

/// Nombra el paso no concluyente y **el primer motivo de su propio testigo**.
String _accionDeNoConcluyente(ResultadoDeCascada r) {
  final entrada = r.desenlaces.entries.firstWhere((e) =>
      e.value is Executed &&
      (e.value as Executed).verdict == Verdict.noConcluyente);
  final ejecutado = entrada.value as Executed;
  final motivo = ejecutado.witness.omitted.first.reason;
  return '${entrada.key} no pudo concluir: $motivo Revisá eso antes de '
      'volver a correr `verify`.';
}

String _resumenEnTexto(ResultadoDeCascada r, String? accion) {
  final estado = r.estado;
  final cabeza = 'verify: ${veredictoDe(estado)} — '
      '${r.ejecutados.length} de ${r.registrados.length} pasos ejecutados, '
      '${r.diagnosticos.length} diagnóstico(s).';
  return accion == null ? cabeza : '$cabeza\n  → $accion';
}
