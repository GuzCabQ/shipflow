/// El reintento de `--retry-publication`: **terminar una corrida que ya
/// commiteó, sin volver a correr la cascada**.
///
/// **Acá tampoco se inventa nada**, igual que en la orquestación de una
/// corrida nueva: el filtro por estado, las dos reconciliaciones de §9, las
/// cuatro lecturas del objeto commit, la comparación del índice acotada a las
/// rutas de la rebanada, la fábrica del desenlace para una corrida cuyas
/// compuertas ya son historia y la transición del documento ya existen y ya
/// están probadas cada una por su lado. Lo que este archivo agrega es el
/// ORDEN en que se llaman y de dónde sale cada hecho.
///
/// **Lo que NO vuelve a correr, y es el punto entero de este camino:** la
/// cascada, la detección de secretos, la compuerta por estado y la
/// confirmación. El documento de la corrida lleva el borrador completo
/// justamente para eso: lo que esas cuatro decidieron ya está decidido y ya
/// está registrado, y volver a decidirlo sobre hechos que nadie volvió a
/// medir es la forma más cara de contradecirse.
///
/// **Tampoco hay previsualización ni pregunta de confirmación.** No hay nada
/// que autorizar que no se haya autorizado ya: quien corrió la corrida
/// original vio la previsualización y confirmó, y el commit que este camino
/// publica es exactamente el que aquélla dejó.
///
/// **Residuo declarado: la proyección local de la revisión no se escribe.**
/// El paso 14 de una corrida nueva la deja al lado del documento cuando
/// promueve a `committed`; un reintento que promueve desde `prepared` o desde
/// `localInconsistent` no pasa por ese paso, así que esa corrida termina con
/// documento y sin proyección. No se agrega acá porque la proyección es
/// evidencia de lo que la corrida original miró —y esta no miró nada nuevo—,
/// y escribirla desde dos lugares distintos es cómo las dos empiezan a
/// divergir. Queda dicho en vez de disimulado.
library;

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import '../corrida.dart';

/// Lo que produce un reintento.
///
/// **Sellada, y con una sola variante que lleva desenlace.** Un reintento que
/// no actúa no tiene [ShipOutcome] que informar —no publicó, no selló y no
/// cambió nada—, y fabricarle uno sería exactamente lo que los constructores
/// privados de [ShipOutcome] existen para impedir. Las otras variantes llevan
/// los hechos de su propia detención, y **quién las traduce a un código de
/// proceso es la raíz de composición y nadie más**: decidir el código en dos
/// lugares es cómo dos sitios terminan contestando distinto sobre la misma
/// corrida.
///
/// **No salen por excepción**, a diferencia de las cuatro detenciones de una
/// corrida nueva. Aquéllas describen por qué no llegó a haber corrida; éstas
/// contestan un pedido de terminar una, y **lo que contestan no es siempre
/// sobre una corrida que exista**: tres de las siete variantes sin desenlace
/// de abajo —contadas sobre esta misma jerarquía sellada, una por una—
/// informan justamente lo contrario, que no hay ningún documento con ese
/// identificador, que hay uno que ninguna lectura pudo interpretar, o que el
/// que hay dice ser de otra corrida. Que viajen como valor es lo que deja que la
/// raíz de composición las despache con un `switch` exhaustivo: una variante
/// nueva no compila hasta que alguien decida su código.
sealed class ResultadoDelReintento {
  const ResultadoDelReintento();
}

/// El reintento publicó, y acá está el desenlace.
///
/// [documentoNoEscrito] es el mismo hecho —y por el mismo motivo— que ya
/// lleva el resultado de una corrida nueva: el desenlace ya está medido, con
/// un pull request abierto del otro lado, y un fallo de la ANOTACIÓN no puede
/// llevárselo.
final class ReintentoConDesenlace extends ResultadoDelReintento {
  final ShipOutcome desenlace;
  final bool documentoNoEscrito;

  const ReintentoConDesenlace({
    required this.desenlace,
    required this.documentoNoEscrito,
  });
}

/// No hay ninguna corrida con ese identificador.
///
/// **Lleva dónde se buscó, y no es decoración.** El documento vive en una
/// ruta derivada del identificador y de la raíz del registro; quien se
/// equivocó de identificador —o borró el directorio de corridas— no tiene
/// cómo saber cuál de las dos cosas pasó sin ver la ruta que se miró.
final class CorridaDesconocida extends ResultadoDelReintento {
  final String runId;
  final String dondeSeBusco;

  const CorridaDesconocida({required this.runId, required this.dondeSeBusco});
}

/// El documento existe y no se puede leer.
///
/// **Es un hecho distinto de [CorridaDesconocida], y no comparte variante con
/// ella.** «No hay ninguna corrida así» manda a revisar el identificador; «la
/// corrida está y su documento no se puede interpretar» manda a mirar el
/// archivo. Y hay una causa concreta que no es corrupción: un documento
/// escrito por una versión con otra forma se rechaza al leerlo, y decirle a
/// quien corre que su corrida no existe sería falso.
///
/// **Por qué no sube como excepción hasta la red de último recurso.** Ahí
/// saldría `70` —«se rompió el arnés, reportalo con la traza»— sobre una
/// corrida donde el arnés no se rompió: lo que falta es una precondición del
/// entorno, que es lo que el `4` nombra.
final class CorridaIlegible extends ResultadoDelReintento {
  final String runId;
  final String dondeSeBusco;

  /// Qué dijo la lectura al fallar. **Se cita lo que la lectura informó**, sin
  /// volver a derivar nada: `fromJson` ya distingue «esto se corrompió» de
  /// «esto es de una forma más vieja», y reescribir ese diagnóstico acá sería
  /// perderlo.
  final String porQue;

  const CorridaIlegible({
    required this.runId,
    required this.dondeSeBusco,
    required this.porQue,
  });
}

/// El documento que hay en esa ruta dice ser de OTRA corrida.
///
/// **Es un hecho distinto de [CorridaIlegible], y por eso no comparte
/// variante con ella.** Ese documento se lee perfectamente: lo que no cierra
/// es que el identificador que lleva adentro no sea el que se pidió. Decirle
/// a quien corre que su documento está corrupto lo mandaría a mirar el
/// archivo buscando un daño que no existe.
///
/// **Y es la tercera comprobación del identificador, después de la gramática
/// y de la ruta.** Las dos primeras miran la CADENA y la RUTA; ésta mira el
/// CONTENIDO, que es lo único que puede desmentir que el archivo que se abrió
/// sea el de la corrida que se nombró — un archivo movido, renombrado o
/// copiado a mano pasa las dos anteriores y sigue siendo de otra corrida. Sin
/// ella, el reintento publica el commit de una corrida creyendo que termina
/// otra, y sella el documento con un desenlace que no es suyo.
final class CorridaConOtroIdentificador extends ResultadoDelReintento {
  /// El que pidió quien corre.
  final String runId;

  /// El que el documento lleva adentro.
  final String elDelDocumento;

  final String dondeSeBusco;

  const CorridaConOtroIdentificador({
    required this.runId,
    required this.elDelDocumento,
    required this.dondeSeBusco,
  });
}

/// La puerta por rama y por estado dijo que no.
final class ReintentoRechazado extends ResultadoDelReintento {
  final NoSeReintenta porQue;

  const ReintentoRechazado(this.porQue);
}

/// La reconciliación no cerró: no se puede confirmar que la revisión de la
/// rama sea la de este candidato, o el índice local no coincide con ella.
///
/// **Las dos reconciliaciones de §9 desembocan acá**, y no en dos variantes
/// distintas, porque [CausaDeAmbiguedad] ya distingue cuál de los cinco pasos
/// no cerró — incluido el del índice, que es el único que produce la
/// comprobación desde `localInconsistent`. Partirla en dos pondría el mismo
/// hecho en dos lugares que podrían llegar a discrepar.
final class ReintentoAmbiguo extends ResultadoDelReintento {
  final CausaDeAmbiguedad causa;
  final String detalle;

  const ReintentoAmbiguo({required this.causa, required this.detalle});
}

/// La reconciliación cerró sin ambigüedad y lo que dijo **no es promover**:
/// no hay ninguna revisión nuestra en la rama sobre la que publicar.
///
/// Desde `prepared` son los dos casos que la comparación de tres casos
/// contesta cuando el `HEAD` no es la revisión candidata: el compare-and-swap
/// nunca corrió, o la rama avanzó a otra cosa. **Desde `localInconsistent`
/// sale también**, con [QueHacerAlRecuperar.alguienMasAvanzo], cuando la rama
/// dejó de estar en la revisión de esta corrida: ahí el compare-and-swap sí
/// corrió, y lo que ya no vale es que lo que dejó siga puesto.
///
/// Ninguno de los casos se arregla desde acá —el
/// almacén de objetos del candidato que haría falta para reintentar el
/// compare-and-swap se liberó cuando aquella corrida terminó—, así que la
/// alternativa es la misma para todos y [detalle] la nombra.
///
/// **Y por eso lleva [enLaRama], que es la lección de haberla reusado.**
/// Reusar un desenlace **arrastra su prosa**, y esa prosa se escribió para el
/// origen que ya tenía: el encabezado que esta variante producía decía «no
/// dejó ninguna revisión en la rama», defendible desde `prepared` —ahí nadie
/// sabe si el compare-and-swap llegó a correr— y **falso** desde
/// `localInconsistent`, un estado que no existe sin que ese compare-and-swap
/// haya corrido. Quedaba un encabezado contradiciendo a su propia línea
/// siguiente, que es la forma más cara de mentirle a quien corre.
///
/// Es una forma de falso motivo que esta rebanada no había nombrado: no uno
/// que envejeció, sino uno que **era cierto y dejó de serlo al ganar un
/// segundo llamador**. El día que aparezca un tercero, lo que hay que mirar
/// no es si el valor de [queHacer] le sirve —le servía, y era correcto— sino
/// si el texto que se deriva de acá sigue siendo cierto para él.
final class SinRevisionEnLaRama extends ResultadoDelReintento {
  final QueHacerAlRecuperar queHacer;
  final String detalle;

  /// Qué se puede afirmar de la revisión de esta corrida, para que quien
  /// escribe el texto y el payload no tenga que adivinarlo.
  final LaRevisionEnLaRama enLaRama;

  const SinRevisionEnLaRama({
    required this.queHacer,
    required this.detalle,
    required this.enLaRama,
  });
}

/// Qué se sabe de la revisión de la corrida cuando el `HEAD` **no** es ella.
///
/// **No es un valor más de [QueHacerAlRecuperar], y esa fue la decisión.** Ese
/// enum es el dominio cerrado de la comparación de tres casos, y lo que
/// contesta acá —«la rama avanzó a otra cosa»— es **correcto** por los dos
/// orígenes: literalmente avanzó. Agregarle un cuarto valor metería en ese
/// dominio uno que la comparación de tres casos no puede producir nunca —una
/// fila inalcanzable, que es exactamente lo que este proyecto ya rechazó al
/// dejar [CausaDeNoIntento] en cuatro y no en cinco—. La falsedad no estaba en
/// la causa: estaba en la PROSA, y la prosa la elige quien compone. Así que lo
/// que viaja es el hecho que le falta a quien compone, y nada más.
enum LaRevisionEnLaRama {
  /// **Puede no estar.** Desde `prepared`, el compare-and-swap pudo no haber
  /// corrido nunca, así que puede no haber ninguna revisión de esta corrida
  /// en la rama.
  puedeNoEstar,

  /// **Está, y lo que dejó de valer es que esté PUESTA.** Desde
  /// `localInconsistent` el compare-and-swap ya corrió —ese estado no existe
  /// de otra forma— y la rama siguió andando por encima: la revisión sigue
  /// ahí, de antepasado del `HEAD`.
  estaPeroNoPuesta,
}

/// Un ensayo: se miró todo y **no se escribió ni se publicó nada**.
///
/// El corte vive lo más tarde posible —después de la puerta y después de la
/// reconciliación— a propósito: lo único que un ensayo del reintento puede
/// producir es la respuesta a «¿esto terminaría bien?», y cortar antes la
/// dejaría sin contestar.
final class ReintentoEnsayado extends ResultadoDelReintento {
  final String runId;
  final String revision;

  const ReintentoEnsayado({required this.runId, required this.revision});
}

/// Termina la corrida [runId]: la publica si corresponde, y sella el
/// documento con el desenlace que salga.
///
/// **[ramaActual] llega leída de afuera**, por lo mismo que la corrida nueva
/// la recibe así: es una lectura que puede fallar por no estar parado en un
/// repositorio, y esa es una precondición del entorno, no un desenlace.
///
/// **El árbol de la revisión se lee UNA vez**, y esa única lectura alimenta
/// dos consumidores: el paso 2 de la reconciliación de los cinco pasos y el
/// tercer argumento de la solicitud del pull request. Dos lecturas del mismo
/// hecho pueden discrepar entre sí —y entonces la guarda del constructor de
/// la solicitud validaría contra una y el paso 2 contra la otra—, así que no
/// hay dos.
Future<ResultadoDelReintento> correrReintento({
  required String runId,
  required RegistroDeCorridas registro,
  required RepositorioGit repo,
  required PullRequestSink forja,
  required String ramaActual,

  /// **A dónde publicaría este repositorio HOY**, o nulo si su remoto no
  /// nombra ningún destino.
  ///
  /// **Llega leído de afuera**, por lo mismo que [ramaActual]: sale del
  /// remoto configurado, que es una lectura del entorno, y quien la
  /// convierte en una identidad es el paquete que sabe quién atiende cada
  /// remoto — nunca este archivo, que no sabe leer una URL de `git`.
  required String? destinoActual,
  required bool dryRun,
}) async {
  final DocumentoDeCorrida? leido;
  try {
    leido = await registro.leer(runId);
  } on Object catch (e) {
    // **Se atrapa todo y no una lista de tipos**, que es la excepción a la
    // regla del proyecto y por eso se argumenta: leer un documento falla por
    // tres familias —no se pudo abrir el archivo, no es JSON, no tiene la
    // forma esperada— y la tercera llega como error y no como excepción. Una
    // lista de tipos dejaría afuera justamente el caso que más importa acá,
    // que es el documento de una forma más vieja.
    return CorridaIlegible(
      runId: runId,
      dondeSeBusco: registro.documentoDe(runId),
      porQue: '$e',
    );
  }
  if (leido == null) {
    return CorridaDesconocida(
      runId: runId,
      dondeSeBusco: registro.documentoDe(runId),
    );
  }
  final documento = leido;

  // **El documento tiene que decir que es de la corrida que se pidió.** La
  // ruta se deriva del identificador, pero el contenido no: un archivo
  // copiado, renombrado o movido a mano cae en la ruta correcta con el
  // borrador de otra corrida adentro, y desde acá para abajo todo —la rama,
  // el estado, la revisión, las rutas de la rebanada— se lee de ese borrador
  // ajeno. Se comprueba antes de la puerta porque la puerta ya decide sobre
  // esos datos.
  if (documento.draft.runId != runId) {
    return CorridaConOtroIdentificador(
      runId: runId,
      elDelDocumento: documento.draft.runId,
      dondeSeBusco: registro.documentoDe(runId),
    );
  }

  final puerta = puertaDelReintento(
    documento: documento,
    ramaActual: ramaActual,
    destinoActual: destinoActual,
  );
  switch (puerta) {
    case NoSeReintenta():
      // Antes de leer nada del repositorio: los tres motivos de no reintentar
      // se contestan con el documento y la rama, y una corrida que no se
      // reintenta no tiene por qué pagar una lectura más.
      return ReintentoRechazado(puerta);

    case PublicarDirecto():
      return await _publicar(
        documento: documento,
        arbolDeLaRevision: await repo.arbolDe(documento.revision),
        forja: forja,
        registro: registro,
        runId: runId,
        dryRun: dryRun,
      );

    case Reconciliar():
      return await _reconciliarYPublicar(
        documento: documento,
        repo: repo,
        forja: forja,
        registro: registro,
        runId: runId,
        dryRun: dryRun,
      );
  }
}

/// Reconstruye la confianza en el candidato y, si cierra, publica.
///
/// **Cuál de las dos reconciliaciones de §9 corre lo decide el estado del
/// documento, acá y no adentro de [Reconciliar].** Es lo que el doc de esa
/// variante pide explícitamente: cargar la elección como un campo suyo
/// pondría el mismo hecho —qué estado tiene el documento— en dos lugares que
/// podrían discrepar.
///
/// **Y es un `if` y no un `switch` exhaustivo sobre los seis estados, a
/// propósito.** El lugar donde un estado nuevo tiene que forzar una decisión
/// ya existe y es el `switch` sin comodín de [puertaDelReintento]: mientras
/// ese estado nuevo no se despache como [Reconciliar], acá no llega; y el día
/// que alguien lo despache así, la decisión que tiene que tomar es cuál de
/// las dos reconciliaciones le toca, que es exactamente la pregunta que esta
/// función hace. Repetir acá los seis casos sería una segunda exhaustividad
/// sobre el mismo dominio, con cuatro ramas que nadie puede alcanzar.
Future<ResultadoDelReintento> _reconciliarYPublicar({
  required DocumentoDeCorrida documento,
  required RepositorioGit repo,
  required PullRequestSink forja,
  required RegistroDeCorridas registro,
  required String runId,
  required bool dryRun,
}) async {
  final candidato = documento.draft.artefacto.candidato;

  // El árbol que el candidato declaró, y las rutas que la rebanada declaró:
  // las dos salen del documento, que es donde la corrida original las
  // persistió. Derivarlas de nuevo acá crearía una segunda fuente del mismo
  // hecho — y una ruta declarada cuyo contenido no cambió no aparece en
  // ningún diff, así que derivarla la sacaría del control sin que nadie lo
  // note.
  final rutasQueDifieren = await repo.rutasQueDifierenDelArbol(
    arbol: candidato.contentRevision,
    rutas: documento.draft.rutas,
  );

  // **El `HEAD` se lee UNA vez y alimenta a los dos caminos**, por lo mismo
  // que el árbol de la revisión: dos lecturas del mismo hecho pueden
  // discrepar entre sí, y entonces cada camino estaría decidiendo sobre una.
  final headActual = await repo.head;

  if (documento.estado == EstadoDelDocumento.localInconsistent) {
    // **La asimetría entre las dos reconciliaciones se CIERRA acá, no se
    // argumenta.** Desde `prepared`, la comparación de tres casos exige que
    // el `HEAD` sea la revisión candidata antes de mirar nada más; desde
    // `localInconsistent` no lo exigía nadie, y era defendible —el documento
    // afirma que el compare-and-swap corrió— pero lo que el documento afirma
    // es lo que pasó ENTONCES, no dónde está la rama AHORA. Sin esta
    // comprobación quedaban dos salidas falsas sobre la misma corrida: el
    // comando de reparación apunta a un commit que ya no es el `HEAD` —y
    // reparar con él deja el índice discrepando con la rama—, y el camino
    // que promueve abre un pull request cuyo contenido incluye lo que otro
    // commiteó encima, sobre un artefacto que solo afirma la verificación de
    // este candidato. Lo segundo es exactamente el falso verde que esta
    // rebanada entera existe para cerrar.
    if (headActual != documento.revision) {
      return SinRevisionEnLaRama(
        queHacer: QueHacerAlRecuperar.alguienMasAvanzo,
        // **Acá SÍ se sabe que el compare-and-swap corrió**, porque este
        // estado no existe de otra forma: la revisión está en la rama, de
        // antepasado del `HEAD`, y lo que dejó de valer es que esté puesta.
        enLaRama: LaRevisionEnLaRama.estaPeroNoPuesta,
        detalle:
            'La rama «${documento.draft.branch}» está en «$headActual», y '
            'esta corrida commiteó «${documento.revision}»: ya no es la '
            'revisión de esta corrida la que está puesta. Desde acá no se '
            'puede reparar el índice ni publicar —el comando de reparación '
            'apuntaría a un commit que ya no es el HEAD, y publicar abriría '
            'un pull request con lo que se commiteó encima adentro, sobre un '
            'artefacto que solo afirma la verificación de este candidato—. '
            'La forma de seguir es volver a correr `ship` desde el principio.',
      );
    }

    switch (comprobarIndice(
      documento: documento,
      rutasQueDifieren: rutasQueDifieren,
    )) {
      case IndiceNoCoincide(:final detalle):
        return ReintentoAmbiguo(
          causa: CausaDeAmbiguedad.indiceDistinto,
          detalle: detalle,
        );
      case IndiceCoincide():
        return await _publicar(
          documento: documento.avanzarA(EstadoDelDocumento.committed),
          arbolDeLaRevision: await repo.arbolDe(documento.revision),
          forja: forja,
          registro: registro,
          runId: runId,
          dryRun: dryRun,
        );
    }
  }

  // Los cinco pasos, desde `prepared`. El árbol se lee ACÁ y viaja a los dos
  // consumidores —el paso 2 y la solicitud—: ver el doc de [correrReintento].
  final arbolDeLaRevision = await repo.arbolDe(documento.revision);
  final hechos = HechosDeLaRevision(
    padre: await repo.padreDe(documento.revision),
    arbol: arbolDeLaRevision,
    mensaje: await repo.mensajeDe(documento.revision),
    rutasQueDifieren: rutasQueDifieren,
  );
  switch (reconciliar(
    documento: documento,
    // La comparación de tres casos pide el `HEAD` como argumento a propósito:
    // no lee el repositorio, y por eso sus casos se prueban sin montar uno.
    // Es la MISMA lectura que usa el otro camino, de más arriba.
    headActual: headActual,
    hechos: hechos,
  )) {
    case Ambigua(:final causa, :final detalle):
      return ReintentoAmbiguo(causa: causa, detalle: detalle);
    case Inequivoca(queHacer: QueHacerAlRecuperar.promoverACommitted):
      return await _publicar(
        documento: documento.avanzarA(EstadoDelDocumento.committed),
        arbolDeLaRevision: arbolDeLaRevision,
        forja: forja,
        registro: registro,
        runId: runId,
        dryRun: dryRun,
      );
    case Inequivoca(:final queHacer):
      return SinRevisionEnLaRama(
        queHacer: queHacer,
        // **Desde `prepared` no se sabe si el compare-and-swap corrió**, y
        // por eso este origen sí puede decir que puede no haber ninguna
        // revisión de esta corrida en la rama.
        enLaRama: LaRevisionEnLaRama.puedeNoEstar,
        detalle:
            'No hay ninguna revisión de esta corrida en la rama: el '
            'compare-and-swap no llegó a moverla, o la rama avanzó a otra '
            'cosa. Reintentarlo desde acá no es posible —el almacén de '
            'objetos que el candidato usaba se liberó cuando aquella corrida '
            'terminó—, así que la forma de seguir es volver a correr `ship` '
            'desde el principio: el candidato se reconstruye sobre el HEAD '
            'de ahora.',
      );
  }
}

/// Abre el pull request de [documento] y sella el resultado.
///
/// **[documento] llega ya promovido a `committed`** cuando venía de un estado
/// que había que reconciliar: la promoción es en memoria y el disco se toca
/// una sola vez, al sellar. Persistir el paso intermedio agregaría una
/// escritura que ningún lector observa —quien muera entre las dos vuelve a
/// entrar por el mismo camino y vuelve a reconciliar, que es barato y no
/// depende de lo que haya quedado anotado.
Future<ResultadoDelReintento> _publicar({
  required DocumentoDeCorrida documento,
  required String arbolDeLaRevision,
  required PullRequestSink forja,
  required RegistroDeCorridas registro,
  required String runId,
  required bool dryRun,
}) async {
  // **El tercer argumento es una MEDICIÓN, no un dato del documento.** El
  // constructor exige el árbol de la revisión y valida su relación con lo que
  // el candidato declaró haber expuesto a los controles; pasarle el
  // `contentRevision` del candidato satisface esa guarda comparando el valor
  // contra sí mismo, y la vacía. Que el árbol leído del repositorio coincida
  // con el del candidato no es una suposición: es el paso 2 de la
  // reconciliación, y por el camino directo es esta guarda la única que
  // queda.
  //
  // **Residuo declarado: si esa guarda rechaza, el rechazo sale como error
  // interno del arnés.** El constructor lanza `ArgumentError` —una solicitud
  // mal compuesta es un defecto de quien compone, y así lo declara— y eso
  // sube hasta la red de último recurso. Solo es alcanzable editando el
  // documento a mano: el árbol de un objeto commit no cambia nunca, así que
  // sobre cualquier documento que haya escrito una corrida real el valor
  // medido y el declarado son el mismo. Las dos salidas posibles cuestan más
  // de lo que compran: atrapar ese `ArgumentError` usaría como señal de
  // control de flujo esperado una excepción documentada como «algo que este
  // control no previó», y comparar los dos valores acá antes de construir
  // sería una TERCERA copia de la misma regla —ya está en el paso 2 de la
  // reconciliación y en el constructor— que además dejaría sin quien la mate
  // a la única prueba que distingue medir de copiar.
  final solicitud = PullRequestRequest(
    draft: documento.draft,
    revision: documento.revision,
    arbolDeLaRevision: arbolDeLaRevision,
  );

  // **El corte del ensayo, después de armar la solicitud y antes de abrirla.**
  // Armarla no tiene efecto —es un valor— y es lo último que se puede
  // comprobar sin escribir nada; abrirla sí lo tiene, y sellar también.
  if (dryRun) {
    return ReintentoEnsayado(runId: runId, revision: documento.revision);
  }

  final remoto = await forja.open(solicitud);

  // **La verificación se LEE del artefacto que la corrida original persistió,
  // nunca se vuelve a decidir.** Y sale por la fábrica del reintento y no por
  // la de una corrida nueva: aquélla volvería a correr la compuerta por
  // estado sobre una corrida cuya compuerta ya es historia, y para eso habría
  // que alimentarla con hechos fabricados —«se confirmó», «autoriza
  // incompleto»— que nadie midió acá.
  //
  // `!` y no un `if`: [EstadoPublicable.desde] solo devuelve nulo para
  // `errorInterno`, y una corrida con el arnés roto nunca pasa la compuerta,
  // así que jamás llega a commitear ni a escribir el documento que este
  // camino acaba de leer.
  final verificacion = EstadoPublicable.desde(
    documento.draft.artefacto.superficie.estado,
  )!;
  final desenlace = ShipOutcome.derivarReintento(
    verificacion: verificacion,
    remoto: remoto,
  );

  // El estado no se elige a mano: lo determina el desenlace, igual que al
  // sellar una corrida nueva. `!` por el mismo motivo que allá: el único
  // desenlace que no afirma ningún estado es el que no intentó, y de esta
  // fábrica solo salen los dos de publicación.
  final destino = DocumentoDeCorrida.estadoQueAfirma(desenlace)!;
  if (destino == documento.estado) {
    // **Un reintento que vuelve a quedar incompleto NO reescribe el
    // documento, y no es una omisión.** El grafo de §9 no tiene la arista de
    // `publicationIncomplete` a sí mismo —y no debería tenerla: el estado no
    // cambió—, así que pedir la transición lanzaría, y ese `StateError`
    // saldría por la red de último recurso como «se rompió el arnés» sobre
    // una corrida donde lo único que pasó es que el remoto volvió a fallar.
    // Lo que se pierde es la causa nueva del fallo remoto, que igual viaja
    // entera en el desenlace que sale de acá; lo que se gana es que el
    // documento siga diciendo exactamente lo que dice.
    return ReintentoConDesenlace(
      desenlace: desenlace,
      documentoNoEscrito: false,
    );
  }
  final sellado = documento.avanzarA(destino, desenlace: desenlace);
  try {
    await registro.escribir(runId, sellado);
  } catch (_) {
    // **Y un fallo de la ESCRITURA no se lleva el desenlace**, por el mismo
    // argumento que ya vale al sellar una corrida nueva: con el pull request
    // ya abierto del otro lado, dejar que la anotación se lo lleve convierte
    // el hecho más caro de toda la corrida en un `70` mudo. El fallo no se
    // traga: sale por este campo hasta el payload.
    return ReintentoConDesenlace(
      desenlace: desenlace,
      documentoNoEscrito: true,
    );
  }
  return ReintentoConDesenlace(desenlace: desenlace, documentoNoEscrito: false);
}
