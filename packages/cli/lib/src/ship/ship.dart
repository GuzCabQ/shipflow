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
/// **Qué NO cabe en [ShipOutcome], y por eso sale por excepción.** El
/// desenlace de una corrida describe lo que pasó con el trabajo local y con el
/// efecto remoto; el preflight rechazado y el directorio de corridas
/// desprotegido son detenciones ANTES de que haya corrida que describir —cero
/// escrituras, código `4`— y no tienen variante en la fábrica. Construir una a
/// mano sería exactamente lo que los constructores privados de [ShipOutcome]
/// impiden, así que salen tipadas, como ya sale [GitignoreAjeno].
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:path/path.dart' as rutas;
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
/// el contrato del CLI ya dice.
///
/// [cambiosAjenos] son las rutas sucias del árbol de trabajo que no son de la
/// rebanada. **Es un colaborador y no un `const []`**: la previsualización las
/// imprime con su cuenta, y decir «cero» sin haber mirado es afirmar que no
/// hay nada que quede afuera. Viaja por su propio parámetro —nunca dentro del
/// artefacto— porque son el canal LOCAL: el revisor remoto no puede verlas.
Future<ShipOutcome> correrShip({
  required EntradaDeShip entrada,
  required String runId,
  required RepositorioGit repo,
  required VerificationEnvironment ambiente,
  required Cascada Function(String raiz) construirCascada,
  required Map<String, Verifier> controles,
  required CredentialSource credenciales,
  required String claveDeCredencial,
  required PullRequestSink forja,
  required RegistroDeCorridas registro,
  required String ramaActual,
  required Future<List<String>> Function() cambiosAjenos,

  /// Cómo se pregunta la confirmación. **Inyectable para poder probar los dos
  /// caminos** sin una terminal: sin terminal no se pregunta y se sale como
  /// una previsualización.
  required Future<bool> Function(String previsualizacion)? confirmar,
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
    // escanear por su cuenta, y eso no es la misma garantía repetida: cierra
    // la ventana entre mostrar y commitear, que ninguna llamada anterior tapa.
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

    final borrador = PullRequestDraft(
      runId: runId,
      branch: aprobado.rama,
      base: aprobado.base,
      artefacto: artefacto,
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
    // **No se pregunta lo que ya no se va a hacer.** Con un secreto, con la
    // compuerta cerrada o con `--dry-run`, la corrida ya tiene desenlace: una
    // pregunta ahí pediría autorizar algo que no va a pasar. Lo que sí se
    // reporta como confirmado es el hecho —`--yes` se pasó o no—, porque la
    // precedencia de la fábrica es la que decide cuál de las causas gana.
    final hayAlgoQueAutorizar =
        !huboSecreto && autorizado && !entrada.dryRun && !entrada.yes;
    final seConfirmo =
        entrada.yes ||
        entrada.dryRun ||
        (hayAlgoQueAutorizar &&
            confirmar != null &&
            await confirmar(
              previsualizacion(
                entrada: entrada,
                rama: aprobado.rama,
                base: aprobado.base,
                artefacto: artefacto,
                cambiosAjenos: await cambiosAjenos(),
              ),
            ));

    // **Una sola salida para todo lo que no llegó a intentar**, y la causa la
    // deriva la fábrica de los hechos. Con `--dry-run` se sale ACÁ, antes del
    // paso 9: crear `.shipflow/` ya sería un efecto persistente, y este camino
    // promete que no queda ninguno.
    if (huboSecreto || !autorizado || !seConfirmo || entrada.dryRun) {
      return ShipOutcome.derivar(
        verificacion: superficie.estado,
        huboSecreto: huboSecreto,
        seConfirmo: seConfirmo,
        soloPreview: entrada.dryRun,
        autorizaIncompleto: entrada.allowIncomplete,
      );
    }

    // **A partir de acá los tres hechos de autorización ya están decididos**, y
    // son los mismos para los cuatro desenlaces que siguen: no hubo secreto, se
    // confirmó y no era una previsualización. Escribirlos una vez en vez de
    // repetirlos en cada retorno es lo que impide que dos sitios contesten
    // distinto sobre la misma corrida.
    ShipOutcome desenlaceDeLoEscrito({
      PublicationOutcome? remoto,
      String? headQueRechazoElCas,
      String? revisionConIndiceSucio,
    }) => ShipOutcome.derivar(
      verificacion: superficie.estado,
      huboSecreto: false,
      seConfirmo: true,
      soloPreview: false,
      autorizaIncompleto: entrada.allowIncomplete,
      remoto: remoto,
      headQueRechazoElCas: headQueRechazoElCas,
      revisionConIndiceSucio: revisionConIndiceSucio,
    );

    // 9 · El `.gitignore` del directorio de corridas, y su comprobación.
    //     Acá y no en el preflight: `.shipflow/` no existe en el primer uso, y
    //     exigirlo antes impediría exactamente ese primer uso.
    await asegurarGitignore(registro.raiz);
    final rutaDelDocumento = rutas.join(registro.raiz, 'runs', '$runId.json');
    if (!await corridasIgnoradas(repo, rutaDelDocumento)) {
      throw CorridasNoIgnoradas(rutaDelDocumento);
    }

    // 10 y 11 · Promover los objetos preparados y crear la revisión. **No
    //     mueve ninguna rama**: si el compare-and-swap se rechaza después,
    //     este objeto queda inalcanzable y el recolector lo junta.
    final revision = await candidato.createRevision();

    // 12 · `prepared`, CON la revisión. Entre crear el objeto y mover la
    //     referencia hay que poder persistir la identidad: si no, un proceso
    //     que muera en el medio deja una revisión que nadie anotó.
    var documento = DocumentoDeCorrida.preparado(
      revision: revision,
      draft: borrador,
    );
    await registro.escribir(runId, documento);

    // 13 · El compare-and-swap, condicionado a la base.
    final aplicado = await candidato.applyRevision();
    switch (aplicado) {
      case NotApplied(:final headObservado):
        return await _sellar(
          registro,
          runId,
          documento,
          desenlaceDeLoEscrito(headQueRechazoElCas: headObservado),
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
  } finally {
    // **En *todo* camino** —éxito, fallo, rechazo del usuario, excepción—. Hasta
    // acá hay un workspace, un índice y un almacén de objetos temporales en
    // disco, y un camino que salga sin liberarlos deja objetos y directorios
    // que nadie va a recoger. Es idempotente: liberar dos veces no falla.
    await candidato?.dispose();
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
Future<ShipOutcome> _sellar(
  RegistroDeCorridas registro,
  String runId,
  DocumentoDeCorrida documento,
  ShipOutcome desenlace,
) async {
  await registro.escribir(
    runId,
    documento.avanzarA(
      DocumentoDeCorrida.estadoQueAfirma(desenlace)!,
      desenlace: desenlace,
    ),
  );
  return desenlace;
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
  final destino = File(
    rutas.join(registro.raiz, 'runs', '$runId.revision.json'),
  );
  await destino.parent.create(recursive: true);
  final temporal = File('${destino.path}.tmp');
  await temporal.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'formatVersion': DocumentoDeCorrida.versionActual, 'revision': documento.revision, 'artefacto': documento.draft.artefacto.toJson()})}\n',
    flush: true,
  );
  await temporal.rename(destino.path);
}
