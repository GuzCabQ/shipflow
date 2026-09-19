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
  final String duenio;
  final String repositorio;

  /// La URL tal como vino, **menos lo que de ella sea un secreto**, y por eso
  /// es la que se guarda para empujar y la que se le muestra al predicado que
  /// decide si este canal puede llevar la credencial.
  final String sinCredencial;

  const _RemotoLeido({
    required this.host,
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
