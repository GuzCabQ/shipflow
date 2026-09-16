/// Los puertos. **Solo interfaces: ninguna implementación vive acá.**
///
/// Todas las flechas apuntan hacia adentro. `core` no conoce ningún stack,
/// ningún CLI y ningún sistema de tickets; cuando necesita algo de ellos,
/// declara un puerto y espera que alguien de afuera lo satisfaga.
///
/// **Cuáles tienen implementación y cuáles no está declarado en
/// `arquitectura.json`** bajo `puertos-sin-implementacion`, con la fase en que
/// aparece cada uno. Esa lista se verifica en los DOS sentidos: un puerto nuevo
/// sin declarar falla, y una declaración que quedó vieja —porque el puerto ya
/// se implementó— también.
///
/// No se repite la cuenta acá. Un número en prosa que nada deriva envejece
/// solo, y este archivo ya lo hizo una vez.
library;

import 'alcance.dart';
import 'entidades.dart';
import 'credencial.dart';
import 'desenlace.dart';
import 'observacion.dart';
import 'publicacion.dart';
import 'regla.dart';
import 'valores.dart';

// --- Entrada -----------------------------------------------------------

/// De dónde salen los [WorkItem]. Solo lectura.
abstract interface class WorkItemSource {
  Future<WorkItem> fetch(String id);
  Future<List<WorkItem>> list();
}

/// Cómo se le contesta a la fuente. **Separado de [WorkItemSource] a
/// propósito**: leer un ticket no debería exigir permiso de escritura sobre él.
abstract interface class WorkItemFeedback {
  Future<void> comment(String workItemId, String body);
  Future<void> transition(String workItemId, String state);
}

/// Contexto adicional del que el trabajo depende y que no está en el código.
abstract interface class ContextSource {
  Future<List<QuotedText>> gather(WorkItem item);
}

// --- Stack · las implementa el plugin del lenguaje ---------------------

/// La topología del proyecto que se está trabajando.
///
/// **Cláusulas del contrato**, descubiertas al hacer diverger las dos
/// implementaciones. Valen para cualquier stack:
///
/// 1. **La lista devuelta es inmodificable.** Un llamador que la mutara
///    corrompería el resultado para todos los demás, y las dos
///    implementaciones dejarían de ser sustituibles — que es la única razón
///    por la que existe un fake.
/// 2. **`dependsOn` solo nombra paquetes que esta misma llamada devuelve.**
///    Una dependencia por ruta hacia afuera del proyecto es una dependencia
///    real, pero no es topología de ESTE proyecto: reportarla dejaría una
///    arista colgante hacia algo que nadie puede resolver.
abstract interface class ProjectTopology {
  Future<List<Package>> packages();
}

/// Qué artefactos produce y consume el stack, y cuáles no se tocan.
///
/// **Cláusulas del contrato, no de una implementación.** Las descubrió la suite
/// de contrato al hacer diverger a las dos implementaciones, y valen para
/// cualquier stack:
///
/// 1. **Lo generado nunca es editable.** No son dos hechos independientes: el
///    segundo se sigue del primero. Poder declarar algo generado y editable a
///    la vez sería un estado sin significado.
/// 2. **Una ruta vacía no es editable.** Devolver `true` dejaría al arnés
///    intentando escribir en ninguna parte.
/// 3. **Las rutas se comparan normalizadas.** Dos formas de escribir el mismo
///    archivo —con `.`, con `..`, con separadores distintos— tienen que dar la
///    misma respuesta. Si no, la cláusula 1 se puede esquivar escribiendo la
///    ruta de otra manera.
///
/// Lo que SÍ es del stack son los patrones: qué cuenta como generado. Eso lo
/// aporta el plugin y no aparece acá — si `core` conociera los sufijos de un
/// ecosistema, cambiar de ecosistema exigiría cambiar `core`.
///
/// Este comentario nombraba uno de esos sufijos como ejemplo, y el check de
/// cadenas lo rechazó. Tenía razón: la frase decía «si core conociera X» y al
/// escribirla, core conocía X.
abstract interface class ArtifactPolicy {
  bool isGenerated(String path);
  bool isEditable(String path);
}

/// Mira el alcance y devuelve **hechos por sujeto**, no conclusiones.
///
/// Existe porque el corolario 4 de ADR-011 dice que ningún verificador juzga
/// su propia cobertura, y declarar «este archivo no es mío» es exactamente
/// eso. El paso dejaba de ser juez de su ejecución y seguía siendo juez de su
/// incumbencia.
///
/// **Cláusulas del contrato:**
///
/// 1. **La observación es una partición de lo pedido**, y lo hace cumplir el
///    tipo. Un sujeto que se pierde acá no lo ve ninguna guardia posterior.
/// 2. **El sujeto vuelve tal como se pidió.** Canonizar para decidir el hecho
///    es necesario; renombrar lo devuelto rompe la partición.
/// 3. **No se pudo mirar y no era mío son distintos.** Lo primero es un sujeto
///    no observado con su causa; lo segundo, uno observado y ajeno con su
///    motivo. Confundirlos es el falso rojo simétrico del falso verde.
/// 4. **Se llama UNA vez por corrida, y la observación viaja.** Dos lecturas
///    del árbol pueden diferir, y entonces dos pasos verificarían alcances
///    distintos que el reporte declara iguales.
///
///    **Lo hace cumplir la forma de [Verifier.run], no la disciplina de
///    quien compone**: un paso recibe la [ScopeObservation] ya hecha y no
///    tiene con qué pedir otra. Antes cada paso guardaba su propio
///    `ScopeObserver` y volvía a llamar a `observe`, así que una corrida de
///    dos pasos leía el árbol tres veces. Estuvo instalado doce tareas y no
///    lo vio nadie, tapado por un comentario que afirmaba lo contrario.
///
///    **Y la salvaguarda que lo hacía tolerable no existía.** El paso
///    comparaba su lectura contra la que la cascada ya había vetado y
///    abortaba si discrepaban, pero comparaba NOMBRES: mientras el sujeto
///    siguiera siendo utilizable, un árbol de otro tamaño no divergía. Una
///    corrida podía reportar diez archivos de alcance con los verificadores
///    habiendo visto nueve, y salir verde. El comentario decía «falla
///    cerrada»; el código comparaba otra cosa.
abstract interface class ScopeObserver {
  Future<ScopeObservation> observe(List<String> requested);
}

/// Un paso de la cascada. **Devuelve su testigo junto con sus diagnósticos**:
/// un [Verifier] que devolviera solo diagnósticos no podría distinguir «limpio»
/// de «no corrí» (INV-2).
///
/// **Cláusulas del contrato.** Las descubrieron los dos primeros pasos reales
/// al diferir: uno puede comprobar su propia cobertura y el otro no, porque su
/// herramienta no la informa. Esa diferencia no se tapa — se declara.
///
/// 1. **Siempre devuelve un desenlace tipado; solo el ejecutado lleva
///    testigo.** Un intento que no llegó a completarse se declara [Aborted],
///    no un [Executed] con un testigo fingido: la terminación que antes vivía
///    suelta en [Witness] ahora es la diferencia entre las dos variantes.
/// 2. **Un alcance vacío es precondición violada, no un desenlace.** Invocar
///    con una lista de sujetos vacía no es un caso que el verificador declare
///    con ningún miembro de [VerificationOutcome]: es un error de quien lo
///    llama, y se comprueba antes de invocar nada — correr sobre nada y
///    correr sobre algo limpio no pueden dar la misma lectura.
/// 3. **El testigo nombra la invocación que de verdad se hizo.** Un testigo
///    que nombra otra cosa es peor que no tener testigo: da confianza sobre un
///    hecho que no ocurrió.
/// 4. **Lo que el paso NO pudo cubrir va en `witness.omitted`, con su
///    motivo.** Es el corolario 5 de ADR-011 vuelto dato: cada control
///    declara si puede detectar una omisión. El que no puede, lo escribe.
/// 5. **Recibe su alcance ya resuelto; no lo pide ni lo clasifica.** Es la
///    cláusula 4 de [ScopeObserver] vuelta firma: un verificador que tomara
///    los sujetos y mirara el árbol por su cuenta agregaría una lectura por
///    paso, y ningún invariante posterior puede reparar dos fotografías
///    distintas del mismo alcance.
///
///    **Y recibe un [VerificationScope], no la [ScopeObservation] entera.**
///    La primera versión de esta cláusula entregaba la observación completa,
///    con sus ajenos y sus no observados adentro. Eso deshizo en silencio una
///    garantía estructural que el `README` afirmaba —«un verificador ni
///    siquiera recibe los sujetos ajenos»— y dejó un falso verde a una
///    palabra de distancia: un paso que escriba `requested` donde quería
///    `usable()` certifica un ajeno, y el libro de obligaciones, que solo
///    mira lo que falta, lo daba por bueno. Lo encontró un review.
abstract interface class Verifier {
  String get id;

  /// Qué demuestra este control cuando ejecuta limpio, y **qué no**.
  ///
  /// Va acá y no en un registro aparte porque el límite lo sostiene quien
  /// ejecuta. Lo consume la fábrica de `AfirmacionCubierta`, que **no acepta
  /// una afirmación que no sea la de este control**.
  Afirmacion get afirmacion;

  Future<VerificationOutcome> run(VerificationScope alcance);
}

/// Se lanza cuando un [DiagnosticNormalizer] **no puede interpretar** lo que
/// le dieron. No es un hallazgo sobre el codigo del usuario: es el arnes
/// diciendo que no sabe leer lo que tiene delante.
///
/// Existe porque [DiagnosticNormalizer.normalize] devuelve una lista y nada
/// mas, asi que la unica forma de decir «no entendi» sin devolver la lista
/// vacia es no devolver. Quien lo atrape lo convierte en
/// [Verdict.noConcluyente], que es la categoria que ADR-011 creo para esto.
class UnreadableToolOutput implements Exception {
  /// El `source` del [QuotedText] que no se pudo leer: que invocacion lo
  /// produjo.
  final String source;

  /// Que no se pudo leer, y que hacer.
  final String reason;

  const UnreadableToolOutput(this.source, this.reason);

  @override
  String toString() => 'UnreadableToolOutput($source): $reason';
}

/// Traduce la salida cruda de una herramienta a [Diagnostic] normalizados.
///
/// **Clausulas del contrato.** Valen para cualquier herramienta de cualquier
/// stack, y son lo unico que la suite de contrato puede exigirle a las dos
/// implementaciones — los formatos concretos son del plugin.
///
/// 1. **Una entrada que no se puede interpretar lanza [UnreadableToolOutput];
///    nunca devuelve la lista vacia.** La lista vacia tiene una sola lectura
///    posible: «lei toda la salida y no habia nada que reportar». Si ademas
///    significara «no entendi», el verde del paso seria indistinguible de la
///    ceguera (ADR-011, corolario 1).
/// 2. **La entrada vacia es no interpretable.** Es el caso que se cuela, y no
///    es hipotetico: hay formatos de salida reales que escriben cero bytes
///    cuando no encontraron nada, y cero bytes es tambien lo que escribe una
///    herramienta que no llego a correr. Un normalizador que devuelva `[]`
///    ante el vacio le esta poniendo verde a las dos situaciones.
/// 3. **La lista devuelta es inmodificable**, por la misma razon que en
///    [ProjectTopology]: dos implementaciones dejan de ser sustituibles si una
///    permite que el llamador le corrompa el resultado a las demas.
/// 4. **El mensaje de cada [Diagnostic] es el de la herramienta, sin
///    reescribir** (INV-6). Lo que el normalizador entiende y el dominio no
///    —codigos, correcciones, lo que sea— va en `sourceMetadata`, que es la
///    escotilla `D-015`. Reescribir el mensaje perderia la unica cosa que el
///    arnes no puede regenerar: lo que la herramienta dijo de verdad.
abstract interface class DiagnosticNormalizer {
  /// Lanza [UnreadableToolOutput] si no puede interpretar [rawOutput].
  List<Diagnostic> normalize(QuotedText rawOutput);
}

/// Sabe cuándo hay que regenerar código y cómo.
abstract interface class CodegenTrigger {
  bool needsRun(List<String> changedFiles);
  Future<VerificationOutcome> run();
}

/// Resuelve el grafo de dependencias del proyecto trabajado.
abstract interface class DependencyResolver {
  Future<Map<String, List<String>>> graph();
}

/// El catálogo de clases de cambio. **Lo declara el plugin**: `core` solo sabe
/// que existen y que seleccionan estrategia.
abstract interface class ChangeClassCatalog {
  List<ChangeClass> all();
  ChangeClass? byId(String id);
}

// --- Agente · las implementa el adapter del CLI ajeno ------------------

/// Ejecuta el CLI agéntico del usuario en modo headless y normaliza sus
/// eventos a [Trace].
///
/// **Reemplaza al `ModelGateway` de la v0.1**: no hablamos con una API de
/// modelo, hablamos con el CLI que el usuario ya tiene instalado.
abstract interface class AgentRunner {
  Future<Trace> run(Plan plan, {required Duration budget});
}

/// Instala y retira los ganchos de la capa de ganchos.
///
/// **Toda instalación declara sus evasiones**: [Rule] rechaza en su
/// constructor cualquier regla de esa capa que no las traiga (INV-3).
abstract interface class HookInstaller {
  Future<void> install(List<Rule> rules);
  Future<void> uninstall();

  /// Qué hay instalado de verdad, leído del sistema y no de lo que creemos
  /// haber escrito.
  Future<List<String>> installed();
}

/// Sabe dónde van los archivos de la capa de prosa proyectada en cada CLI.
abstract interface class ContextProjector {
  Future<void> project(List<Rule> rules);
  Future<List<String>> targets();
}

// --- Salida e infraestructura ------------------------------------------

/// Por donde salen los cambios al mundo **local**: rama y commits.
///
/// **No sabe que existe una forja, y son dos puertos y no uno.** Lo decidió
/// ADR-014 sin nombrarlo: su invariante ejecutable exige que tras una
/// detención por presupuesto «la rama y todos los artefactos existen, y **no
/// hay PR abierto**». Ese estado tiene que ser alcanzable, estable e
/// inspeccionable. Un puerto que hiciera las dos cosas en una operación no
/// tendría un medio — sería una bandera adentro fingiendo que es atómico.
///
/// **Cláusulas del contrato:**
///
/// 1. **[apply] commitea EXACTAMENTE los archivos de la rebanada**, y eso
///    vale en los dos sentidos.
///
///    **Ni uno más**: barrer lo que hubiera suelto en el árbol metería en el
///    PR cambios que nadie planeó, y el artefacto de revisión los declararía
///    cubiertos —que por ADR-012 es pedirle a una persona que no los mire.
///
///    **Ni uno menos**: un archivo declarado que no produce ningún cambio es
///    un plan que dijo que iba a tocar algo y no lo tocó. La cláusula decía
///    «exactamente» y solo se comprobaba una dirección; la otra dejaba pasar
///    en verde una rebanada que no hizo lo que prometía.
///
///    **Y se comprueba ANTES de commitear.** Comprobarlo después solo puede
///    informar: la excepción dice la verdad y el commit indebido ya está en
///    la rama. Un invariante que solo se puede reportar no es un invariante,
///    es una crónica.
/// 2. **Una rebanada sin archivos no se commitea.** Un commit vacío afirma un
///    cambio que no existe.
/// 3. **[useBranch] es idempotente**: pedir dos veces la misma rama no falla.
///    La orquestación la pide al empezar y `--resume` la vuelve a pedir.
/// 4. **Lo que el stack no declara fuente no se AGREGA, y no se quita en
///    silencio.** Un artefacto generado versionado duplica la verdad y la deja
///    envejecer. Quitarlo de la rebanada sin decirlo rompería la cláusula 1 en
///    su segunda dirección, así que la rebanada se rechaza con su alternativa.
///    Quién decide qué es fuente no se sabe acá: es [ArtifactPolicy], y su
///    contenido vive en el plugin del stack.
///
///    **Borrarlo sí se puede**, y la distinción importa: la política dice qué
///    no se escribe, y sacar del repositorio algo que ya estaba versionado es
///    justamente lo que quiere. Prohibirlo dejaba al arnés sin manera de
///    limpiar lo que otro commiteó antes.
/// 5. **Lo que se inspecciona es el objeto que se commitea**, no una
///    representación suya. `apply` arma un índice aparte, lo inspecciona y
///    commitea ESE índice: si no, un gancho `pre-commit` puede reescribir el
///    archivo entre la inspección y el commit, y hay dos objetos donde el
///    contrato promete uno.
/// 6. **Un secreto corta el commit.** No lo reporta: un secreto commiteado no
///    se des-commitea —queda en el historial— y avisar después es una crónica,
///    no un control. Cumple INV-8 porque la alternativa existe y es concreta.
///    El corpus nunca le dio severidad a esto; la decisión se tomó al
///    construirlo y quedó registrada.
abstract interface class ChangeSink {
  /// La rama donde va el trabajo. La crea si no existe.
  ///
  /// **Enmienda:** el comentario anterior decia que la orquestacion la pide al
  /// empezar. Eso vale para `start`, que crea o cambia la rama **antes** de
  /// construir. `ship` no la llama: afirma la rama actual y falla en preflight
  /// si no coincide. Cambiar de rama despues de verificar invalidaria el
  /// candidato, porque el contenido expuesto a los controles dejaria de ser el
  /// que se va a commitear.
  Future<void> useBranch(String name);

  /// Prepara el **candidato**: fija qué contenido exacto se va a verificar, y
  /// lo materializa aparte para que los controles corran sobre eso.
  ///
  /// **Sin esto el artefacto no puede contestar su pregunta.** Entre que la
  /// cascada mira los archivos y [apply] los stagea, el contenido puede
  /// cambiar —el usuario, el IDE, un watcher, un generador, otro proceso— y
  /// [apply] commitea lo que exista en ese momento. La ventana es real y no
  /// depende de concurrencia exótica.
  ///
  /// **No deja efectos persistentes.** La preparación es reversible por
  /// completo hasta que alguien autorice: lo que produce vive en almacenes
  /// temporales, y [PreparedCandidate.dispose] los borra. Recién
  /// [PreparedCandidate.commit] escribe en el repositorio.
  Future<PreparedCandidate> prepareCandidate(PullRequestSlice slice);

  /// Deja la rebanada commiteada y devuelve la revisión resultante.
  ///
  /// **Stagea en el momento del commit**, así que entre lo que un control mire
  /// y lo que se commitee puede haber cambiado el contenido. Quien necesite
  /// que sean el mismo objeto usa [prepareCandidate]; los dos caminos escriben,
  /// y los dos rechazan una rebanada con secretos.
  ///
  /// **Recibe [PullRequestSlice] y no [Plan]** porque el caso «solo PR» de
  /// `docs/04` entra sin `WorkItem`, y `Plan.workItemId` es obligatorio. La
  /// rebanada lleva lo único que hace falta para commitear: qué archivos y por
  /// qué — su `intent`, que es lo que ADR-014 llama intención.
  Future<String> apply(PullRequestSlice slice);
}

/// Un candidato ya fijado: **el contenido está decidido y todavía no se
/// commiteó**.
///
/// Es un recurso con ciclo de vida. Quien lo abrió es quien lo cierra: hay que
/// llamar a [dispose] en **todo** camino —éxito, fallo, rechazo del usuario,
/// interrupción— porque hasta entonces hay directorios y objetos temporales en
/// disco.
abstract interface class PreparedCandidate {
  /// Qué contenido se expuso a los controles, y sobre qué base.
  CandidateIdentity get identity;

  /// La raíz donde el candidato quedó materializado. **Los controles corren
  /// acá**, no sobre el árbol de trabajo del usuario.
  String get root;

  /// Qué rutas cambian entre la base y el contenido. La cláusula del puerto es
  /// igualdad literal con los archivos de la rebanada, en los dos sentidos:
  /// ni una de más ni una de menos.
  List<String> get changedPaths;

  /// Rutas que el candidato **contiene y no materializó**, cada una con su
  /// motivo. Nunca se omiten en silencio.
  List<RutaNoMaterializada> get noMaterializadas;

  /// Qué entradas versionadas del candidato dejaron de coincidir con su árbol.
  ///
  /// Vacío significa intacto.
  ///
  /// **Una ruta nueva cuenta salvo que la política de artefactos del stack la
  /// declare artefacto.** Derivar el entorno genera archivos, y generarlos es
  /// su trabajo; pero un archivo de fuente nuevo, un manifiesto nuevo o un
  /// efecto lateral de un verificador **no** son eso, y la cascada los lee
  /// igual que a los demás. La primera versión de esta cláusula decía que
  /// **ningún** archivo nuevo contaba, y con eso un archivo de fuente creado entre la
  /// derivación y el segundo control dejaba la corrida en rojo, concluyendo
  /// sobre bytes que el candidato nunca fijó. Está reproducido.
  ///
  /// **Lo declarado en [noMaterializadas] tampoco cuenta**, porque el candidato
  /// lo dejó afuera a sabiendas — pero si alguien escribió algo en esa ruta,
  /// eso sí cuenta.
  ///
  /// Se comprueba **dos veces**, y las dos tienen su motivo: después de derivar
  /// el entorno, contra que la derivación haya borrado contenido versionado
  /// —está medido que lo hace—; y después de la cascada, contra que un
  /// verificador haya escrito en el workspace, que nada le impide.
  ///
  /// Una alteración hace la corrida **no concluyente, nunca roja**: no se puede
  /// afirmar nada sobre un árbol que dejó de ser el que se fijó.
  Future<List<AlteracionDelCandidato>> alteraciones();

  /// Crea la revisión y devuelve su identificador. **No mueve ninguna rama.**
  ///
  /// Es el primer paso que escribe en el repositorio, y está separado de
  /// [applyRevision] por una razón de recuperación, no de estilo: entre crear
  /// el objeto y mover la referencia hay que poder **persistir la revisión**.
  /// Si las dos cosas fueran una, un proceso que muriera en el medio dejaría
  /// una revisión que no quedó anotada en ningún lado, y quien intentara
  /// recuperar no tendría identidad que consultar. Como crear un commit no
  /// mueve nada, hacerlo antes no tiene efecto observable.
  ///
  /// **Se niega si la rebanada trae un secreto**, antes de escribir nada.
  ///
  /// Idempotente: llamarla dos veces devuelve la misma revisión.
  Future<String> createRevision();

  /// Mueve la rama a la revisión ya creada, **condicionado a que la base no se
  /// haya movido**.
  ///
  /// Exige que [createRevision] haya corrido: aplicar sin haber podido
  /// persistir la revisión es exactamente la ventana que la separación cierra.
  Future<CommitOutcome> applyRevision();

  /// Borra todo lo temporal. **Idempotente**: se puede llamar dos veces, y hay
  /// que poder llamarla desde un manejador de señal.
  Future<void> dispose();
}

/// Deja el candidato en condiciones de ser verificado.
///
/// **Lo aporta el plugin del stack**, porque qué hace falta para ejecutar es
/// conocimiento del lenguaje: este paquete no puede saberlo y `orchestration`
/// no puede verlo.
///
/// El entorno se **deriva** del candidato —de lo que el candidato fijó—, nunca
/// se presta del árbol de trabajo del usuario: prestarlo haría que la cascada
/// midiera sobre resoluciones que ningún commit contiene.
///
/// **Lleva presupuesto porque abre un subproceso**, y recibe los archivos del
/// alcance porque deriva una vez por cada raíz de resolución que la rebanada
/// toca: un manifiesto que la rebanada no toca no existe para ella, y derivar
/// raíces que nadie necesita es pagar por nada el riesgo de una toolchain que
/// acá está y en el runner no.
///
/// **No hay `dispose`**: lo que la derivación escribe vive dentro de
/// `candidateRoot`, y [PreparedCandidate.dispose] ya borra esa raíz entera. Un
/// segundo cierre sería redundante o un doble borrado, con un orden
/// determinante que nada impone.
///
/// **Se deriva UNA vez por candidato, y eso es una precondición, no un
/// detalle.** El rechazo por «el árbol versiona lo que la derivación genera»
/// mira el disco, que es lo único que la implementación puede mirar: no conoce
/// git y no debe conocerlo. Después de una derivación exitosa ese disco ya tiene
/// lo generado, así que una segunda llamada sobre el mismo candidato lo
/// rechazaría — y tendría razón según lo que puede ver. Quien recomponga una
/// corrida prepara un candidato nuevo; es lo que hace [PreparedCandidate] con su
/// raíz temporal.
abstract interface class VerificationEnvironment {
  Future<ResultadoDeEntorno> derivar(
    String candidateRoot, {
    required List<String> archivos,
    required Duration presupuesto,
  });
}

/// Por donde sale un Pull Request a la forja.
///
/// **Separado de [ChangeSink] a propósito.** Uno es local y funciona sin red;
/// el otro es remoto, necesita credencial y depende de un proveedor. Fallan
/// por razones distintas, se prueban distinto, y ADR-014 exige que se pueda
/// terminar con el primero hecho y el segundo no.
///
/// **Quién es la forja no se sabe acá.** GitHub, GitLab o lo que sea vive en
/// su propio adapter, igual que el stack vive en su plugin. El
/// repositorio/remoto pertenece a la configuración inyectada de ese adapter,
/// no a la solicitud.
///
/// **Devuelve el desenlace; no lanza por un fallo remoto.** Con un `String` y
/// una excepción no había forma de representar «el push salió y el PR no», ni
/// de distinguir una respuesta perdida de un rechazo — y confundirlas hace que
/// el reintento cree un segundo PR.
abstract interface class PullRequestSink {
  /// Abre el PR y devuelve dónde quedó. **Idempotente**: repetirla con la
  /// misma solicitud no crea un segundo pull request.
  Future<PublicationOutcome> open(PullRequestRequest request);
}

/// El árbol de trabajo: leer, escribir, y saber si está sucio.
abstract interface class Workspace {
  Future<String> read(String path);
  Future<void> write(String path, String contents);
  Future<bool> isDirty();
  Future<String> revision();
}

/// Por donde salen las trazas.
abstract interface class TraceSink {
  Future<void> emit(Trace trace);
}

/// **Entrega** credenciales. Devuelve [Credential], nunca cadenas: el tipo es
/// lo que impide que el secreto termine en una traza (INV-5).
///
/// **Partido de [CredentialStore] a propósito.** Quien solo lee no puede ser
/// sustituible por el puerto entero sin lanzar en `write` y `delete`, y un
/// método cuya única implementación es lanzar es una capacidad declarada que no
/// existe — el diagnóstico que este repositorio ya se hace con los puertos sin
/// implementación. Partido, `ship` depende de lo que necesita y el
/// almacenamiento sigue sin existir hasta que alguien lo escriba.
abstract interface class CredentialSource {
  Future<Credential?> read(String key);
}

/// Guarda y entrega. **Sigue sin implementación**: llega con `init`, que es la
/// primera etapa que necesita escribir una credencial.
abstract interface class CredentialStore implements CredentialSource {
  Future<void> write(String key, Credential value);
  Future<void> delete(String key);
}

// --- Sensores inferenciales · anotan, nunca bloquean -------------------

/// Mira un diff y anota. Devuelve [Finding], que **no tiene severidad**: por
/// eso no puede detener nada (ADR-006).
abstract interface class ReviewSensor {
  Future<List<Finding>> review(List<String> changedFiles);

  /// Qué miró y qué NO miró, con el motivo. Es el hueco `RS-1` del sensor real
  /// analizado: sin esto, un reporte sin la sección de seguridad se lee como
  /// «seguridad ok».
  Future<Witness> attestation();
}

/// Audita las trazas en busca de patrones que ningún check determinista ve.
abstract interface class TraceAuditor {
  Future<List<Finding>> audit(Trace trace);
}

// --- Aportados por el plugin, además de los de stack -------------------

/// Prosa y skills del ecosistema: el cuadrante **guía inferencial** (`D-010`).
abstract interface class RuleContributor {
  List<Rule> contribute();
}

/// Qué mirar en un diff de este lenguaje: el cuadrante **sensor inferencial**
/// (`D-011`).
abstract interface class ReviewCriteria {
  /// Cada criterio con su id estable, para telemetría y promoción.
  Map<String, QuotedText> criteria();

  /// Lo que ya imponen los lints y el sensor **no** debe comentar (`RS-5`).
  List<String> coveredByLints();
}

/// Vías alternativas conocidas por control (`D-012`).
///
/// Es un puerto y no documentación por una razón operativa: sin evasiones el
/// gancho no se instala, así que esto tiene que ser consultable en tiempo de
/// instalación, no leíble por una persona.
abstract interface class EvasionCatalog {
  List<String> evasionsFor(String controlId);
}

/// El catálogo de formas a las que se puede traducir un criterio de aceptación
/// (ADR-016, `D-013`). Es lo que INV-1 exige que exista antes de admitir un
/// [WorkItem].
abstract interface class AssertionForms {
  List<String> forms();
  bool supports(String formId);
}
