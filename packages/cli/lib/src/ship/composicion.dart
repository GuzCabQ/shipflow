/// El comando `ship`: **qué se compone**, por dónde sale cada texto, y con qué
/// código termina el proceso.
///
/// **Es el composition root de la corrida**, igual que el archivo de `verify`
/// lo es de la cascada. Acá y solo acá se sabe qué repositorio, qué entorno de
/// verificación, qué política de artefactos y qué forja existen: `correrShip`
/// recibe puertos y no puede ver ninguno de esos nombres. Cambiar de stack, de
/// repositorio o de forja cambia este archivo y nada más.
///
/// **Y acá se atrapan las cuatro excepciones que no son desenlace.** El doc de
/// `correrShip` las declara y dice que es el comando quien las traduce a código
/// de proceso; esa traducción vive en este archivo y en ningún otro, porque
/// decidir el código dos veces es cómo dos sitios terminan contestando distinto
/// sobre la misma corrida.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:path/path.dart' as rutas;
import 'package:plugin_dart/plugin_dart.dart';
import 'package:vcs/vcs.dart';

import '../corrida.dart';
import '../credenciales.dart';
import '../salida.dart';
import '../uso.dart';
import '../verify.dart';
import 'entrada.dart';
import 'gitignore.dart';
import 'ship.dart';

const nombreDeShip = 'ship';

/// El tipo del evento con el que viaja la previsualización.
///
/// **No es `progress`, y la diferencia es de comportamiento.** `--quiet` calla
/// el progreso —lo dice la impresora— y la previsualización es exactamente
/// aquello sobre lo que una persona decide: callarla dejaría a quien confirma
/// autorizando una escritura que no vio. Y va por el canal de eventos y no por
/// la salida cruda porque los eventos ya son ANTES del resultado, ya respetan
/// `--json` y ya prohíben emitir después del resultado — que es justo el orden
/// que el preview necesita.
const tipoDeEventoDePrevisualizacion = 'preview';

/// El tipo del evento con el que viaja la pregunta de confirmación.
const tipoDeEventoDeConfirmacion = 'confirmation';

const ayudaDeShip = r'''
shipflow ship — prepara un candidato, lo verifica sobre él, lo commitea y abre
el pull request. Cada camino termina en un desenlace declarado.

  --intent <texto>    Qué va a decir el pull request. Obligatorio con --file.
  --file <ruta>       Un archivo de la rebanada; se repite. `ship` NO infiere
                      el árbol de trabajo: los archivos se declaran.
  --slice <ruta>      Una rebanada ya declarada en un archivo. Excluyente con
                      --file, y trae su propia intención.
  --branch <rama>     Aserción, no cambio: tiene que coincidir con la actual.
  --base <rama>       Contra qué rama se abre el pull request.
  --dry-run           Solo la previsualización. Cero efectos persistentes.
  --yes               Autoriza a ESCRIBIR. No autoriza a publicar algo que no
                      concluyó: eso es --allow-incomplete.
  --allow-incomplete  Publica con la verificación en rojo o no concluyente. No
                      la declara verde.
  --help, -h          Esto.

Sin una terminal con quien hablar, la corrida se comporta como una
previsualización: no se pregunta nada y no se escribe nada.

Códigos: 0 verde · 1 diagnósticos bloqueantes · 2 no concluyente ·
         3 detención declarada · 4 falta configuración o credencial ·
         5 error de uso · 6 entrega incompleta · 70 error interno del arnés.''';

/// Los colaboradores de una corrida de `ship`, ya elegidos.
///
/// **Existe para que la elección sea un valor y no una lista de parámetros.**
/// `correrShip` recibe trece colaboradores; pasarlos de a uno por la frontera
/// obligaría a que el despachador —que no compone nada— los nombrara todos, y
/// a que cada prueba que quiera cambiar uno los repita. Acá se arman juntos y
/// se reemplazan juntos.
///
/// **No incluye `mostrar` ni `confirmar`, y esa ausencia es deliberada.** Los
/// dos son canales de SALIDA, y la salida tiene una sola frontera: la arma el
/// comando con la impresora que recibió. Dejarlos inyectables permitiría que
/// una prueba observara un canal que no es el que corre de verdad, que es
/// exactamente el falso verde que la frontera única existe para cerrar. Lo que
/// sí se inyecta es [responder]: el HECHO de si hay alguien que pueda
/// contestar, que es una pregunta sobre el mundo y no sobre el protocolo.
class ColaboradoresDeShip {
  final RepositorioGit repo;
  final VerificationEnvironment ambiente;
  final Cascada Function(String raiz) construirCascada;

  /// Los controles por id, para que la superficie pueda citar la afirmación de
  /// cada uno. **Se arman del mismo registro que la cascada**, no de una lista
  /// aparte: un id registrado sin control acá hace lanzar a `derivarSuperficie`,
  /// y con razón.
  final Map<String, Verifier> controles;

  final CredentialSource credenciales;
  final String claveDeCredencial;

  /// Por dónde sale el pull request, o **nulo cuando no hay forja compuesta**.
  ///
  /// Nulo es un hecho del entorno, no un descuido: hoy este repositorio no
  /// tiene ninguna superficie —ni archivo de configuración, ni bandera, ni
  /// clave de entorno declarada— por donde decir de qué remoto se trata, así
  /// que la raíz de composición no puede armar el adapter sin inventarle un
  /// destino. Un doble que devolviera un desenlace remoto fabricado sería el
  /// falso verde exacto; por eso se declara la ausencia y el comando la
  /// convierte en `4` — falta configuración, cero escrituras — en cuanto la
  /// corrida PODRÍA publicar.
  final PullRequestSink? forja;

  final RegistroDeCorridas registro;

  /// Las rutas sucias que no son de la rebanada. **Recibe los archivos
  /// declarados** porque «ajeno» se define contra ellos, y quien los conoce es
  /// la entrada ya interpretada, no esta composición.
  final Future<List<String>> Function(List<String> deLaRebanada) cambiosAjenos;

  /// Cómo se obtiene un sí o un no de quien corre, o **nulo cuando no hay con
  /// quién hablar**. Ver [responderDeLaTerminal].
  final Future<bool> Function(String pregunta)? responder;

  /// Cómo se lee el archivo de `--slice`. Es la única forma en que la
  /// resolución de la rebanada toca el disco, y por eso viaja como
  /// colaborador: una prueba que la reemplace no monta nada.
  final Future<String> Function(String ruta) leerArchivo;

  /// Quién asigna la identidad de la corrida.
  ///
  /// **Es una decisión de composición, no un detalle del comando.** El
  /// identificador nombra rutas en el disco —el documento de la corrida y su
  /// proyección— y viaja adentro del marcador del pull request; quién lo emite
  /// pertenece al mismo lugar donde se decide qué repositorio y qué registro
  /// hay. Que se pueda reemplazar es lo que permite fijar un caso donde la
  /// ruta del documento tiene que ser conocida de antemano.
  final String Function() nuevoRunId;

  final String? baseConfigurada;
  final String? baseDeLaForja;

  const ColaboradoresDeShip({
    required this.repo,
    required this.ambiente,
    required this.construirCascada,
    required this.controles,
    required this.credenciales,
    required this.registro,
    required this.cambiosAjenos,
    required this.leerArchivo,
    this.claveDeCredencial = claveDeCredencialDeLaForja,
    this.nuevoRunId = generarRunId,
    this.forja,
    this.responder,
    this.baseConfigurada,
    this.baseDeLaForja,
  });
}

/// La composición real: los adapters que existen de verdad, sobre [directorio].
///
/// **`baseConfigurada` y `baseDeLaForja` van nulas, y eso no es un olvido.** Las
/// tres fuentes de la base son explícita, configuración y rama por defecto de
/// la forja; hoy no hay ni una superficie de configuración ni una forja a la
/// que preguntarle, así que la única fuente viva es `--base`. Rellenarlas con
/// un valor cómodo —`main`— sería adivinar la base, que es justo lo que la
/// causa `baseIndeterminada` del preflight existe para nombrar.
///
/// **Residuo declarado: ninguna prueba mide que ESTA función arme los
/// adapters de verdad.** Bajo la suite, la única invocación que llega hasta
/// acá es la del comando sin argumentos, y esa sale por error de uso —dentro
/// de `resolverRebanada`— antes de que ninguno de los cinco colaboradores que
/// se arman acá se llegue a usar. La prueba del «comando hueco», en la suite
/// del comando, mide algo real pero distinto: que
/// `correrShipDelComando` no ignora los colaboradores que recibe. No mide que
/// esta función, la que los construye, los construya contra el mundo real —
/// reemplazar cualquiera de los cinco por un doble no pone roja ninguna
/// prueba hoy. Cerrarlo pediría un proceso de verdad corriendo contra un
/// repositorio real sin que el binario de prueba lo intercepte, que ninguna
/// otra parte de esta suite hace; queda como residuo, con la misma
/// honestidad que los cuatro de más arriba.
ColaboradoresDeShip colaboradoresDelSistema(String directorio, Globales g) {
  final entorno = EntornoDelProceso(Platform.environment);
  // Los controles salen de una cascada armada sobre el directorio del usuario y
  // la que corre se arma sobre la raíz del candidato. **No son la misma
  // instancia y no hace falta que lo sean**: de acá solo se leen el id y la
  // afirmación de cada control, que no dependen de sobre qué se lo corra.
  final registrados = cascadaPorDefecto(directorio: directorio).pasos;
  return ColaboradoresDeShip(
    repo: RepositorioGit(
      directorio: directorio,
      politica: const PoliticaDeArtefactosDart(),
      entornoDelPadre: entorno,
    ),
    ambiente: const EntornoDart(),
    construirCascada: (raiz) => cascadaPorDefecto(directorio: raiz),
    controles: {for (final paso in registrados) paso.id: paso},
    credenciales: FuenteDeEntorno(entorno),
    registro: RegistroDeCorridas(raiz: rutas.join(directorio, '.shipflow')),
    cambiosAjenos: (deLaRebanada) => cambiosAjenosDelArbol(
      directorio: directorio,
      deLaRebanada: deLaRebanada,
      entornoDelPadre: entorno,
    ),
    responder: responderDeLaTerminal(
      json: g.json,
      hayTerminal: stdin.hasTerminal,
    ),
    leerArchivo: (ruta) => File(ruta).readAsString(),
    nuevoRunId: generarRunId,
  );
}

/// Cómo se le pregunta a quien corre, o **nulo cuando no hay con quién hablar**.
///
/// Dos cosas lo anulan, y decidirlas es del composition root porque las dos son
/// sobre el mundo, no sobre la corrida:
///
/// - **La entrada estándar no es una terminal.** No hay nadie que pueda
///   contestar, y leer de una tubería devolvería como un «sí» lo primero que
///   otro programa haya escrito ahí — una autorización que nadie dio. Se
///   pregunta por la entrada y no por la salida porque la entrada es el canal
///   por el que la respuesta tiene que volver: con la salida redirigida a un
///   archivo, quien está sentado adelante sigue pudiendo contestar.
/// - **`--json`.** Un consumidor automático no contesta preguntas, y la
///   pregunta sería una línea que no es un envelope: el mismo protocolo roto
///   que la frontera única cerró tres veces.
///
/// En los dos casos la corrida se comporta como una previsualización, que es lo
/// que el contrato del CLI ya dice.
///
/// **[hayTerminal] llega leído de afuera y no se consulta acá**, por lo mismo
/// que el preflight recibe la rama ya leída: bajo una suite de pruebas la
/// entrada estándar NUNCA es una terminal, así que una versión que lo
/// preguntara adentro devolvería nulo por las dos razones a la vez y ninguna
/// prueba podría distinguirlas — la de `--json` pasaría con la condición de
/// `--json` borrada. Quien lo lee es la composición real, en una línea.
Future<bool> Function(String pregunta)? responderDeLaTerminal({
  required bool json,
  required bool hayTerminal,
}) {
  if (json || !hayTerminal) return null;
  return (pregunta) async {
    // **Solo un sí explícito autoriza.** Una línea vacía —alguien que apretó
    // Enter— es un no: el default de una pregunta que va a escribir en el
    // repositorio de otra persona no puede ser que sí.
    final respuesta = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    return respuesta == 's' || respuesta == 'si' || respuesta == 'sí';
  };
}

/// Las rutas sucias del árbol de trabajo que **no** son de la rebanada.
///
/// **Se miden, no se asumen.** La previsualización las imprime con su cuenta, y
/// un cero sin haber mirado afirma que no queda nada afuera — que es justo lo
/// que quien confirma necesita poder creerle.
///
/// **Residuo declarado:** la ruta se toma de la cuarta columna en adelante, que
/// es donde el formato de porcelana la escribe. Un renombrado la escribe como
/// `origen -> destino` y acá viaja así, entera: es el texto que una persona
/// necesita para reconocerlo, y partirlo pediría interpretar un formato que
/// además entrecomilla las rutas con caracteres fuera de ASCII. Nada de esto
/// entra en el artefacto ni en el pull request: es el canal local y solo eso.
Future<List<String>> cambiosAjenosDelArbol({
  required String directorio,
  required List<String> deLaRebanada,
  EntornoDelProceso? entornoDelPadre,
  String programa = 'git',
}) async {
  final padre = entornoDelPadre ?? EntornoDelProceso(Platform.environment);
  final argumentos = const [
    // Mismo motivo que en el adapter del repositorio: sin esto cada ruta que
    // vuelve se leería como un patrón.
    '--literal-pathspecs',
    'status',
    '--porcelain',
    '--untracked-files=all',
  ];
  final r = await Process.run(
    programa,
    argumentos,
    workingDirectory: directorio,
    environment: entornoSaneado(padre.paraHijos),
    includeParentEnvironment: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (r.exitCode != 0) {
    // **No se degrada a una lista vacía.** Una lista vacía significa «miré y no
    // había nada»; si la lectura falló, nadie miró, y decir que no hay nada
    // ajeno sería la afirmación que esta función existe para no hacer.
    throw StateError(
      'No se pudieron leer los cambios del árbol de trabajo '
      '($programa ${argumentos.join(" ")} → ${r.exitCode}): ${r.stderr}',
    );
  }
  final declarados = deLaRebanada.toSet();
  return [
    for (final linea in const LineSplitter().convert(r.stdout as String))
      if (linea.length > 3 && !declarados.contains(linea.substring(3)))
        linea.substring(3),
  ];
}

/// La forja que no está compuesta. **Lanza si alguien la usa.**
///
/// Es inalcanzable por construcción: solo se compone en una corrida que no
/// puede publicar —ver [_puedePublicar]—, y llegar a `open` significaría que
/// esa cuenta se equivocó. Por eso lanza en vez de devolver un desenlace:
/// devolver uno inventaría un hecho remoto, y un error del arnés es
/// exactamente lo que una contradicción del composition root es.
class _ForjaAusente implements PullRequestSink {
  const _ForjaAusente();

  @override
  Future<PublicationOutcome> open(PullRequestRequest request) async {
    throw StateError(
      'Se pidió publicar en una corrida compuesta SIN forja, que solo se '
      'compone cuando publicar es imposible. Es una contradicción del '
      'composition root, no un fallo remoto.',
    );
  }
}

/// Si esta corrida **puede llegar a publicar**, decidido antes de tocar nada.
///
/// Un ensayo no publica nunca. Y sin `--yes` y sin nadie que pueda confirmar,
/// tampoco: la confirmación no puede aparecer de ningún lado. Las dos son
/// propiedades de la composición —no del recorrido—, así que se pueden decidir
/// antes de la primera escritura, que es lo que permite que la falta de forja
/// salga como `4` con cero efectos en vez de después del commit.
bool _puedePublicar(EntradaDeShip entrada, {required bool hayQuienConfirme}) =>
    !entrada.dryRun && (entrada.yes || hayQuienConfirme);

/// Corre `ship` y devuelve el código de proceso.
///
/// **Recibe la impresora**, no la construye: la frontera es una sola. Y **emite
/// exactamente un resultado en todo camino**, incluidos los cuatro que salen
/// por excepción.
Future<int> correrShipDelComando(
  Globales globales, {
  required String directorio,
  required Impresora impresora,
  ColaboradoresDeShip Function(String directorio, Globales globales)?
  construirColaboradores,
}) async {
  if (globales.ayuda) {
    // La ayuda gana sobre `--quiet`, igual que en la frontera y en `verify`: si
    // alguien la pidió, callarla es no hacer lo que se pidió. Y se CIERRA la
    // misma que emitió.
    final sinSilencio = Impresora(
      salida: impresora.salida,
      error: impresora.error,
      json: globales.json,
    );
    sinSilencio.resultado(
      const ResultEnvelope(
        command: nombreDeShip,
        exitCode: Codigo.exito,
        // **'ok', y no es que la ayuda haya mirado algo.** Contrastalo con el
        // veredicto nulo de `_detener`, más abajo en este archivo: los dos
        // caminos no miraron ningún cambio y la ayuda mira todavía menos —ni
        // siquiera llega a interpretar la invocación—, y sin embargo acá se
        // afirma 'ok'. No es una inconsistencia que esta ronda introduzca: la
        // ayuda de la frontera (en el despachador) y la de `verify` ya usaban
        // 'ok' antes de que `ship` existiera. Queda sin unificar a propósito:
        // hacerlo tocaría esos dos archivos además de este, y es un cambio de
        // convención que no le pertenece a la ronda de arreglos de un solo
        // comando.
        verdict: 'ok',
        data: {'help': ayudaDeShip},
      ),
      ayudaDeShip,
    );
    sinSilencio.cerrar();
    return Codigo.exito;
  }

  final colaboradores = (construirColaboradores ?? colaboradoresDelSistema)(
    directorio,
    globales,
  );

  final EntradaDeShip entrada;
  try {
    entrada = await resolverRebanada(
      interpretarShip(globales.restantes),
      leer: colaboradores.leerArchivo,
    );
  } on UsoInvalido catch (e) {
    // **Sin `runId`.** No se llegó a componer ninguna corrida, así que no hay
    // nada que correlacionar: inventarle un identificador afirmaría una corrida
    // que no ocurrió.
    return _detener(
      impresora,
      codigo: Codigo.errorDeUso,
      humano: 'shipflow ship: ${e.reason}',
      queHacer: e.queHacer,
      datos: {'error': e.reason},
    );
  }

  final hayQuienConfirme = colaboradores.responder != null;
  final forja = colaboradores.forja;
  if (forja == null &&
      _puedePublicar(entrada, hayQuienConfirme: hayQuienConfirme)) {
    return _detener(
      impresora,
      codigo: Codigo.errorDeConfiguracion,
      humano:
          'shipflow ship: no hay ninguna forja compuesta, así que esta '
          'corrida no podría abrir el pull request que promete.',
      queHacer:
          'Se detuvo ANTES de preparar nada: no quedó ni un objeto ni un '
          'commit. Corré `shipflow ship --dry-run` para ver la '
          'previsualización, que no necesita forja.',
      datos: {'error': 'forja no compuesta'},
    );
  }

  final runId = colaboradores.nuevoRunId();

  void mostrar(String previsualizacion) => impresora.evento(
    EventEnvelope(
      command: nombreDeShip,
      type: tipoDeEventoDePrevisualizacion,
      runId: runId,
      data: {'preview': previsualizacion},
    ),
    previsualizacion,
  );

  final responder = colaboradores.responder;
  Future<bool> confirmar(String previsualizacion) async {
    const pregunta = '¿Se publica esta rebanada? [s/N]';
    impresora.evento(
      EventEnvelope(
        command: nombreDeShip,
        type: tipoDeEventoDeConfirmacion,
        runId: runId,
        data: const {'question': pregunta},
      ),
      pregunta,
    );
    return responder!(pregunta);
  }

  // **Las cuatro que el doc de `correrShip` declara, y ninguna más.** Lo que no
  // esté acá sube a la frontera, que lo convierte en `70` con su resultado: un
  // `catch` ancho acá convertiría un fallo del arnés en una detención declarada,
  // que es la mentira más cara de esta tabla.
  try {
    final desenlace = await correrShip(
      entrada: entrada,
      runId: runId,
      repo: colaboradores.repo,
      ambiente: colaboradores.ambiente,
      construirCascada: colaboradores.construirCascada,
      controles: colaboradores.controles,
      credenciales: colaboradores.credenciales,
      claveDeCredencial: colaboradores.claveDeCredencial,
      forja: forja ?? const _ForjaAusente(),
      registro: colaboradores.registro,
      ramaActual: await colaboradores.repo.ramaActual,
      cambiosAjenos: () => colaboradores.cambiosAjenos(entrada.archivos),
      confirmar: responder == null ? null : confirmar,
      mostrar: mostrar,
      baseConfigurada: colaboradores.baseConfigurada,
      baseDeLaForja: colaboradores.baseDeLaForja,
    );
    return _emitirDesenlace(impresora, runId, desenlace);
  } on UsoInvalido catch (e) {
    // **Hoy es defensivo: inalcanzable por construcción.** La única guardia
    // que lanza `UsoInvalido` dentro de la función compuesta es la de la
    // intención nula, y para cuando la ejecución llega ahí ya pasaron
    // `interpretarShip` y `resolverRebanada` —más arriba, ANTES de este
    // `try`— que garantizan una intención no nula por los dos caminos de
    // entrada: uno la exige junto con `--file`, el otro la lee ya validada
    // del archivo de la rebanada. Este `catch` se queda porque la tabla de
    // códigos del doc de `correrShip` lo declara, y sacarlo la dejaría
    // mintiendo sobre un código que ya no se traduce en ningún lado. Se
    // volvería alcanzable si `correrShip` ganara una tercera forma de armar
    // una `EntradaDeShip` que no pasara por esas dos garantías, o si alguna
    // de las dos dejara de sostener la intención antes de este punto.
    return _detener(
      impresora,
      codigo: Codigo.errorDeUso,
      humano: 'shipflow ship: ${e.reason}',
      queHacer: e.queHacer,
      datos: {'error': e.reason},
      runId: runId,
    );
  } on PreflightRechazado catch (e) {
    // El fallo entero viaja: causa, detalle y qué hacer. No se vuelve a derivar
    // nada acá — es lo que la excepción lleva adentro justamente para esto.
    return _detener(
      impresora,
      codigo: Codigo.errorDeConfiguracion,
      humano: 'shipflow ship: ${e.fallo.detalle}',
      queHacer: e.fallo.queHacer,
      datos: {'error': e.fallo.detalle, 'causa': e.fallo.causa.name},
      runId: runId,
    );
  } on CorridasNoIgnoradas catch (e) {
    return _detener(
      impresora,
      codigo: Codigo.errorDeConfiguracion,
      humano: 'shipflow ship: $e',
      queHacer:
          'Agregá «${e.ruta}» a lo que git ignora —o sacala del índice, que '
          'es lo que hace que ninguna regla la ignore— y volvé a correr. No '
          'se escribió nada.',
      datos: {'error': 'el documento de la corrida no está ignorado'},
      runId: runId,
    );
  } on GitignoreAjeno catch (e) {
    return _detener(
      impresora,
      codigo: Codigo.errorDeConfiguracion,
      humano: 'shipflow ship: $e',
      queHacer:
          'Revisá «${e.ruta}»: si ese contenido es deliberado, dejalo y '
          'asegurate de que ignore el directorio de corridas. No se pisa.',
      datos: {'error': 'gitignore ajeno en el directorio de corridas'},
      runId: runId,
    );
  }
}

/// Emite el desenlace: **el código, el veredicto, la acción y el payload salen
/// todos del mismo [ShipOutcome]**, cada uno por su derivación. Ningún sitio de
/// retorno elige uno a mano.
int _emitirDesenlace(Impresora imp, String runId, ShipOutcome desenlace) {
  final codigo = Codigo.deShip(desenlace);
  final accion = accionDe(desenlace);
  final humano = _enTexto(desenlace);
  imp.resultado(
    ResultEnvelope(
      command: nombreDeShip,
      exitCode: codigo,
      verdict: veredictoDeShip(desenlace),
      nextAction: accion,
      runId: runId,
      data: payloadDeShip(desenlace),
    ),
    accion == null ? humano : '$humano\n  → $accion',
  );
  imp.cerrar();
  return codigo;
}

/// Una detención que **no es desenlace**: no hubo corrida que describir, así
/// que no hay `ShipOutcome` del que derivar nada y el código lo decide quien
/// atrapó la excepción.
int _detener(
  Impresora imp, {
  required int codigo,
  required String humano,
  required String queHacer,
  required Map<String, Object?> datos,
  String? runId,
}) {
  imp.resultado(
    ResultEnvelope(
      command: nombreDeShip,
      exitCode: codigo,
      // **Sin veredicto, y es el mismo hueco declarado del error de uso:** una
      // detención antes de que hubiera corrida no miró ningún cambio, así que
      // no tiene nada que afirmar sobre él. **La ayuda, más arriba en este
      // archivo, mira todavía menos y sale con 'ok'.** No es una regresión —
      // sigue al `--help` que ya existía en la frontera y en `verify`— pero
      // las dos reglas conviven sin que nada más las distinga; se documentan
      // cruzadas en vez de unificarse porque unificarlas es una decisión de
      // convención que excede esta ronda de un solo comando.
      verdict: null,
      nextAction: queHacer,
      runId: runId,
      data: datos,
    ),
    '$humano\n  → $queHacer',
  );
  imp.cerrar();
  return codigo;
}

/// El desenlace en texto. **Las cinco variantes se dicen distinto**: un
/// resumen que las igualara obligaría a leer el código de salida para saber qué
/// pasó, y el texto es justamente lo que lee quien no lo hace.
String _enTexto(ShipOutcome desenlace) => switch (desenlace) {
  NoIntentado(:final causa, :final verificacion) =>
    'ship: no se publicó nada — ${causa.name}. La verificación quedó en '
        '${verificacion.name}.',
  NoAplicado(:final headObservado) =>
    'ship: la rama avanzó a $headObservado mientras se verificaba, así que '
        'no se aplicó nada.',
  LocalInconsistente(:final revision) =>
    'ship: el commit $revision existe y el índice quedó sin sincronizar.',
  Publicado(:final pr, :final verificacion) =>
    'ship: pull request en ${pr.url}. La verificación quedó en '
        '${verificacion.name}.',
  PublicacionIncompleta(:final remoto, :final verificacion) =>
    'ship: el trabajo local se completó y el efecto remoto no '
        '(${remoto.kind}). La verificación quedó en ${verificacion.name}.',
};
