/// La orquestación de `ship`: los dieciséis pasos, y la limpieza en todo
/// camino.
///
/// **Acá no se inventa nada.** Cada paso ya existe —el preflight, el
/// candidato, la cascada sobre su raíz, el remapeo, el escaneo de secretos, la
/// superficie, la previsualización, la compuerta, el `.gitignore` de las
/// corridas, el commit condicionado, el documento y el desenlace—: lo que este
/// archivo agrega es el ORDEN en que se llaman y qué se hace con lo que cada
/// uno devuelve.
///
/// **Todos los colaboradores se inyectan**, y no por gusto: es lo que permite
/// probar cada camino sin red, sin forja y sin terminal. El único que no es un
/// puerto es el repositorio, y ahí la suite usa uno de verdad en un directorio
/// temporal — lo que estas pruebas fijan es que el commit NO ocurre en ciertos
/// caminos, y eso contra un doble no prueba nada.
///
/// **Qué NO cabe en [ShipOutcome], y por eso sale por excepción.** [ShipOutcome]
/// cubre el desenlace de una corrida **que llegó a existir**: qué pasó con el
/// trabajo local y con el efecto remoto. La invocación que no se pudo
/// interpretar, el preflight rechazado, el directorio de corridas desprotegido
/// y el `.gitignore` ajeno son detenciones ANTES de que haya corrida que
/// describir, y no tienen variante en la fábrica. Construir una a mano sería
/// exactamente lo que los constructores privados de [ShipOutcome] impiden, así
/// que salen tipadas. Son cuatro y están todas en el doc de [correrShip], con
/// su código.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:vcs/vcs.dart';

import '../corrida.dart';
import '../uso.dart';
import 'entrada.dart';
import 'gitignore.dart';
import 'preflight.dart';
import 'preview.dart';

/// El preflight rechazó la corrida. **Cero escrituras**: es el código `4`.
///
/// No es un [ShipOutcome] porque no hay ninguno que lo diga: las cuatro causas
/// de [NoIntentado] son sobre una corrida que llegó a preparar un candidato, y
/// acá no se preparó ninguno. Lleva el fallo entero —causa, detalle y qué
/// hacer— para que quien lo atrape no tenga que volver a derivar nada.
class PreflightRechazado implements Exception {
  final PreflightFallo fallo;

  const PreflightRechazado(this.fallo);

  @override
  String toString() =>
      'PreflightRechazado(${fallo.causa.name}): ${fallo.detalle}';
}

/// El documento de la corrida iba a quedar donde `git` NO lo ignora.
///
/// **Se detiene antes de escribirlo.** Un documento de corrida dentro del pull
/// request es lo contrario de lo que el mecanismo promete: el JSON es local
/// —el revisor remoto no puede abrirlo— y por eso el cuerpo del pull request
/// es autosuficiente. Si alguna vez tuviera que estar remoto, se publica por
/// un mecanismo explícito, nunca colándose por una ruta local.
class CorridasNoIgnoradas implements Exception {
  final String ruta;

  const CorridasNoIgnoradas(this.ruta);

  @override
  String toString() =>
      'CorridasNoIgnoradas: git no ignora «$ruta», así que el documento de la '
      'corrida terminaría commiteado dentro del pull request.';
}

/// Por qué esta corrida no tiene plan.
///
/// **Presente y concreto, no vacío.** [ArtefactoDeRevision] exige plan o
/// motivo porque un artefacto sin ninguno de los dos afirma por omisión que no
/// hacía falta ninguno; el modo «solo PR» entra sin elemento de trabajo y sin
/// plan a propósito, y eso se dice.
const _sinPlanPorque =
    'Esta corrida entra por el modo «solo PR»: la rebanada se declaró en la '
    'invocación y no hay ningún plan del que derivarla.';

/// Lo que produce una corrida: **el desenlace, y si su registro quedó
/// escrito**.
///
/// **Son dos hechos y no uno, y por eso no viven en el mismo campo.** El
/// desenlace describe qué pasó con el trabajo local y con el efecto remoto;
/// [documentoNoEscrito] describe qué pasó con la ANOTACIÓN de ese desenlace.
/// Meterlo adentro de [ShipOutcome] sería hacerle decir a la corrida algo que
/// no es de la corrida sino de su registro, y además obligaría a las cinco
/// variantes a llevar un campo que solo le importa a quien persiste.
///
/// **Por qué existe.** El paso 15 abre el pull request y el paso 16 sella, y
/// sellar escribe. Hasta esta ronda un fallo de esa escritura —disco lleno,
/// permisos, el directorio de corridas que dejó de ser escribible— no era
/// ninguna de las cuatro excepciones tipadas, subía a la frontera y salía por
/// la red de último recurso: `70`, «se rompió el arnés», **con el pull
/// request ya abierto** y sin ninguna clave que lo dijera. Ese hecho es el más
/// caro de perder de toda la corrida, porque es el único que volver a correr
/// no reconstruye. Un ruling anterior ya protegió la RELECTURA del documento
/// por este mismo motivo; la escritura quedaba sin proteger, y es la que
/// falla por causas de entorno reales.
typedef ResultadoDeShip = ({ShipOutcome desenlace, bool documentoNoEscrito});

/// Corre `ship` de punta a punta y devuelve **el desenlace**, no un código.
///
/// El orden es el de §8 de la propuesta, y cada número del comentario es el
/// paso que nombra esa lista. Lo que decide si se sigue o no son tres cosas y
/// están todas antes de la primera escritura: el secreto (paso 5), la
/// confirmación (paso 7) y la compuerta por estado (paso 8).
///
/// [ramaActual] llega leída de afuera, igual que la credencial: [preflight] es
/// puro sobre hechos ya leídos, y esa pureza es lo que hace baratas sus siete
/// pruebas. [confirmar] es nulo cuando no hay terminal con quien hablar, y
/// entonces la corrida se comporta como una previsualización — que es lo que
/// el contrato del CLI ya dice. [mostrar] es por dónde sale ese texto, y es
/// un canal aparte justamente porque mostrar y preguntar no son lo mismo.
///
/// [cambiosAjenos] son las rutas sucias del árbol de trabajo que no son de la
/// rebanada. **Es un colaborador y no un `const []`**: la previsualización las
/// imprime con su cuenta, y decir «cero» sin haber mirado es afirmar que no
/// hay nada que quede afuera. Viaja por su propio parámetro —nunca dentro del
/// artefacto— porque son el canal LOCAL: el revisor remoto no puede verlas.
///
/// **Las CUATRO salidas que no son desenlace, y salen por excepción.** Ninguna
/// describe una corrida: describen por qué no llegó a haber una. Las cuatro
/// las atrapa el comando —la tarea 10—, que es el único que traduce a código
/// de proceso; acá no se atrapa ninguna, porque atraparla sería decidir el
/// código dos veces.
///
/// | Excepción | Cuándo | Código |
/// |---|---|---|
/// | [UsoInvalido] | La entrada no declara intención | `5` |
/// | [PreflightRechazado] | El preflight rechazó, con su fallo entero | `4` |
/// | [CorridasNoIgnoradas] | El documento iba a quedar donde `git` no lo ignora | `4` |
/// | [GitignoreAjeno] | Ya hay un `.gitignore` ajeno en el directorio de corridas | `4` |
///
/// Las tres últimas comparten el `4` porque **lo que falta es una
/// precondición del entorno**: nada está mal en el código y nada se
/// corrompió. [UsoInvalido] es `5` porque lo que no se pudo interpretar es la
/// invocación.
///
/// **Ese motivo NO es «cero escrituras persistentes», y decirlo era falso**
/// para una de las tres. [PreflightRechazado] y [GitignoreAjeno] sí dejan el
/// disco como estaba —el primero corre antes de que nada escriba; el segundo
/// necesita que el `.gitignore` ajeno ya exista, o sea que el directorio ya
/// estaba—. [CorridasNoIgnoradas], en cambio, se lanza DESPUÉS de
/// [asegurarGitignore], que crea el directorio de corridas y escribe su regla
/// antes de devolver: en el primer uso, que es el caso común, quedan un
/// directorio y un archivo.
///
/// **Y quedan, no se borran.** Deshacerlos sería un rollback en el momento
/// exacto en que el entorno ya está dando problemas, sobre un archivo que
/// puede venir de una corrida anterior; y comprobar antes de asegurar no es
/// una opción, porque la regla que se comprueba es justamente la que esa
/// función escribe —sin ella, el primer uso no podría pasar nunca—. Lo que
/// queda es inerte: un directorio con una regla que hace que `git` no vea
/// nada de lo que haya adentro. El mensaje lo dice así.
Future<ResultadoDeShip> correrShip({
  required EntradaDeShip entrada,
  required String runId,
  required RepositorioGit repo,
  required VerificationEnvironment ambiente,
  required Cascada Function(String raiz) construirCascada,
  required Map<String, Verifier> controles,
  required CredentialSource credenciales,

  /// Bajo qué clave del entorno viaja la credencial de la forja. **La elige
  /// quien compone**, porque `ship` no sabe quién es la forja.
  ///
  /// El preflight aprueba leyendo ESTA clave y quien publica lee con la que le
  /// hayan armado: si fueran dos elecciones, el preflight aprobaría por una y
  /// la publicación fallaría por otra, sin que nada lo explique. **Ya no son
  /// dos**: desde que la salida de pull requests se construye con una fábrica,
  /// la clave viaja hasta adentro del adapter y la raíz de composición la
  /// decide una sola vez. Antes el adapter la traía escrita adentro y esta
  /// frase solo podía pedir que coincidieran.
  required String claveDeCredencial,
  required PullRequestSink forja,

  /// **A dónde publica esta corrida**, como la cadena opaca que produce el
  /// paquete que sabe quién atiende cada remoto. Se persiste en el documento
  /// para que un reintento pueda comprobar que sigue publicando ahí — ver
  /// `DocumentoDeCorrida.destino`.
  ///
  /// **Nulo solo en una composición que NO puede publicar**, y es la misma
  /// cuenta que sostiene a la forja ausente: sale del mismo remoto del que
  /// sale la forja, así que una composición con forja tiene destino. Ningún
  /// camino que escriba el documento llega con esta nula — ver el sitio donde
  /// se persiste.
  required String? destino,
  required RegistroDeCorridas registro,
  required String ramaActual,
  required Future<List<String>> Function() cambiosAjenos,

  /// Cómo se pregunta la confirmación. **Inyectable para poder probar los dos
  /// caminos** sin una terminal: sin terminal no se pregunta y se sale como
  /// una previsualización.
  required Future<bool> Function(String previsualizacion)? confirmar,

  /// Por dónde sale la previsualización. **Nulo es no mostrarla**, y por eso
  /// se exige: quien compone tiene que decidirlo, igual que [confirmar].
  ///
  /// Sin este canal, `--dry-run` no producía nada —y es el modo cuyo único
  /// producto es este texto—, porque mostrar iba pegado a preguntar y un
  /// ensayo no pregunta. Aguas arriba tampoco se podía tapar: lo único que
  /// sale de acá es el desenlace, que no lleva ni artefacto ni superficie.
  required void Function(String previsualizacion)? mostrar,
  String? baseConfigurada,
  String? baseDeLaForja,
  Duration presupuesto = const Duration(minutes: 5),
}) async {
  // **La intención se exige acá, y no se asume.** `EntradaDeShip.intent` es
  // nulable, la previsualización lo interpola directo y la rebanada lo exige
  // no vacío: hoy el intérprete lo obliga antes de llegar acá, pero una
  // entrada armada por otro camino colaría un nulo hasta el texto que lee una
  // persona. Es la misma frontera que ya rechaza cero archivos.
  final intencion = entrada.intent;
  if (intencion == null) {
    throw const UsoInvalido(
      'la entrada no declara ninguna intención',
      'Pasá --intent junto con --file, o --slice con la rebanada ya '
          'declarada: la intención es lo que el pull request va a decir.',
    );
  }

  // 1 · Preflight. Cero escrituras: si algo falla, no se preparó nada.
  final resultado = preflight(
    ramaActual: ramaActual,
    branchPedida: entrada.branch,
    baseExplicita: entrada.base,
    baseConfigurada: baseConfigurada,
    baseDeLaForja: baseDeLaForja,
    credencial: await credenciales.read(claveDeCredencial),
  );
  final PreflightOk aprobado;
  switch (resultado) {
    case PreflightFallo():
      throw PreflightRechazado(resultado);
    case PreflightOk():
      aprobado = resultado;
  }

  // **La identidad de la rebanada la asigna la corrida, no el archivo.** Hoy
  // hay una sola por corrida; el modelo final admite varias, y por eso el
  // identificador es `<runId>/1` y no el `runId` a secas: igualar las dos
  // identidades fusiona dos cosas que van a divergir.
  final rebanada = PullRequestSlice(
    id: '$runId/1',
    intent: intencion,
    files: entrada.archivos,
  );

  PreparedCandidate? candidato;
  // Si el cuerpo ya falló, la limpieza no puede ser la que se cuente. Ver el
  // `finally`.
  var elCuerpoFallo = false;
  try {
    // 2 y 3 · El candidato, en almacén de objetos aislado, y materializado.
    candidato = await repo.prepareCandidate(rebanada);

    final entorno = await ambiente.derivar(
      candidato.root,
      archivos: entrada.archivos,
      presupuesto: presupuesto,
    );

    // **La integridad se mira dos veces y las dos cuentan, así que se
    // acumulan por ruta.** La primera comprueba que la derivación no haya
    // borrado contenido versionado; la segunda, que ningún verificador haya
    // escrito en el workspace. Quedarse solo con la última perdería lo que la
    // primera vio y la cascada ya leyó.
    final alteraciones = <String, AlteracionDelCandidato>{
      for (final a in await candidato.alteraciones()) a.ruta: a,
    };

    // 4 · La cascada, SOBRE EL CANDIDATO, y el remapeo de sus rutas.
    //
    // **Sin entorno derivado no corre, y entonces no hay cascada que mostrar.**
    // `derivarSuperficie` rechaza la combinación contradictoria —entorno no
    // derivado con cascada no nula— porque sería afirmar que corrieron
    // controles que no pudieron correr.
    ResultadoDeCascada? cascada;
    if (entorno is EntornoDerivado) {
      final corrida = await construirCascada(
        candidato.root,
      ).correr(entrada.archivos);
      cascada = remapear(corrida, raizDelCandidato: candidato.root);
      for (final a in await candidato.alteraciones()) {
        alteraciones[a.ruta] = a;
      }
    }

    // 5 · Los secretos, sobre el diff de ESE par de revisiones.
    //
    // **Se pregunta antes de mostrar y de preguntar, y el hallazgo no lanza
    // acá.** Un secreto es un desenlace de la corrida —`secretDetected`—, no
    // una excepción: la fábrica lo pone por encima de la confirmación, así que
    // se ve aunque nadie haya pasado `--yes`. `createRevision` vuelve a
    // escanear por su cuenta, y eso NO es una segunda ventana —el par de
    // revisiones es el mismo y es inmutable—: es que la garantía del commit no
    // dependa de que este paso se haya pedido antes.
    var huboSecreto = false;
    try {
      await candidato.exigirSinSecretos();
    } on SecretoEnLaRebanada {
      huboSecreto = true;
    }

    // 6 · La superficie, con las alteraciones REALES, y el artefacto.
    //
    // **Vacía significa «comprobado e intacto», no «no se comprobó».** Hasta
    // esta rebanada `derivarSuperficie` se llamaba con la lista vacía; acá
    // recibe la que salió del candidato, que es la única que puede sostener
    // esa lectura.
    final superficie = derivarSuperficie(
      entorno: entorno,
      alteraciones: alteraciones.values.toList(),
      cascada: cascada,
      controles: controles,
    );

    final artefacto = ArtefactoDeRevision(
      superficie: superficie,
      candidato: candidato.identity,
      intent: intencion,
      plan: null,
      sinPlanPorque: _sinPlanPorque,
      alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
    );

    // **`entrada.archivos` y no una derivación nueva.** Son las rutas de la
    // rebanada que el comando ya interpretó —las mismas que arma `rebanada` y
    // que ve la cascada—, y el borrador las persiste tal cual: D1 de esta
    // rebanada prohíbe una segunda fuente del mismo hecho.
    final borrador = PullRequestDraft(
      runId: runId,
      branch: aprobado.rama,
      base: aprobado.base,
      artefacto: artefacto,
      rutas: entrada.archivos,
    );

    // 8 · La compuerta por estado. **`--yes` no participa**: autoriza a
    //     escribir, no a publicar algo que no concluyó.
    //
    // **Se calcula antes del paso 7 y eso no altera el orden de §8**, porque
    // no hace nada: es una función pura del estado y de una bandera. Lo que la
    // secuencia ordena son los EFECTOS —mostrar, preguntar, escribir—, y el
    // único efecto de por acá es la pregunta, que sigue yendo después. Tenerla
    // resuelta antes es justamente lo que impide preguntar por algo que la
    // compuerta ya decidió que no va a pasar.
    final autorizado = autoriza(
      estado: superficie.estado,
      allowIncomplete: entrada.allowIncomplete,
    );

    // 7 · La previsualización, y la confirmación.
    //
    // **Construir, mostrar y preguntar son tres cosas y eran una sola
    // condición.** Pegadas, un ensayo —que no pregunta— tampoco construía, y
    // entonces el modo cuyo único producto es el preview no producía nada.
    //
    // Se CONSTRUYE cuando hay algo que mostrar: no hubo secreto y la compuerta
    // autorizó. Con cualquiera de los dos en contra el desenlace ya está
    // decidido y el texto sería trabajo para tirar — ese ahorro es del código
    // anterior y se conserva. Se MUESTRA cada vez que se construye. Y se
    // PREGUNTA solo cuando además falta autorización.
    //
    // **`seConfirmo` lleva el HECHO, sin adornos.** Un ensayo no confirmó
    // nada; decir que sí para alcanzar `previewOnly` era mentirle a la fábrica
    // cuya razón de existir es derivar la causa de los hechos. La precedencia
    // —previsualización antes que confirmación— es la que decide cuál gana.
    var seConfirmo = entrada.yes;
    if (!huboSecreto && autorizado) {
      final texto = previsualizacion(
        entrada: entrada,
        rama: aprobado.rama,
        base: aprobado.base,
        artefacto: artefacto,
        cambiosAjenos: await cambiosAjenos(),
      );
      mostrar?.call(texto);
      // **No se pregunta lo que ya no se va a hacer.** Un ensayo no pidió
      // efecto ninguno y `--yes` ya autorizó: en los dos casos la pregunta
      // pediría autorizar algo que no está pendiente.
      if (!entrada.dryRun && !entrada.yes && confirmar != null) {
        seConfirmo = await confirmar(texto);
      }
    }

    // **Una sola salida para todo lo que no llegó a intentar**, y la causa la
    // deriva la fábrica de los hechos. Con `--dry-run` se sale ACÁ, antes del
    // paso 9: crear `.shipflow/` ya sería un efecto persistente, y este camino
    // promete que no queda ninguno.
    if (huboSecreto || !autorizado || !seConfirmo || entrada.dryRun) {
      // **`documentoNoEscrito` en falso, y no es un valor de relleno**: este
      // camino no llegó a escribir ningún documento, así que no hay ninguno
      // que pudiera haber fallado. Decir que sí afirmaría un intento que no
      // ocurrió.
      return (
        desenlace: ShipOutcome.derivar(
          verificacion: superficie.estado,
          huboSecreto: huboSecreto,
          seConfirmo: seConfirmo,
          soloPreview: entrada.dryRun,
          autorizaIncompleto: entrada.allowIncomplete,
        ),
        documentoNoEscrito: false,
      );
    }

    // **A partir de acá los tres hechos de autorización ya están decididos**, y
    // son los mismos para los cuatro desenlaces que siguen: no hubo secreto, se
    // confirmó y no era una previsualización. Escribirlos una vez en vez de
    // repetirlos en cada retorno es lo que impide que dos sitios contesten
    // distinto sobre la misma corrida.
    ShipOutcome desenlaceDeLoEscrito({
      PublicationOutcome? remoto,
      NotApplied? casRechazado,
      String? revisionConIndiceSucio,
    }) => ShipOutcome.derivar(
      verificacion: superficie.estado,
      huboSecreto: false,
      seConfirmo: true,
      soloPreview: false,
      autorizaIncompleto: entrada.allowIncomplete,
      remoto: remoto,
      casRechazado: casRechazado,
      revisionConIndiceSucio: revisionConIndiceSucio,
    );

    // 9 · El `.gitignore` del directorio de corridas, y su comprobación.
    //     Acá y no en el preflight: `.shipflow/` no existe en el primer uso, y
    //     exigirlo antes impediría exactamente ese primer uso.
    //
    //     **Se comprueban LAS DOS rutas que el paso 14 escribe**, y la lista
    //     la da el registro: el criterio es «ningún archivo de la corrida
    //     termina commiteado», y mirar solo el documento era decidirlo sobre
    //     una representación más pobre que ese criterio.
    await asegurarGitignore(registro.raiz);
    for (final ruta in registro.rutasDe(runId)) {
      if (!await corridasIgnoradas(repo, ruta)) {
        throw CorridasNoIgnoradas(ruta);
      }
    }

    // 10 y 11 · Promover los objetos preparados y crear la revisión. **No
    //     mueve ninguna rama**: si el compare-and-swap se rechaza después,
    //     este objeto queda inalcanzable y el recolector lo junta.
    final revision = await candidato.createRevision();

    // 12 · `prepared`, CON la revisión. Entre crear el objeto y mover la
    //     referencia hay que poder persistir la identidad: si no, un proceso
    //     que muera en el medio deja una revisión que nadie anotó.
    // **`!`, y la cuenta que lo sostiene es la misma que vuelve inalcanzable
    // a la forja ausente.** Un documento solo se escribe pasadas las cuatro
    // condiciones del retorno de arriba —no hubo secreto, la compuerta
    // autorizó, se confirmó y no es un ensayo—, y confirmar exige `--yes` o
    // alguien que conteste. Esas son exactamente las condiciones con las que
    // la raíz de composición decide que esta corrida PODRÍA publicar, y una
    // corrida que podría publicar y no tiene forja se detiene antes de llegar
    // acá, con cero escrituras. La forja y el destino salen del MISMO remoto
    // leído una sola vez: donde hay una, hay el otro.
    var documento = DocumentoDeCorrida.preparado(
      revision: revision,
      draft: borrador,
      destino: destino!,
    );
    await registro.escribir(runId, documento);

    // 13 · El compare-and-swap, condicionado a la base.
    final aplicado = await candidato.applyRevision();
    switch (aplicado) {
      // **Viaja entero, no su `HEAD`.** Las dos causas se arreglan distinto y
      // una de las dos ni siquiera intentó el compare-and-swap: quedarse con
      // el `HEAD` observado las igualaba, y el desenlace terminaba afirmando
      // «la rama avanzó» sobre una rama que no se movió.
      case NotApplied():
        return await _sellar(
          registro,
          runId,
          documento,
          desenlaceDeLoEscrito(casRechazado: aplicado),
        );
      case LocalInconsistent(revision: final revisionConIndiceSucio):
        return await _sellar(
          registro,
          runId,
          documento,
          desenlaceDeLoEscrito(revisionConIndiceSucio: revisionConIndiceSucio),
        );
      case Committed():
        // 14 · `committed` y sus proyecciones, las dos LOCALES.
        documento = documento.avanzarA(EstadoDelDocumento.committed);
        await registro.escribir(runId, documento);
        await _proyectarLaRevision(registro, runId, documento);
    }

    // 15 · La publicación. **Idempotente**: repetirla con la misma solicitud
    //     no abre un segundo pull request.
    //
    // **El tercer argumento se COPIA del candidato acá, y eso vacía la guarda
    // del constructor — que por este camino es inocuo, por construcción.** El
    // constructor valida que el árbol de la revisión sea el que el candidato
    // declaró haber expuesto a los controles; pasarle el valor declarado lo
    // hace comparar el dato contra sí mismo. Acá no hay nada que esa
    // comparación pudiera atrapar: el árbol lo fijó este mismo proceso unas
    // líneas más arriba, el commit se creó sobre ESE árbol fijado, y entre
    // las dos cosas no hubo ningún otro proceso ni ninguna otra lectura de la
    // que discrepar. Medirlo con la herramienta acá sería una lectura más que
    // ninguna prueba puede matar, porque no hay documento en el disco que
    // pueda decir otra cosa.
    //
    // **Donde SÍ cambia es en el reintento**, y por eso allá se mide y acá
    // no: ese camino reconstruye la solicitud desde un documento que escribió
    // OTRO proceso, así que el valor declarado y el árbol que el repositorio
    // tiene son dos hechos distintos que pueden discrepar, y la guarda es lo
    // único que los cruza. Queda dicho en los dos lados —acá por qué copiar
    // no cuesta nada, allá por qué copiar sería el defecto— para que no
    // parezca que uno de los dos se olvidó.
    final remoto = await forja.open(
      PullRequestRequest(
        draft: borrador,
        revision: revision,
        arbolDeLaRevision: candidato.identity.contentRevision,
      ),
    );

    // 16 · El desenlace final, persistido.
    return await _sellar(
      registro,
      runId,
      documento,
      desenlaceDeLoEscrito(remoto: remoto),
    );
  } catch (_) {
    elCuerpoFallo = true;
    rethrow;
  } finally {
    // **En *todo* camino** —éxito, fallo, rechazo del usuario, excepción—. Hasta
    // acá hay un workspace, un índice y un almacén de objetos temporales en
    // disco, y un camino que salga sin liberarlos deja objetos y directorios
    // que nadie va a recoger. Es idempotente: liberar dos veces no falla.
    //
    // **Y si liberar falla, no tapa al que ya venía subiendo.** Una excepción
    // lanzada desde un `finally` reemplaza a la que estaba en vuelo, así que
    // sin esta guarda quien rompió la cascada veía un fallo del borrado de un
    // directorio temporal. El fallo de la limpieza se pierde SOLO en ese caso,
    // y es el intercambio correcto: lo que explica la corrida es el primero,
    // el borrado es idempotente y lo que queda sin recoger es un temporal del
    // sistema. Sin nada en vuelo, en cambio, el fallo de la limpieza es el
    // único hecho que hay y sube entero.
    try {
      await candidato?.dispose();
    } catch (_) {
      if (!elCuerpoFallo) rethrow;
    }
  }
}

/// Persiste el estado que [desenlace] afirma, con él adentro, y lo devuelve.
///
/// **El estado no se elige a mano: lo determina el desenlace.** Son el mismo
/// hecho dicho dos veces, y elegirlo por separado es lo que dejaba construir
/// un documento que dijera «el CAS fue rechazado» llevando adentro «hay un
/// pull request abierto».
///
/// `!` y no un `if`: [DocumentoDeCorrida.estadoQueAfirma] devuelve nulo solo
/// para [NoIntentado], y ninguno de los tres sitios que llaman acá puede
/// producirlo — los cuatro motivos de no intentar se resuelven antes de que
/// exista la revisión sin la cual este documento no se puede escribir.
///
/// **Y un fallo de la ESCRITURA no se lleva el desenlace.** Es la elección de
/// esta ronda, y el argumento es el de la relectura: el desenlace ya está
/// medido —con el paso 15 detrás, hay un pull request abierto del otro lado—
/// y dejar que la anotación se lo lleve convierte el hecho más caro de toda
/// la corrida en un `70` mudo. Lo que se pierde al tolerar es el registro, que
/// es recuperable mirando la forja; lo que se perdía al no tolerar era el
/// único aviso de que hay un pull request abierto. El fallo NO se traga: sale
/// por [ResultadoDeShip.documentoNoEscrito] hasta el payload, que lo dice con
/// su propia clave, igual que ya dice que el documento no se pudo releer.
///
/// **Lo que sí sube entero es el cálculo del estado**, y por eso
/// [DocumentoDeCorrida.avanzarA] queda fuera del `try`: una transición
/// inválida es un error de programación —el desenlace y el estado se
/// contradicen—, no una condición del entorno, y taparlo dejaría escribible
/// justo lo que ese tipo existe para impedir.
///
/// **Se atrapa todo y no una lista de tipos**, que es la excepción a la regla
/// del proyecto y por eso se argumenta: lo que puede fallar acá es el disco
/// —sin espacio, sin permisos, el directorio borrado entre dos pasos— y llega
/// por familias que ni siquiera son todas excepciones. Una lista de tipos
/// dejaría afuera justamente el caso que motiva esto. El precio de atrapar de
/// más está acotado a una escritura que no decide nada: solo anota.
Future<ResultadoDeShip> _sellar(
  RegistroDeCorridas registro,
  String runId,
  DocumentoDeCorrida documento,
  ShipOutcome desenlace,
) async {
  final sellado = documento.avanzarA(
    DocumentoDeCorrida.estadoQueAfirma(desenlace)!,
    desenlace: desenlace,
  );
  try {
    await registro.escribir(runId, sellado);
  } catch (_) {
    return (desenlace: desenlace, documentoNoEscrito: true);
  }
  return (desenlace: desenlace, documentoNoEscrito: false);
}

/// La proyección local de la revisión: la evidencia citada, al lado del
/// documento.
///
/// **Es una proyección, no una segunda fuente.** Todo lo que escribe sale del
/// documento que recibe; nada se compone acá. Dos documentos del mismo hecho
/// divergen siempre, así que este no lleva ni versión propia ni campos que el
/// autoritativo no tenga.
///
/// **Es local y queda ignorada por `git`** —el paso 9 lo comprobó contra la
/// misma máquina que decide qué entra en un commit—, así que el revisor remoto
/// no puede abrirla: por eso el cuerpo del pull request es autosuficiente.
///
/// Temporal y `rename`, como [RegistroDeCorridas.escribir] y por lo mismo: el
/// nombre final aparece con el contenido entero o no aparece.
Future<void> _proyectarLaRevision(
  RegistroDeCorridas registro,
  String runId,
  DocumentoDeCorrida documento,
) async {
  // La ruta la da el registro, que es quien la declara: si la compusiera acá,
  // el control del paso 9 comprobaría una ruta y este paso escribiría otra.
  final destino = File(registro.proyeccionDe(runId));
  await destino.parent.create(recursive: true);
  final temporal = File('${destino.path}.tmp');
  // El mapa, con nombre y en una línea por clave: interpolado entero adentro
  // del texto, esto era una sola línea de doscientos caracteres donde no se
  // veía cuáles son los tres campos ni de dónde sale cada uno.
  final proyeccion = <String, Object?>{
    'formatVersion': DocumentoDeCorrida.versionActual,
    'revision': documento.revision,
    'artefacto': documento.draft.artefacto.toJson(),
  };
  await temporal.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(proyeccion)}\n',
    flush: true,
  );
  await temporal.rename(destino.path);
}
