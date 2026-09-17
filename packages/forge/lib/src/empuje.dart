import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

/// El desenlace del empuje. **Sellado y no un nulo**: «nulo quiere decir que
/// salió bien» es una convención que hay que recordar en cada llamada.
sealed class ResultadoDeEmpuje {
  const ResultadoDeEmpuje();
}

final class Empujado extends ResultadoDeEmpuje {
  const Empujado();
}

final class NoEmpujado extends ResultadoDeEmpuje {
  final PublicacionNoUtilizable desenlace;
  const NoEmpujado(this.desenlace);
}

/// ¿Se le puede adjuntar la credencial a este destino sin que viaje en claro?
///
/// **Valida, no declara.** Los DOS canales que llevan el secreto fuera de este
/// proceso —el `userinfo` de la URL del `git push` y el encabezado
/// `Authorization` del cliente de la API— arman su destino a partir de una
/// cadena que produce la raíz de composición, no este paquete. Con `http://`
/// el token viaja legible para cualquiera que esté en el camino, y ninguna
/// prosa lo impide: por eso lo impide esta función, que los dos llaman ANTES
/// de adjuntar nada.
///
/// **La excepción, decidida y no dejada por las dudas: `http` sobre
/// loopback.** Un destino de loopback —`127.0.0.0/8`, `::1`, o el nombre
/// `localhost`— no sale de la máquina: no hay «camino» donde interceptarlo, y
/// exigirle TLS obligaría a cada suite que levanta un `HttpServer` local a
/// montar un certificado propio, con lo que el control terminaría probándose
/// contra un montaje que no es el de producción. Es la misma excepción que
/// hace RFC 8252 §8.3 para el redirect de loopback de OAuth, y por el mismo
/// motivo.
///
/// **Residuo declarado de esa excepción:** el nombre `localhost` se acepta por
/// su TEXTO, no por la dirección a la que resuelva. Un `/etc/hosts` que lo
/// apunte a una máquina remota haría viajar el token en claro y esta función
/// no lo vería. Resolverlo acá significaría hacer DNS dentro de una validación
/// sincrónica, y el resultado seguiría sin ser el que use el subproceso `git`,
/// que resuelve por su cuenta cuando se conecta: la comprobación sería una
/// segunda resolución, no la misma.
///
/// **Lo que tampoco pasa: un esquema que no sea `http` ni `https`.** Un remoto
/// `ssh://` o `git@host:org/repo.git` no se rechaza por inseguro sino porque
/// [EmpujeAislado] adjunta la credencial en el `userinfo`, que ahí no
/// significa nada: quien empuja por SSH se autentica con su clave y no
/// necesita esta credencial en absoluto. Llegar acá con uno de esos es una
/// configuración equivocada, no un canal que haya que tolerar.
bool esCanalSeguroParaLaCredencial(String url) {
  final uri = Uri.tryParse(url);
  // Una URL que ni siquiera parsea no puede declararse segura: no mirar no es
  // lo mismo que no encontrar nada.
  if (uri == null) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  if (uri.host == 'localhost') return true;
  final direccion = InternetAddress.tryParse(uri.host);
  return direccion != null && direccion.isLoopback;
}

/// Empuja una revisión a una rama del remoto **sin entregarle la credencial a
/// ningún programa del usuario**.
///
/// Dos `-c`, y los dos son el mismo mecanismo que el `core.hooksPath` con el
/// que `vcs` commitea:
///
/// - `core.hooksPath` a un directorio vacío frena TODOS los ganchos. Medido:
///   con el token en el entorno de `git`, un `pre-push` lo recibe verbatim.
/// - `credential.helper` vacío **resetea la cadena entera** del usuario.
///   `core.hooksPath` no la gobierna: medido, el helper corre igual —dos
///   veces— y ve el entorno completo.
///
/// Y la credencial viaja en la URL de destino, de un solo uso, **nunca en el
/// entorno**. El canal que parecía más seguro no lo era: `-c
/// http.extraHeader=` con el token le llega a ese helper por entorno, como
/// `GIT_CONFIG_PARAMETERS`. Por `ps` parece argv porque el padre del helper es
/// `git-remote-http`; elegirlo por eso sería decidir sobre una representación
/// más pobre que el criterio.
///
/// **Residuo declarado:** `/proc/<pid>/cmdline` en Linux deja ver el argv de
/// nuestro propio `git`. Es limitación de ambiente, no un fallo que causemos
/// nosotros — a diferencia de entregarle el token a un programa que el usuario
/// eligió y nosotros ejecutamos.
class EmpujeAislado {
  final String directorio;

  /// El entorno del padre. **Es [EntornoDelProceso] y no un mapa, y el tipo
  /// es el control**: `RepositorioGit` y `EjecutorDelSistema` ya tienen esta
  /// forma. Con un mapa crudo, un llamador distraído podía pasar el entorno
  /// del padre entero —token incluido— confiando en que `entornoSaneado` lo
  /// recortaría más abajo; con este tipo, lo que sale de acá ya pasó por
  /// `paraHijos` antes de que este lanzamiento exista.
  final EntornoDelProceso entornoDelPadre;

  final String programa;

  const EmpujeAislado({
    required this.directorio,
    required this.entornoDelPadre,
    this.programa = 'git',
  });

  Future<ResultadoDeEmpuje> empujar({
    required String urlDelRemoto,
    required Credential credencial,
    required String revision,
    required String rama,
  }) async {
    // ANTES de crear nada y antes de tocar la credencial: con un remoto que
    // no es `https` el secreto viajaría en claro en el `userinfo`. Es un
    // desenlace cerrado y no una excepción —el llamador de `empujar` es
    // `SalidaDePrDeGitHub.open`, y `PullRequestSink` declara que `open` no
    // lanza por un fallo remoto—, y no nombra la URL: es justamente la que
    // iba a llevar el secreto adjunto.
    if (!esCanalSeguroParaLaCredencial(urlDelRemoto)) {
      return NoEmpujado(
        PushFailed(causa: CausaDePublicacion.configuracionInsegura),
      );
    }

    final sinGanchos = await Directory.systemTemp.createTemp('forge-ganchos-');
    try {
      final destino = credencial.use(
        (secreto) => _conCredencial(urlDelRemoto, secreto),
      );
      final ProcessResult r;
      try {
        r = await Process.run(
          programa,
          [
            '-c',
            'core.hooksPath=${sinGanchos.path}',
            '-c',
            'credential.helper=',
            'push',
            destino,
            '$revision:refs/heads/$rama',
          ],
          workingDirectory: directorio,
          environment: entornoSaneado(entornoDelPadre.paraHijos),
          includeParentEnvironment: false,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
      } on ProcessException {
        // No se pudo ni lanzar `git`. No sabemos si algo salió.
        //
        // **Esta excepción no se nombra, no se loguea, no se relanza y no se
        // encadena — nunca.** `ProcessException.arguments` es la lista de
        // argumentos con la que se intentó lanzar el proceso, y acá `destino`
        // —la URL con la credencial en el `userinfo`— es uno de ellos. Su
        // propio `toString()` los interpola verbatim: `"Command: $executable
        // $args"`, tal como documenta esa clase en la biblioteca estándar de
        // entrada y salida. Agregar el mensaje a un log, a una traza o a una
        // causa de una excepción propia filtraría el secreto por el único
        // canal de este archivo que no es `Credential`. Lo único que sale de
        // este `catch` es una causa cerrada, igual que en el resto del
        // archivo.
        return NoEmpujado(PushUnknown(causa: CausaDePublicacion.desconocida));
      }
      if (r.exitCode == 0) return const Empujado();
      return NoEmpujado(PushFailed(causa: _causaDe(r.stderr as String)));
    } finally {
      await sinGanchos.delete(recursive: true);
    }
  }

  /// Solo para la suite: `_causaDe` es privada, y esta es la forma de probar
  /// el clasificador contra salidas de `git` que son costosas o difíciles de
  /// provocar de verdad con un servidor de prueba (un 403 se reproduce fácil;
  /// un rechazo por no ser fast-forward necesita un remoto que ya avanzó).
  ///
  /// **Sin `@visibleForTesting`.** `meta` no es una dependencia declarada de
  /// `forge` —solo llegaría transitiva por el lockfile del workspace— e
  /// importarla igual deja el análisis marcando «no es una dependencia», que
  /// con `--fatal-infos` es rojo. El nombre ya dice que es de prueba; eso
  /// alcanza, igual que en `RepositorioGit.identidadCapturadaParaLaPrueba`.
  static CausaDePublicacion causaDeParaLaPrueba(String stderr) =>
      _causaDe(stderr);

  /// Mete la credencial en el `userinfo` de la URL. **No se registra en
  /// ningún lado**: es un destino de un solo uso, no un remoto configurado.
  static String _conCredencial(String url, String secreto) {
    final u = Uri.parse(url);
    return u
        .replace(userInfo: 'x-access-token:${Uri.encodeComponent(secreto)}')
        .toString();
  }

  /// Clasifica **sin copiar nada**: lo que sale de acá es una causa cerrada, y
  /// `safeReason` se deriva de ella. El texto de `git` no se propaga.
  ///
  /// **Residuo declarado:** la clasificación mira el texto de nuestro propio
  /// hijo, que es un universo acotado por construcción. Un mensaje que no
  /// reconozca cae en `desconocida`, que es reintentable: el precio de errar
  /// es un reintento de más, nunca una publicación que se lea como completa.
  static CausaDePublicacion _causaDe(String stderr) {
    final t = stderr.toLowerCase();
    if (t.contains('authentication failed') ||
        t.contains('invalid username or password')) {
      return CausaDePublicacion.autenticacion;
    }
    if (t.contains('permission denied') ||
        t.contains('denied to') ||
        t.contains('403')) {
      return CausaDePublicacion.permisos;
    }
    if (t.contains('could not resolve host') ||
        t.contains('failed to connect') ||
        t.contains('connection refused') ||
        t.contains('operation timed out')) {
      return CausaDePublicacion.red;
    }
    if (t.contains('rejected') || t.contains('non-fast-forward')) {
      return CausaDePublicacion.rechazoDeLaForja;
    }
    return CausaDePublicacion.desconocida;
  }
}
