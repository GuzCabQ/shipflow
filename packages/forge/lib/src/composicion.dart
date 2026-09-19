/// Cómo se arma la salida de pull requests **sin nombrar a la forja desde
/// afuera**.
///
/// La regla `forja-en-su-adapter` dice que quién es la forja lo sabe este
/// paquete y ningún otro: ni su nombre de marca, ni su host. Su residuo
/// declarado anticipaba el choque —`SalidaDePrDeGitHub` y
/// `ConfiguracionDeGitHub` llevan la marca ADENTRO del nombre, así que la raíz
/// de composición no podía armarlos sin escribirla— y anticipaba dos salidas:
/// renombrar esos símbolos, o darle a la regla una excepción acotada a la raíz
/// de composición.
///
/// **Este archivo es una tercera, y es la que se eligió.** Lo que faltaba no
/// era una excepción: era el constructor. Una función de nombre neutro, acá
/// adentro, que recibe una URL de `git` y devuelve el puerto. Así la marca no
/// cruza el límite ni una vez, la regla queda intacta y sin residuo nuevo, y
/// el día que haya un segundo proveedor la selección ya vive donde tiene que
/// vivir: en el único paquete que puede saber quién atiende qué.
///
/// Una excepción, en cambio, habría abierto la raíz de composición a la marca
/// para siempre a cambio de ahorrar una función.
library;

import 'dart:io';

import 'package:core/core.dart';

import 'empuje.dart';
import 'github.dart';

/// La base de la API cuando quien compone no dice otra cosa.
///
/// **Vive acá y no en la raíz de composición**, que es el punto entero de este
/// archivo: es el host del proveedor, y ese dato no sale de este paquete.
final _baseDeLaApiPorOmision = Uri.parse('https://api.github.com');

/// El host cuyos remotos este adapter sabe atender.
///
/// **Se compara entero y en minúsculas, no por sufijo.** `no-github.com`
/// TERMINA con el texto de este host y no es él; un control que preguntara
/// `endsWith` atendería el remoto de cualquiera que registre un dominio que
/// termine así, con la credencial adjunta.
const _hostAtendido = 'github.com';

/// La salida de pull requests que atiende [urlDelRemoto], o **nulo cuando
/// ninguna de las que este paquete conoce lo atiende**.
///
/// **Nulo y no una excepción, a propósito.** «Este remoto no es mío» es un
/// hecho sobre la configuración de quien corre, no un error de programación:
/// quien compone tiene que poder ramificar sobre él —y decir por qué no se va
/// a publicar— sin atrapar nada. Es el mismo precedente que `EstadoPublicable.desde`.
///
/// **La credencial de la URL no sobrevive a esta función.** Un remoto puede
/// traerla embebida en la autoridad, y lo que se construye acá guarda esa URL
/// para empujar: si viajara entera, cualquier mensaje o volcado que la nombre
/// publicaría el secreto de quien la configuró. El secreto se va SIEMPRE,
/// cualquiera sea la forma: la credencial con la que se empuja es la que sale
/// de [credenciales], nunca la que ya estuviera escrita en la configuración
/// del remoto. En una URL con esquema se va la parte de usuario entera,
/// porque ahí ese lugar ES la credencial y no identifica ningún destino.
///
/// **Lo que se deja inyectable es exactamente lo que el adapter ya dejaba**
/// —la fábrica de cliente, el presupuesto de red, el presupuesto del empuje y
/// el programa con el que se empuja—. Envolver algo con sus aberturas tapadas
/// deja al envoltorio imposible de probar sin red, que es el costo que esas
/// aberturas existen para evitar.
///
/// **«Saber atender» quiere decir el camino ENTERO, no el parseo.** De
/// `git@host:duenio/repo` salen el dueño y el repositorio perfectamente, y de
/// un remoto sin cifrar también: la búsqueda idempotente y la creación del
/// pull request funcionarían con los dos. Lo que no funciona es la
/// publicación, que se niega a adjuntar la credencial donde nada la protege.
/// Devolver una salida para esas formas haría correr la preparación entera
/// —commit y documento incluidos— para fallar recién al publicar, que es
/// exactamente lo que el preflight existe para evitar: si algo falla, no se
/// preparó nada.
///
/// Por eso quien decide acá es [esCanalSeguroParaLaCredencial], **la misma
/// función que decide la publicación**, aplicada a la misma URL que la
/// publicación va a recibir. Con un predicado propio —o con una lista de
/// esquemas escrita al lado— las dos definiciones podrían separarse sin que
/// nada se pusiera rojo, y el día que se separaran volvería el mismo defecto:
/// una corrida que prepara todo para fallar al final. Un clon local queda
/// cubierto por el mismo control y por el mismo motivo: no hay API con pull
/// requests del otro lado.
///
/// **Residuo declarado: un servidor propio del proveedor no se atiende.** El
/// host se compara contra uno solo, así que una instalación en un dominio de
/// la empresa vuelve nula aunque hable exactamente la misma API. Atenderla
/// pide una superficie donde declarar ese host, que es una decisión de
/// configuración y no de esta función.
PullRequestSink? salidaDePrDelRemoto({
  required String urlDelRemoto,
  required CredentialSource credenciales,
  required String claveDeCredencial,
  required String directorio,
  required EntornoDelProceso entornoDelPadre,
  Uri? baseDeLaApi,
  HttpClient Function()? clienteHttp,
  Duration presupuestoDeRed = SalidaDePrDeGitHub.presupuestoDeRedPorDefecto,
  Duration presupuestoDelEmpuje = EmpujeAislado.presupuestoPorDefecto,
  String programaDeGit = 'git',
}) {
  final remoto = _RemotoLeido.de(urlDelRemoto);
  if (remoto == null) return null;
  // Sobre `sinCredencial` y no sobre lo que llegó, porque `sinCredencial` es
  // el texto que va a recibir la publicación: preguntarle al predicado por
  // otra cosa sería volver a abrir la distancia que este control cierra.
  if (!esCanalSeguroParaLaCredencial(remoto.sinCredencial)) return null;
  if (remoto.host.toLowerCase() != _hostAtendido) return null;
  return SalidaDePrDeGitHub(
    configuracion: ConfiguracionDeGitHub(
      duenio: remoto.duenio,
      repositorio: remoto.repositorio,
      baseDeLaApi: baseDeLaApi ?? _baseDeLaApiPorOmision,
      urlDelRemoto: remoto.sinCredencial,
    ),
    credenciales: credenciales,
    claveDeCredencial: claveDeCredencial,
    empuje: EmpujeAislado(
      directorio: directorio,
      entornoDelPadre: entornoDelPadre,
      programa: programaDeGit,
      presupuesto: presupuestoDelEmpuje,
    ),
    clienteHttp: clienteHttp,
    presupuestoDeRed: presupuestoDeRed,
  );
}

/// **La identidad del destino** que [urlDelRemoto] nombra, o nulo cuando de
/// esa URL no sale ningún destino.
///
/// **Sale por la misma puerta que la fábrica, y por el mismo motivo.** Quién
/// es la forja lo sabe este paquete y ningún otro: si quien compone tuviera
/// que derivar la identidad del destino, tendría que saber leer la URL de un
/// remoto y comparar su host, que es exactamente el conocimiento que la regla
/// `forja-en-su-adapter` prohíbe que salga de acá. Lo que cruza el límite es
/// una cadena opaca, y quien la recibe solo puede hacer con ella una cosa:
/// compararla con otra.
///
/// **Saneada: la credencial NO viaja.** Un remoto puede traerla en su parte
/// de autoridad, y esta cadena se persiste en el documento de la corrida y se
/// imprime en el mensaje que explica por qué un reintento no actúa. De acá
/// sale el host, el dueño y el repositorio, y nada más: ni la contraseña ni
/// el nombre de usuario, que en las formas con esquema es donde la credencial
/// se escribe.
///
/// **Canónica entre protocolos, a propósito.** El mismo repositorio nombrado
/// por `https` y por la forma corta de `ssh` produce la MISMA identidad,
/// porque es el mismo destino: distinguirlos haría que cambiar el protocolo
/// del remoto —sin cambiar a dónde apunta— pareciera un cambio de
/// repositorio, y el reintento se detendría por algo que no pasó.
///
/// **El PUERTO entra, y el host se baja a minúsculas; el dueño y el
/// repositorio NO. Las tres son decisiones, no accidentes, y las tres se
/// deciden por el mismo criterio: de qué lado conviene equivocarse.**
///
/// - **El puerto entra** porque dos remotos que solo difieren en él son
///   destinos DISTINTOS, y dejarlo afuera hacía que la compuerta no se
///   detuviera ante una mudanza real. Es el caso que esta función tiene que
///   contestar aunque ninguna forja conocida atienda a ninguno de los dos —dos
///   instalaciones propias en el mismo host y distinto puerto son lo más
///   parecido a un caso normal que tiene ese escenario—. El puerto por
///   omisión del esquema no se escribe: `https://host` y `https://host:443`
///   son el mismo destino, y el analizador de URLs ya los unifica.
/// - **El host se baja a minúsculas** porque un nombre de dominio no
///   distingue caja por definición: dos escrituras del mismo host SON el
///   mismo destino, y tratarlas como distintas detendría un reintento por
///   algo que no pasó.
/// - **El dueño y el repositorio se dejan como vienen**, y eso es lo que corta
///   en la otra dirección. Este paquete no puede saber si la forja de turno
///   pliega la caja en esa parte de la ruta; si la plegara acá y la forja no
///   lo hiciera, dos repositorios REALMENTE distintos darían la misma
///   identidad y la compuerta dejaría pasar la publicación en el equivocado
///   — que es el fallo que esta función existe para impedir. Al revés, el
///   costo es que dos escrituras del mismo destino detienen un reintento que
///   podría haber seguido: **falla cerrado**, con un mensaje que nombra los
///   dos y dice cómo devolver el remoto. Entre fallar abierto en el fallo más
///   caro del reintento y fallar cerrado con la salida escrita al lado, se
///   elige lo segundo.
///
/// **Residuo declarado, y sale de la misma decisión:** el analizador de URLs
/// solo conoce el puerto por omisión de los esquemas que conoce, así que
/// `ssh://host/x/y` y `ssh://host:22/x/y` dan identidades distintas aunque `22`
/// sea el puerto de ese protocolo. Falla cerrado, por el mismo lado que la
/// caja del dueño.
///
/// **No exige que este paquete ATIENDA el destino**, y eso no es un descuido:
/// lo que se compara con esta cadena es si el remoto de hoy es el de aquella
/// corrida, y esa pregunta tiene respuesta aunque ninguna forja conocida
/// atienda a ninguno de los dos. Hacerla depender de [salidaDePrDelRemoto]
/// devolvería nulo —«no sé quién es»— para un remoto que sí se puede nombrar,
/// y un nulo no se puede comparar con nada.
String? identidadDelDestino(String urlDelRemoto) {
  final remoto = _RemotoLeido.de(urlDelRemoto);
  if (remoto == null) return null;
  final puerto = remoto.puerto == null ? '' : ':${remoto.puerto}';
  return '${remoto.host.toLowerCase()}$puerto'
      '/${remoto.duenio}/${remoto.repositorio}';
}

/// Por qué [urlDelRemoto] no tiene una salida de pull requests, para quien ya
/// sabe —por el nulo de [salidaDePrDelRemoto]— que no la tiene.
///
/// **Existe para separar QUIÉN de POR DÓNDE, sin que quien compone tenga que
/// nombrar a esta forja para preguntarlo.** `salidaDePrDelRemoto` colapsa tres
/// motivos en un mismo nulo —remoto malformado, host que este paquete no
/// atiende, canal que no protege la credencial— porque para publicar los tres
/// valen lo mismo: no hay por dónde. Pero para EXPLICARLE a quien corre qué
/// hacer, los dos primeros son «esa forja no es una que se conozca» y el
/// tercero es «esa forja sí se conoce, y lo que falla es el protocolo del
/// remoto» — y son consejos distintos: al primero se le apunta a otra forja,
/// al segundo se le reescribe el mismo remoto en una forma segura. Sin esta
/// función, decírselo desde afuera exigiría que la raíz de composición
/// supiera comparar contra [_hostAtendido], que es exactamente el nombre que
/// la regla `forja-en-su-adapter` prohíbe que sepa.
///
/// **No se llama nunca sobre una URL que SÍ tiene salida.** Las dos preguntas
/// son mutuamente excluyentes por construcción —esta repite las mismas dos
/// condiciones que hacen fallar a [salidaDePrDelRemoto]—, así que llamarla ahí
/// sería preguntar por una causa que no existe.
enum CausaDeAusenciaDeForja {
  /// El remoto no nombra un repositorio, o su host no es uno que este
  /// paquete sepa atender.
  forjaDesconocida,

  /// El host SÍ es uno conocido; lo que no se atiende es el canal por el que
  /// llegó, porque no puede llevar la credencial sin exponerla.
  protocoloNoAtendible,
}

/// Deriva [CausaDeAusenciaDeForja] para [urlDelRemoto]. Ver esa clase.
CausaDeAusenciaDeForja causaDeAusenciaDeForja(String urlDelRemoto) {
  final remoto = _RemotoLeido.de(urlDelRemoto);
  if (remoto == null || remoto.host.toLowerCase() != _hostAtendido) {
    return CausaDeAusenciaDeForja.forjaDesconocida;
  }
  return CausaDeAusenciaDeForja.protocoloNoAtendible;
}

/// La forma corta con la que `git` escribe un remoto de `ssh`:
/// `usuario@host:duenio/repo`.
///
/// **No la puede leer un analizador de URLs** —no tiene esquema— y por eso se
/// reconoce antes. Lo que la distingue de una URL de verdad es que lo que
/// sigue a los dos puntos NO empieza con una barra: en `https://host/x` eso es
/// `//host/x`, así que esta expresión no lo toca.
final _formaCorta = RegExp(r'^(?:([^@/]+)@)?([^@/:]+):([^/].*)$');

/// Lo que hace falta saber de un remoto para armar la salida: quién es el
/// host, de quién es el repositorio, y la misma URL sin la credencial.
class _RemotoLeido {
  final String host;

  /// El puerto que la URL escribe explícitamente, o nulo cuando no escribe
  /// ninguno —o cuando el que escribe es el de omisión de su esquema, que el
  /// analizador de URLs ya unifica con no escribir ninguno—.
  ///
  /// **La forma corta de `ssh` no lo tiene**, y no es una omisión: en
  /// `usuario@host:duenio/repo` lo que sigue a los dos puntos es la ruta, no
  /// un puerto. Esa forma no puede nombrar uno.
  final int? puerto;

  final String duenio;
  final String repositorio;

  /// La URL tal como vino, **menos lo que de ella sea un secreto**, y por eso
  /// es la que se guarda para empujar y la que se le muestra al predicado que
  /// decide si este canal puede llevar la credencial.
  final String sinCredencial;

  const _RemotoLeido({
    required this.host,
    required this.puerto,
    required this.duenio,
    required this.repositorio,
    required this.sinCredencial,
  });

  /// Lee [url], o devuelve nulo si de ahí no salen las cuatro cosas.
  ///
  /// Nulo cubre por igual lo malformado y lo que está bien formado y no nombra
  /// un repositorio: las dos son «de acá no sale un destino», y separarlas
  /// pediría que quien compone supiera distinguirlas para hacer algo distinto,
  /// que no es el caso.
  static _RemotoLeido? de(String url) {
    final corta = _formaCorta.firstMatch(url.trim());
    if (corta != null) {
      final host = corta.group(2)!;
      final partes = _duenioYRepositorio(corta.group(3)!);
      if (partes == null) return null;
      // **Se le saca la contraseña y se le DEJA el nombre de usuario**, que
      // es la única forma de que lo que queda siga nombrando el mismo
      // destino: en esta forma el usuario no es la credencial sino la cuenta
      // con la que el protocolo resuelve la conexión, y tirarlo produciría
      // una URL que apunta a otro lado. La contraseña sí es un secreto y no
      // identifica nada, así que se va siempre.
      //
      // Lo que queda alcanza para lo único que se hace con él: preguntarle al
      // predicado de la publicación si este canal protege la credencial. La
      // respuesta es que no —esta forma ni siquiera tiene esquema—, así que
      // este texto no llega nunca a lo que se construye.
      final usuario = corta.group(1);
      final sinContrasenia = usuario == null
          ? ''
          : '${usuario.split(':').first}@';
      return _RemotoLeido(
        host: host,
        puerto: null,
        duenio: partes.duenio,
        repositorio: partes.repositorio,
        sinCredencial: '$sinContrasenia$host:${corta.group(3)}',
      );
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    if (uri.host.isEmpty) return null;
    final partes = _duenioYRepositorio(uri.path);
    if (partes == null) return null;
    return _RemotoLeido(
      host: uri.host,
      puerto: uri.hasPort ? uri.port : null,
      duenio: partes.duenio,
      repositorio: partes.repositorio,
      sinCredencial: uri.replace(userInfo: '').toString(),
    );
  }
}

/// De la ruta de un remoto, el dueño y el repositorio, o nulo.
///
/// **Se exigen exactamente dos segmentos.** Uno solo no nombra ningún
/// repositorio; tres o más no son una ruta que esta API entienda, y quedarse
/// con los dos primeros —o con los dos últimos— sería adivinar cuál de las dos
/// lecturas quiso quien la escribió.
({String duenio, String repositorio})? _duenioYRepositorio(String ruta) {
  var limpia = ruta.trim();
  while (limpia.startsWith('/')) {
    limpia = limpia.substring(1);
  }
  while (limpia.endsWith('/')) {
    limpia = limpia.substring(0, limpia.length - 1);
  }
  // El sufijo con el que `git` nombra un repositorio desnudo. No es parte del
  // nombre del repositorio en la API, así que se saca acá y no más abajo.
  if (limpia.endsWith('.git')) {
    limpia = limpia.substring(0, limpia.length - '.git'.length);
  }
  final segmentos = limpia.split('/');
  if (segmentos.length != 2) return null;
  if (segmentos.any((s) => s.trim().isEmpty)) return null;
  return (duenio: segmentos[0], repositorio: segmentos[1]);
}
