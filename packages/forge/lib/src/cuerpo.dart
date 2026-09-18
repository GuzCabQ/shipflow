/// El render del cuerpo y el título del pull request de GitHub.
///
/// **Por qué vive acá y no en un renderizador neutral.** Un componente
/// neutral decide la **estructura**; el adapter aplica la **sintaxis**. La
/// alerta `> [!WARNING]` y el comentario HTML del marcador son sintaxis de
/// GitHub — Markdown de otro proveedor no las entiende igual, algunos ni las
/// entienden — así que un componente que se dijera neutral y las produjera
/// tendría neutralidad falsa. Esta función vive en `forge`, el adapter, y en
/// ningún paquete que otro adapter pudiera importar.
///
/// **Por qué el orden de las secciones no es una elección de estilo.** ADR-016
/// nombra «cubierto» como el peor lugar para una traducción mala: habilita a
/// un revisor a **saltar**. De ahí salen las tres cosas que este archivo
/// ordena, y ninguna es de estilo:
///
/// 1. La advertencia va antes de cualquier sección que se lea como verde.
/// 2. **Lo que requiere criterio humano va antes que lo cubierto.** Lo dice
///    verbatim §13 de la propuesta aceptada —«El cuerpo, el JSON y el
///    directorio»—: «requiere criterio, completo y antes que lo cubierto». Y
///    lo dice por el otro lado la decisión 7 de ADR-022: la lista de lo que
///    requiere criterio «no se entierra, no se resume y no va después de una
///    conclusión tranquilizadora». Un revisor que lee primero la lista de lo
///    cubierto ya decidió saltar cuando llega a lo que tendría que mirar él.
///
///    **Ninguno de los dos documentos vive en este árbol**, y por eso van con
///    su ruta: los dos están en el repositorio del corpus, en
///    `sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md` y
///    `sdlc-agentico/adr/ADR-022-forja-y-credencial.md`. Una cita que quien
///    lee no puede abrir es la misma clase de defecto que este orden vino a
///    cerrar: la versión anterior de esta línea atribuía el orden CONTRARIO
///    a ADR-016, y nadie podía contrastarlo sin salir del repositorio.
/// 3. Ninguna sección resume o entierra lo que requiere criterio — cada
///    entrada sale completa, con su motivo y su detalle, nunca como un
///    conteo.
library;

import 'package:core/core.dart';

import 'github.dart' show marcadorEstable;

/// El límite de GitHub para el título de un pull request. Es conocimiento de
/// **este** proveedor — `core` no lo sabe, y no debería: `titulo` en
/// `PullRequestRequest` es texto sin límite de proveedor alguno.
const _longitudMaximaDelTitulo = 256;

/// El título, truncado al límite de GitHub **conservando el prefijo**.
///
/// Si hay que cortar, se corta la intención, nunca la advertencia: un título
/// que perdiera `PullRequestRequest.prefijoIncompleto` por el corte le diría
/// a un revisor que la corrida salió verde cuando no fue así.
///
/// **Y el corte cae entre caracteres, no adentro de uno.** `String.length` y
/// `substring` cuentan unidades UTF-16, y todo lo que está fuera del plano
/// básico —un emoji, por ejemplo— ocupa DOS: cortar en el límite de 256
/// unidades puede dejar media pareja suelta, que al codificarse a UTF-8 se
/// convierte en `�` y le entrega a la forja un título terminado en un
/// carácter que nadie escribió. No bloquea —la intención completa va en el
/// cuerpo—, pero es el render mostrando algo que no es el dato.
String tituloDeGitHub(PullRequestRequest solicitud) {
  final titulo = solicitud.titulo;
  if (titulo.length <= _longitudMaximaDelTitulo) return titulo;

  final prefijo = solicitud.incompleto
      ? PullRequestRequest.prefijoIncompleto
      : '';
  final intencion = titulo.substring(prefijo.length);
  final maximoParaLaIntencion = _longitudMaximaDelTitulo - prefijo.length;
  return '$prefijo${_truncarPorRunes(intencion, maximoParaLaIntencion)}';
}

/// Corta [texto] para que no pase de [maximoEnUnidades] unidades UTF-16 **sin
/// partir ningún carácter**.
///
/// El límite sigue midiéndose en unidades UTF-16 porque es el que declara la
/// forja para el título, y `String.length` es lo que cuenta lo mismo que
/// cuenta ella; lo que cambia es dónde puede caer el corte: solo entre runas.
///
/// **Se trunca por RUNAS y no por grafemas, y eso tiene un precio declarado:**
/// un emoji compuesto —una familia unida por `ZWJ`, una bandera, un tono de
/// piel— es una sola cosa para quien lo lee y varias runas para el lenguaje,
/// así que el corte puede dejar la primera mitad de esa secuencia y mostrar
/// dos emojis donde había uno. Nunca deja media pareja suelta, que es el
/// defecto que este corte cierra: lo que se ve sigue siendo un carácter que
/// estaba en el dato. Cortar por grafemas pediría una dependencia externa
/// —`characters`—, y `forge` hoy no tiene ninguna fuera del SDK.
String _truncarPorRunes(String texto, int maximoEnUnidades) {
  if (texto.length <= maximoEnUnidades) return texto;
  final recortado = StringBuffer();
  var usadas = 0;
  for (final runa in texto.runes) {
    // Una runa fuera del plano básico ocupa dos unidades UTF-16; el `if` de
    // abajo es lo que impide que entre solo la primera.
    final ancho = runa > 0xFFFF ? 2 : 1;
    if (usadas + ancho > maximoEnUnidades) break;
    recortado.writeCharCode(runa);
    usadas += ancho;
  }
  return recortado.toString();
}

// ---------------------------------------------------------------------------
// EL RENDER SEGURO: un dato que este archivo no escribió no puede enterrar lo
// obligatorio, ni falsificar una sección, ni descuadrar el ítem donde vive, ni
// meter un enlace o una imagen en el cuerpo.
//
// **Eso es lo que promete, y se enuncia por extensión a propósito.** La
// versión anterior de esta cabecera decía que el dato «no puede cambiar la
// estructura», y prometía de más: neutralizaba lo que ENTIERRA —el comentario
// HTML, la cerca de código— y lo que abre bloque al principio de un renglón,
// pero dejaba pasar el énfasis y los enlaces a mitad de línea. Con
// `sujeto: 'a**b'` la negrita del ítem quedaba descuadrada, y con
// `detalle: '![](http://atacante/x.png)'` el cuerpo llevaba una imagen remota
// —o sea una baliza que dispara cuando el revisor abre la página—. Un enlace y
// una imagen SON estructura, así que esta ronda los agregó a la
// neutralización en vez de acotar la promesa.
//
// **Lo que sigue afuera, declarado:** el Markdown de la forja convierte en
// enlace una URL escrita al desnudo —`http://…` en medio del texto— y eso no
// se puede neutralizar escapando puntuación. Un enlace que el revisor tiene
// que CLICKEAR no entierra nada, no falsifica ninguna sección y no dispara
// solo; la diferencia con la imagen es justamente esa, y es la que hace que
// una entre y la otra no.
//
// **El defecto que esto cierra, reproducido por el autor:** con
// `intent: '<!--'`, la intención abría un comentario HTML y la advertencia
// obligatoria más las dos secciones obligatorias quedaban ADENTRO del
// comentario — el comentario recién cerraba en el marcador final. O sea que un
// dato de la corrida enterraba exactamente lo que la norma dice que no se
// puede enterrar, y el cuerpo se leía como si no hubiera nada que mirar.
//
// **Por qué un render por CONTEXTO y no reemplazos sueltos.** La
// neutralización es una sola —los caracteres de sintaxis pasan a entidades—,
// pero el envoltorio cambia según dónde caiga el dato: un párrafo suelto
// conserva sus renglones; un ítem de lista no puede tenerlos, porque un
// renglón nuevo termina el ítem y lo que siga queda al mismo nivel que las
// secciones de este archivo; y un identificador se muestra como código. Con
// reemplazos dispersos, cada sitio de llamada vuelve a decidir, y el que se
// olvide no lo nota nadie: por eso son TRES funciones —[_textoDeBloque],
// [_textoEnLista], [_identificadorEnCodigo]— y ninguna interpolación cruda de
// datos ajenos en `cuerpoDeGitHub`.
//
// **Qué NO existe: un canal de Markdown confiable.** El `plan` también se
// escapa. Se podría argumentar que un plan quiere sus viñetas y sus títulos,
// pero hoy ningún tipo declara «este texto es Markdown que su autor escribió a
// propósito»: sería una propiedad de un campo `String` sostenida por prosa, o
// sea la clase de promesa que este repositorio persigue. El día que haga
// falta, el que tiene que declararlo es el tipo —un `MarkdownConfiable` que se
// construya donde alguien pueda responder por su contenido—, no una excepción
// en este render. Precio declarado: un plan escrito en Markdown se lee como
// texto plano en el pull request.
// ---------------------------------------------------------------------------

/// Los caracteres que dejan de ser sintaxis al escribirse como entidad.
///
/// - `&` va primero por construcción —se reemplaza en una sola pasada—, para
///   que un `&` del dato no se coma la entidad de los otros.
/// - `<` es el que abre `<!--` y cualquier etiqueta HTML: es el del defecto
///   reproducido.
/// - `>` al principio de un renglón abre una cita, y `> [!WARNING]` es
///   justamente la forma de la advertencia obligatoria: un dato podría
///   falsificarla.
/// - El acento grave abre código, y tres abren un bloque que se traga todo
///   hasta el siguiente — otra forma de enterrar lo de abajo.
/// - La tilde hace lo mismo que el acento grave con `~~~`, que es la segunda
///   forma de cerca que Markdown reconoce.
/// - El asterisco y el guion bajo abren énfasis: un dato con `**` adentro
///   descuadra la negrita del ítem que lo contiene, y entonces el cuerpo
///   muestra en negrita algo que no es lo que este archivo marcó.
/// - Los corchetes abren un enlace y —con un `!` delante— una imagen. Una
///   imagen remota en el cuerpo es una baliza: se pide sola cuando el revisor
///   abre la página. Neutralizado el corchete, los paréntesis que vienen
///   detrás son texto y no hace falta tocarlos.
///
/// GitHub decodifica estas entidades al renderizar, así que el revisor lee el
/// carácter tal como venía en el dato; lo que no puede es actuar como
/// sintaxis.
const _entidades = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '`': '&#96;',
  '~': '&#126;',
  '*': '&#42;',
  '_': '&#95;',
  '[': '&#91;',
  ']': '&#93;',
};

final _neutralizables = RegExp(r'[&<>`~*_\[\]]');

String _comoEntidades(String texto) =>
    texto.replaceAllMapped(_neutralizables, (m) => _entidades[m[0]!]!);

/// Lo que ABRE un bloque cuando está al principio de un renglón **y todavía
/// no es una entidad**: un título, una viñeta, una línea de tabla, un
/// subrayado de título, una lista numerada. Hasta tres espacios de sangría
/// siguen contando como principio de renglón en Markdown, así que la sangría
/// entra en el patrón.
///
/// El asterisco y el guion bajo NO están acá aunque también abran bloque:
/// para cuando este patrón corre ya son entidades. Dejarlos en la clase sería
/// una rama muerta que dice cubrir algo que nunca le llega.
///
/// Ninguno de estos ENTIERRA nada —no abren una región que se trague lo que
/// sigue, como sí hacen el comentario y la cerca—, pero sí FALSIFICAN
/// estructura: un dato que empiece con `## Qué quedó cubierto` agrega una
/// sección que nadie escribió, y un revisor no tiene desde dónde notar que esa
/// sección la puso el dato y no el render.
final _aperturaDeBloque = RegExp(r'^( {0,3})(\d{1,9}([.)])|[#\-+=|])');

String _renglonDeBloque(String renglon) {
  final texto = _comoEntidades(renglon);
  final apertura = _aperturaDeBloque.firstMatch(texto);
  if (apertura == null) return texto;
  final sangria = apertura[1]!;
  final marca = apertura[2]!;
  final cierreDelNumero = apertura[3];
  // La barra invertida escapa signos de puntuación ASCII y NO dígitos: en una
  // lista numerada lo que hay que escapar es el punto o el paréntesis, no el
  // número. Escapar el dígito dejaría una barra invertida visible en el
  // cuerpo, que es ensuciar el dato en vez de neutralizarlo.
  final neutra = cierreDelNumero == null
      ? '\\$marca'
      : '${marca.substring(0, marca.length - 1)}\\$cierreDelNumero';
  return '$sangria$neutra${texto.substring(apertura.end)}';
}

final _finDeRenglon = RegExp(r'\r\n|\r|\n');

/// Texto que ocupa su propio bloque: la intención, el alcance, el plan.
/// **Conserva los renglones** —son del dato y el revisor los espera— y
/// neutraliza el principio de cada uno.
String _textoDeBloque(String texto) =>
    texto.split(_finDeRenglon).map(_renglonDeBloque).join('\n');

/// Texto que va DENTRO de un ítem de lista.
///
/// Además de las entidades, los renglones se juntan en uno solo: un renglón
/// nuevo adentro de un ítem lo termina y lo que siga pasa a ser un bloque
/// nuevo —con lo que el dato quedaría al mismo nivel que las secciones que
/// escribe este archivo—. **Residuo declarado:** un `detalle` de varios
/// renglones se lee en uno solo, separado por espacios.
String _textoEnLista(String texto) =>
    _comoEntidades(texto).split(_finDeRenglon).join(' ');

/// El texto de «Qué hacer». **Es fijo y no pasa por el render seguro**: no
/// depende de ningún dato de la corrida —a diferencia de todo lo demás que
/// interpola este archivo—, así que no hay nada ajeno que pudiera actuar
/// como sintaxis.
///
/// **Por qué esto y no la acción del desenlace de la publicación.** `forge`
/// arma este cuerpo ANTES de que exista un desenlace que dar: la operación
/// que lo llama es la misma que todavía no terminó de abrir el pull request,
/// y `accionDe(ShipOutcome)` —en `cli`, la raíz de composición— recién puede
/// evaluarse con lo que esa apertura devuelva. Pedirle el parámetro a `cli`
/// además cruzaría la flecha al revés: `forge` no puede ver a `cli`. Lo que
/// SÍ existe en este momento es [PullRequestRequest.incompleto], que ya lo
/// tiene la solicitud — de ahí se deriva esta sección, sin agregar un
/// parámetro nuevo.
const _queHacerSiIncompleto =
    'La verificación de este cambio no salió verde. Antes de fusionar, '
    'alguien con criterio tiene que revisar «Qué requiere criterio humano», '
    'arriba, y decidir si el cambio se acepta publicado así.';

/// La línea visible con la revisión, el `runId` y `payloadVersionDeShip`.
///
/// **Es la corrección directa del hallazgo que motiva este archivo.** La
/// revisión y el `runId` ya viajaban en [marcadorEstable], pero ADENTRO de un
/// comentario HTML: la forja no lo muestra, así que para el revisor humano no
/// estaban — el JSON de la corrida es local y `git` lo ignora, y el marcador
/// era la única otra copia. Esta línea repite los mismos dos valores, ya
/// visibles, y agrega `payloadVersionDeShip`, que hasta ahora no aparecía en
/// ningún lado del cuerpo.
///
/// Pasa por [_identificadorEnCodigo] como cualquier otro identificador de
/// este archivo. `runId` y `revision` tienen su propia forma restringida
/// —[PullRequestDraft] rechaza `<!--`, `-->` y saltos de línea en el primero;
/// [PullRequestRequest] exige que el segundo sea un OID completo—, pero esta
/// función no se apoya en esa restricción para estar segura: la promesa del
/// render seguro es la misma para todo dato que este archivo no haya escrito
/// él mismo.
String _lineaDeIdentidad(PullRequestRequest solicitud) =>
    'Corrida ${_identificadorEnCodigo(solicitud.draft.runId)} · '
    'revisión ${_identificadorEnCodigo(solicitud.revision)} · '
    'payload v$payloadVersionDeShip';

/// Los testigos que sostienen lo cubierto, en un bloque PLEGABLE: es
/// evidencia de apoyo, no algo que un revisor tenga que leer para decidir —
/// eso ya lo dijeron, completas y sin plegar, las dos secciones obligatorias
/// de arriba. Por eso este bloque va DESPUÉS de las dos, nunca antes ni entre
/// ellas, y por eso es el único de este archivo que el adapter puede plegar:
/// `<details>` es sintaxis de GitHub, igual que `> [!WARNING]`.
///
/// **Sin nada cubierto no hay testigos que mostrar, y no se inventa un bloque
/// vacío** — el mismo principio que ya aplican [_escribirLoQueQuedoCubierto]
/// y [_escribirLoQueRequiereCriterio] con su texto de lista vacía, llevado un
/// paso más allá: acá ni siquiera hay una sección fija que rellenar.
///
/// **Deduplicado por identidad, no por contenido.** Un solo paso puede cubrir
/// varios sujetos con el MISMO testigo —una invocación certifica una lista de
/// archivos—, y `AfirmacionCubierta.desde` (en `core`, `superficie`) reusa ese
/// mismo objeto para cada sujeto que cubre. `Witness` no define `==`, así que
/// el `Set` de abajo compara por identidad y agrupa exactamente esas
/// repeticiones, sin fundir dos testigos distintos que dijeran lo mismo por
/// coincidencia.
///
/// **Nada se trunca.** Un testigo con muchos sujetos —o muchas omisiones— sale
/// completo: cortarlo y dejar un «…» sería, otra vez, la forma exacta del
/// defecto que este archivo existe para no cometer — decirle al revisor que
/// puede no mirar algo que nadie certificó.
void _escribirTestigos(StringBuffer buffer, List<AfirmacionCubierta> cubierto) {
  final testigos = <Witness>{for (final c in cubierto) c.testigo};
  if (testigos.isEmpty) return;

  buffer.writeln('<details>');
  buffer.writeln('<summary>Testigos (${testigos.length})</summary>');
  buffer.writeln();
  for (final testigo in testigos) {
    final sujetos = testigo.subjects.map(_identificadorEnCodigo).join(', ');
    buffer.writeln(
      '- ${_identificadorEnCodigo(testigo.invocation)}'
      '${sujetos.isEmpty ? '' : ' — sujetos: $sujetos'} — salida '
      '${testigo.exitCode} — terminó '
      '${testigo.finishedAt.toUtc().toIso8601String()}',
    );
    for (final omision in testigo.omitted) {
      final sujeto = omision.subject == null
          ? 'residuo general'
          : 'sujeto ${_identificadorEnCodigo(omision.subject!)}';
      buffer.writeln('  - omitido — $sujeto: ${_textoEnLista(omision.reason)}');
    }
  }
  buffer.writeln('</details>');
}

/// Un identificador que se muestra como código: el sujeto, el id del control,
/// el id de la afirmación.
///
/// **Va entre `<code>` y no entre acentos graves, y la diferencia no es de
/// gusto.** Adentro de un tramo de código de Markdown las entidades NO se
/// decodifican, así que ahí un `&lt;` se leería literal: para neutralizar un
/// identificador hostil habría que jugar con el largo de la cerca, y eso
/// alcanza solo contra los acentos. Contra `<!--` no alcanza, porque en
/// CommonMark el HTML crudo tiene precedencia sobre el tramo de código —un
/// `<!--` en un identificador y un `-->` en otro, en el mismo ítem, forman un
/// comentario que se traga el detalle que hay entre los dos, que es
/// exactamente lo que la norma prohíbe enterrar—.
///
/// Con `<code>`, en cambio, el contenido es HTML: las mismas entidades que
/// [_textoEnLista] neutraliza se decodifican al renderizar, así que el
/// revisor lee el identificador tal como vino y ningún carácter suyo puede
/// actuar como sintaxis. Es una sola regla para todo el archivo —neutralizar
/// con entidades— en vez de dos mecanismos que hay que recordar cuál protege
/// de qué.
///
/// Los renglones se juntan por lo mismo que en [_textoEnLista].
String _identificadorEnCodigo(String texto) =>
    '<code>${_textoEnLista(texto)}</code>';

/// Cómo se lee, en el cuerpo del PR, cada motivo por el que algo requiere
/// criterio humano. **Traduce el nombre del enum, no lo resume, y no le
/// agrega alcance que el motivo no tiene.**
///
/// La ronda de arreglo 1 encontró exactamente ese segundo error en
/// [MotivoDeCriterio.nadieDioCuenta]: decía «nadie dio cuenta de este
/// sujeto», y el doc comment de ese valor, en `core`, dice que dos de sus
/// tres hechos **no tienen sujeto en absoluto** — el
/// entorno derivado sin ningún control que corriera, o la cascada corrida sin
/// ningún control registrado. Agregarle «de este sujeto» encogía un fallo de
/// la corrida entera a uno acotado a un sujeto puntual: exactamente la
/// traducción tranquilizadora que este archivo existe para no escribir. La
/// entrada que sí tiene sujeto ya lo muestra por separado, en el sufijo
/// `— sujeto \`...\`` que arma [_escribirLoQueRequiereCriterio]; esta prosa no
/// necesita nombrarlo de nuevo, y nombrarlo aquí sería afirmar que siempre
/// hay uno.
///
/// **Las diez ramas, comparadas una por una contra su doc comment en esta
/// ronda de arreglo** (el de cada valor de [MotivoDeCriterio], en `core`):
/// - `hallazgo`: el doc dice que se emite sobre todos los sujetos del paso, o
///   sobre ninguno. «El control encontró algo» no afirma ni una cosa ni la
///   otra, así que no contradice ningún caso — sin cambios.
/// - `declaradoNoMirado`: el doc mismo dice «ese sujeto» — a diferencia de
///   `nadieDioCuenta`, acá el sujeto es parte de la definición, no un agregado
///   de esta traducción — sin cambios.
/// - `nadieDioCuenta`: **el único con un error real.** Decía «nadie dio
///   cuenta de este sujeto»; el doc nombra tres hechos y dos de los tres no
///   tienen sujeto — corregido a «nadie dio cuenta», sin calificador.
/// - `ajenoAlStack`: el doc dice «el sujeto no es de este stack» — siempre
///   hay sujeto en la propia definición — sin cambios.
/// - `noSePudoMirar`, `instrumentoFallo`: la prosa ya calca el doc casi
///   palabra por palabra — sin cambios.
/// - `intentoIncompleto`: paráfrasis («no terminó» por «no llegó a
///   terminar»), mismo alcance que el doc — sin cambios.
/// - `residuoGeneral`: el doc dice «no ata a ningún sujeto» y la prosa lo
///   conserva tal cual — sin cambios.
/// - `entornoNoDerivado`: el doc habla de la cascada entera, nunca de «este
///   sujeto» — «el entorno no se derivó» no le agrega alcance — sin cambios.
/// - `candidatoAlterado`: el doc dice que **ningún** sujeto se puede dar por
///   cubierto — «el candidato se alteró» tampoco nombra un sujeto puntual —
///   sin cambios.
String _nombreDeMotivo(MotivoDeCriterio motivo) => switch (motivo) {
  MotivoDeCriterio.hallazgo => 'el control encontró algo',
  MotivoDeCriterio.declaradoNoMirado => 'el control declaró que no lo miró',
  MotivoDeCriterio.nadieDioCuenta => 'nadie dio cuenta',
  MotivoDeCriterio.ajenoAlStack => 'el sujeto no es de este stack',
  MotivoDeCriterio.noSePudoMirar => 'no se pudo establecer qué era',
  MotivoDeCriterio.intentoIncompleto => 'el control empezó y no terminó',
  MotivoDeCriterio.instrumentoFallo => 'el arnés se rompió',
  MotivoDeCriterio.residuoGeneral => 'residuo que no ata a ningún sujeto',
  MotivoDeCriterio.entornoNoDerivado => 'el entorno no se derivó',
  MotivoDeCriterio.candidatoAlterado => 'el candidato se alteró',
};

/// Las entradas sin sujeto primero: son las que hablan de la corrida entera
/// —el entorno que no se derivó, la cascada que no dejó control registrado—
/// y no de un sujeto puntual, así que preceden a las que sí lo nombran.
/// **Estable**: no reordena las entradas dentro de cada uno de los dos
/// grupos, para no sugerir una prioridad entre ellas que nadie afirmó.
List<EntradaDeCriterio> _sinSujetoPrimero(List<EntradaDeCriterio> entradas) => [
  ...entradas.where((e) => e.sujeto == null),
  ...entradas.where((e) => e.sujeto != null),
];

void _escribirLoQueQuedoCubierto(
  StringBuffer buffer,
  List<AfirmacionCubierta> cubierto,
) {
  buffer.writeln('## Qué quedó cubierto');
  buffer.writeln();
  if (cubierto.isEmpty) {
    buffer.writeln('Ningún sujeto quedó cubierto en esta corrida.');
  } else {
    for (final c in cubierto) {
      // `afirmacion.id` no es `controlId`: un control puede declarar más de
      // una afirmación el día que tenga evidencia por sujeto, así que las
      // dos identidades se muestran, no solo la del control.
      buffer.writeln(
        '- **${_textoEnLista(c.sujeto)}** '
        '(control ${_identificadorEnCodigo(c.controlId)}, afirmación '
        '${_identificadorEnCodigo(c.afirmacion.id)}): '
        '${_textoEnLista(c.afirmacion.demuestra)}. No demuestra: '
        '${_textoEnLista(c.afirmacion.noDemuestra)}.',
      );
    }
  }
  buffer.writeln();
}

void _escribirLoQueRequiereCriterio(
  StringBuffer buffer,
  List<EntradaDeCriterio> requiereCriterio,
) {
  buffer.writeln('## Qué requiere criterio humano');
  buffer.writeln();
  if (requiereCriterio.isEmpty) {
    buffer.writeln('Nada quedó pendiente de criterio humano en esta corrida.');
  } else {
    for (final e in _sinSujetoPrimero(requiereCriterio)) {
      final sujeto = e.sujeto == null
          ? ''
          : ' — sujeto ${_identificadorEnCodigo(e.sujeto!)}';
      final control = e.controlId == null
          ? ''
          : ' — control ${_identificadorEnCodigo(e.controlId!)}';
      buffer.writeln(
        '- **${_nombreDeMotivo(e.motivo)}**$sujeto$control: '
        '${_textoEnLista(e.detalle)}',
      );
    }
  }
  buffer.writeln();
}

/// El cuerpo completo del PR. **Arma las secciones en el orden que imponen
/// §13 de la propuesta aceptada y la decisión 7 de ADR-022** —lo que requiere
/// criterio, completo y ANTES que lo cubierto; las dos citas, con su ruta en
/// el repositorio del corpus, están en el doc comment de esta biblioteca— y
/// cierra con [marcadorEstable], que sigue viviendo en el módulo
/// vecino que habla con la API porque la clave de la búsqueda idempotente
/// pertenece a quien busca.
///
/// **Después del plan, y antes del marcador, van los cuatro elementos que
/// §13 exige y que este archivo no llevaba**: la acción siguiente cuando la
/// corrida se publica incompleta ([_queHacerSiIncompleto], derivada de
/// [PullRequestRequest.incompleto]), los testigos agrupados en un bloque
/// plegable ([_escribirTestigos]) y, visibles y no solo dentro del
/// comentario HTML del marcador, la revisión, el `runId` y
/// `payloadVersionDeShip` ([_lineaDeIdentidad]).
///
/// **Lo que no aparece acá, a propósito**: ninguna ruta del workspace local,
/// ningún campo que el revisor remoto no pueda ver por su cuenta. Todo lo que
/// esta función lee sale de [ArtefactoDeRevision] y de sus tipos —ninguno
/// lleva una ruta de disco—, así que no hay nada que filtrar por accidente
/// mientras esa condición se sostenga.
String cuerpoDeGitHub(PullRequestRequest solicitud) {
  final artefacto = solicitud.draft.artefacto;
  final superficie = artefacto.superficie;
  final buffer = StringBuffer();

  buffer.writeln(_textoDeBloque(artefacto.alcanceDeLoAfirmado));
  buffer.writeln();

  // El título trunca la intención al límite de GitHub (ver
  // `tituloDeGitHub`); acá va completa siempre. Sin esto, un título largo
  // dejaba la intención sin ningún lugar donde el revisor remoto pudiera
  // leerla entera — el JSON de la corrida es local y `git` lo ignora, así
  // que el cuerpo del PR es la única superficie que le queda.
  buffer.writeln('## Intención');
  buffer.writeln();
  buffer.writeln(_textoDeBloque(artefacto.intent));
  buffer.writeln();

  if (solicitud.incompleto) {
    // Antes de cualquier cosa que se lea como verde: es la advertencia
    // obligatoria de ADR-016, y por eso no espera a las secciones de abajo.
    buffer.writeln('> [!WARNING]');
    buffer.writeln(
      '> La superficie de verificación no salió verde '
      '(`${superficie.estado.name}`). Lo que sigue certifica solo lo que '
      'cada afirmación cubierta dice, sujeto por sujeto — no el cambio '
      'entero.',
    );
    buffer.writeln();
  }

  // **Lo que requiere criterio va PRIMERO, y eso es la norma y no un
  // gusto.** §13 de la propuesta aceptada
  // (`sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md`, en el
  // repositorio del corpus) lo dice verbatim: «requiere criterio, completo y
  // antes que lo cubierto». Este archivo tenía las dos llamadas al revés, y
  // una prueba que exigía el orden equivocado atribuyéndoselo a ADR-016.
  _escribirLoQueRequiereCriterio(buffer, superficie.requiereCriterio);
  _escribirLoQueQuedoCubierto(buffer, superficie.cubierto);

  if (artefacto.plan != null) {
    buffer.writeln('## Plan');
    buffer.writeln();
    buffer.writeln(_textoDeBloque(artefacto.plan!));
  } else {
    // Presente si y solo si no hay plan: sin esto, un artefacto sin plan
    // afirmaría por omisión que no hacía falta ninguno.
    buffer.writeln('## Por qué no hay plan');
    buffer.writeln();
    buffer.writeln(_textoDeBloque(artefacto.sinPlanPorque!));
  }
  buffer.writeln();

  // Presente si y solo si la corrida se publica incompleta: sobre una
  // superficie verde no hay nada que decidir, y una sección vacía afirmaría
  // que sí lo hay.
  if (solicitud.incompleto) {
    buffer.writeln('## Qué hacer');
    buffer.writeln();
    buffer.writeln(_queHacerSiIncompleto);
    buffer.writeln();
  }

  _escribirTestigos(buffer, superficie.cubierto);
  buffer.writeln();

  buffer.writeln('---');
  buffer.writeln();
  buffer.writeln(_lineaDeIdentidad(solicitud));
  buffer.writeln();

  buffer.writeln(marcadorEstable(solicitud));

  return buffer.toString();
}
