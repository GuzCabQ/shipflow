import 'dart:async';
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

  /// Cuánto se espera a que `git push` termine antes de matarlo.
  ///
  /// **Sin esto el flujo no producía NINGÚN desenlace.** `Process.run` sin
  /// límite espera a que el hijo salga, y `git push` puede no salir nunca:
  /// un remoto que acepta la conexión y deja de contestar, un `git` trabado
  /// en una espera propia. Eso contradice el invariante de que el desenlace
  /// se declara: un cuelgue no es un desenlace, es la ausencia de uno.
  ///
  /// **Dos minutos, y por qué ese número.** Un `git push` no es un pedido y
  /// una respuesta como los de la API —que viven con 30 segundos en
  /// `SalidaDePrDeGitHub`—: es una negociación de referencias MÁS la subida
  /// de un packfile cuyo tamaño depende de la rebanada, por el mismo enlace
  /// y con el mismo enlace de subida, que suele ser el lado angosto. Con 30
  /// segundos una subida lenta pero sana se convertiría en un [PushUnknown]
  /// —el peor desenlace que este archivo puede producir, porque manda a
  /// buscar un efecto que quizás ocurrió—. Más de dos minutos, en cambio,
  /// empieza a competir con el presupuesto de la corrida entera, que el
  /// README mide en minutos: el cuelgue que este límite existe para cortar
  /// se volvería indistinguible de una corrida que simplemente tarda. Dos
  /// minutos es el punto donde una subida que todavía progresa es rara y un
  /// cuelgue ya es evidente.
  ///
  /// **Lo que NO es:** un presupuesto de progreso. Mide tiempo total del
  /// proceso, no tiempo sin datos, así que una subida grande y sana que pase
  /// de dos minutos se corta igual. Cortarla por falta de progreso pediría
  /// leer el avance de `git` desde su salida, que es texto de progreso sin
  /// contrato — y este archivo ya declara que del texto de `git` solo deriva
  /// una causa cerrada.
  static const presupuestoPorDefecto = Duration(minutes: 2);

  /// Inyectable para que la prueba del vencimiento no espere dos minutos.
  final Duration presupuesto;

  const EmpujeAislado({
    required this.directorio,
    required this.entornoDelPadre,
    this.programa = 'git',
    this.presupuesto = presupuestoPorDefecto,
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

    // La SEGUNDA frontera, y por eso vuelve a preguntar lo mismo que
    // `PullRequestRequest` ya preguntó al construirse. **No es una
    // duplicación: es una precondición de ejecución.** Lo que se interpola
    // abajo es `'$revision:refs/heads/$rama'`, y con la revisión vacía eso
    // queda `:refs/heads/<rama>`, que es la forma documentada de BORRAR esa
    // rama del remoto. Este método es público, recibe la revisión como
    // parámetro suelto y no tiene forma de saber por dónde llegó: confiar en
    // que el llamador validó sería declarar un control que vive en otro
    // archivo, y el precio de equivocarse es el borrado de la rama de otro.
    //
    // Es un desenlace cerrado y no una excepción, por el mismo motivo que el
    // rechazo de arriba: `PullRequestSink` declara que `open` no lanza.
    if (!esOidCompleto(revision)) {
      return NoEmpujado(PushFailed(causa: CausaDePublicacion.revisionInvalida));
    }

    final sinGanchos = await Directory.systemTemp.createTemp('forge-ganchos-');
    try {
      final destino = credencial.use(
        (secreto) => _conCredencial(urlDelRemoto, secreto),
      );
      final Process proceso;
      try {
        // **`start` y no `run`.** `Process.run` espera a que el hijo termine
        // y no ofrece dónde poner un límite: con un remoto que acepta la
        // conexión y deja de contestar, ese `await` no vuelve nunca y la
        // corrida no produce ningún desenlace. `start` devuelve el proceso,
        // que es lo que hace falta para poder esperarlo CON presupuesto y,
        // sobre todo, para poder MATARLO cuando vence.
        //
        // El entorno se arma igual que antes y eso no es incidental:
        // `subprocesos-con-entorno-saneado` mira los tres lanzadores —`run`,
        // `runSync` y `start`— por elemento resuelto, así que cambiar de
        // lanzador no mueve la obligación ni un milímetro.
        proceso = await Process.start(
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
        );
      } on ProcessException {
        // No se pudo ni LANZAR `git`, y eso es distinto de no saber qué pasó.
        // `Process.start` es lo que obtiene el proceso; cuando falla, no hay
        // proceso, y sin proceso no hay nada que haya podido hablar con el
        // remoto. Decir `PushUnknown` acá mandaba a buscar un efecto remoto
        // que no pudo existir: el desenlace es `PushFailed`.
        //
        // **La causa es `noSePudoLanzar` y no `desconocida`.** La primera
        // versión de este arreglo dejó `desconocida` argumentando que, como
        // este `catch` no mira la excepción, no se sabe qué pasó. Eso
        // confundía NO LEER LA EXCEPCIÓN con NO SABER: *qué `catch` corrió*
        // es información propia del código y no del texto de la excepción,
        // así que nombrar el hecho no copia ni un byte de lo que esa
        // excepción traiga. Y «no se pudo determinar la causa» sobre un
        // `git` que no está en el `PATH` es falso y no accionable.
        //
        // Sigue siendo reintentable: un `fork` que falló por recursos puede
        // andar en el próximo intento, y para un `git` que falta el precio
        // es un reintento de más.
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
        return NoEmpujado(PushFailed(causa: CausaDePublicacion.noSePudoLanzar));
      }

      // **El stdin del hijo se cierra, y esto restituye algo que `run` hacía
      // solo.** `Process.run` cierra el stdin del hijo; `Process.start` lo
      // deja ABIERTO. Un `git` que decidiera leer de ahí —un `askpass` mal
      // configurado, una versión que pregunte algo— dejaba de fallar al
      // instante y pasaba a colgarse hasta agotar el presupuesto, saliendo
      // como `PushUnknown`: el cambio de lanzador habría convertido un fallo
      // inmediato en una duda de dos minutos.
      //
      // Sin esperar y tragando el error: si el hijo ya salió, cerrar su
      // stdin rompe la tubería y eso lanza, y una tubería rota del lado que
      // NO íbamos a usar no es un desenlace de la publicación.
      unawaited(proceso.stdin.close().catchError((Object _) {}));

      // **El drenaje empieza ANTES de esperar la salida, y no es opcional.**
      // Los dos flujos son tuberías con un buffer finito en el núcleo: un
      // hijo que escribe más de lo que entra ahí se BLOQUEA escribiendo
      // hasta que alguien lea. `git push` es locuaz —progreso por `stderr`,
      // mensajes del remoto— y un `git` bloqueado en su propia escritura
      // nunca sale, así que el presupuesto de arriba se cumpliría y
      // reportaría un vencimiento cuya causa real es que nosotros no
      // leímos. Sería un falso `unknown` fabricado por este archivo.
      final salidaEstandar = _Drenaje(proceso.stdout);
      final salidaDeError = _Drenaje(proceso.stderr);

      final int codigo;
      try {
        codigo = await proceso.exitCode.timeout(presupuesto);
      } on TimeoutException {
        // **`SIGKILL` y no `SIGTERM`.** Lo que se está cortando es un proceso
        // que ya demostró no avanzar; una señal que se puede ignorar deja
        // abierta la posibilidad de que la ignore y el cuelgue siga, que es
        // exactamente lo que este camino existe para terminar.
        proceso.kill(ProcessSignal.sigkill);
        // Se espera la MUERTE, no el cierre de los flujos. `exitCode` viene
        // de esperar al hijo y `SIGKILL` no se puede bloquear, así que esto
        // termina; esperar a que las tuberías se cierren, en cambio, sería
        // poner el cuelgue de vuelta un renglón más abajo, porque un nieto
        // que las heredó —`git` lanza `git-remote-https`— puede tenerlas
        // abiertas después de que el hijo murió.
        await proceso.exitCode;
        // **Y se SUELTAN, que no es lo mismo que no esperarlas.** Dejar de
        // esperar un futuro no cancela la suscripción que lo alimenta: la
        // tubería seguiría abierta y escuchada, y el proceso que corre esto
        // no puede terminar mientras haya una suscripción viva —`shipflow`
        // fija `exitCode` y vuelve de `main`, no llama a `exit`—. Medido: sin
        // cancelar, el desenlace se computaba en 624 ms y el proceso recién
        // terminaba a los 20,3 s, cuando moría el nieto.
        await salidaDeError.soltar();
        await salidaEstandar.soltar();
        // **`PushUnknown` y no `PushFailed`.** Al interrumpirlo se pierde la
        // única fuente que sabía cómo terminó: puede haber subido el
        // packfile entero y estar esperando el `report-status` del remoto,
        // con la rama ya actualizada del otro lado. Reportarlo como fallo
        // haría que quien reintenta creyera que no hay nada allá.
        return NoEmpujado(PushUnknown(causa: CausaDePublicacion.desconocida));
      }

      // **Una sola espera con presupuesto, y la otra se suelta sin esperar.**
      // El texto del hijo se mira en UN solo lugar —`_causaDe`, que clasifica
      // sobre `stderr`—, así que el contenido de `stdout` no hace falta una
      // vez que el proceso terminó: se drenó para que el hijo no se bloqueara
      // escribiendo, y ese trabajo ya está hecho. Esperarlo también sería un
      // tercer presupuesto en serie por un texto que nadie lee.
      //
      // La espera que sí queda lleva presupuesto por el mismo motivo que el
      // `if` de arriba manda a no esperar los cierres tras el `SIGKILL`: el
      // hijo salió, pero un descendiente suyo pudo heredar la tubería y
      // conservarla abierta, y entonces este `await` no vuelve nunca y
      // `empujar` se cuelga sin producir ningún desenlace. Al vencer se
      // SUELTA la tubería —cancela la suscripción— y se devuelve lo que se
      // alcanzó a leer: lo que se pierde es parte del texto con el que se
      // clasifica la causa, que degrada a `desconocida` —un reintento de
      // más— y nunca a una publicación que se lea como completa.
      //
      // **El peor caso es el presupuesto dos veces**, y está declarado: la
      // espera de la salida más esta. Es el mismo valor a propósito —es la
      // misma pregunta, «¿esto termina?», en dos momentos del mismo
      // lanzamiento— y no un segundo número que ajustar por su cuenta.
      final textoDeError = await salidaDeError.texto(presupuesto);
      await salidaEstandar.soltar();
      if (codigo == 0) return const Empujado();
      return NoEmpujado(PushFailed(causa: _causaDe(textoDeError)));
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

/// Un flujo del hijo que se lee a medida que llega **y que se puede soltar**.
///
/// **Por qué es una clase y no un `join()` con `.timeout(...)`.** Esa forma
/// —la que tenía este archivo— parecía cerrar el cuelgue y lo mudaba: el
/// `timeout` ABANDONA el futuro, pero no cancela la suscripción que lo
/// alimenta. La tubería queda abierta y escuchada, y un proceso con una
/// suscripción viva no termina — el ejecutable del comando, bajo
/// `packages/cli/bin/`, fija `exitCode` y vuelve de `main` a propósito, en vez
/// de llamar a `exit`, que mataría el proceso con trabajo pendiente.
///
/// **Medido**, con un programa que deja un nieto con la tubería heredada
/// (`sh -c 'sleep 20 & exit 0'`) y un presupuesto de 300 ms:
///
/// | forma | desenlace | fin del proceso |
/// |---|---|---|
/// | `join()` abandonado por `timeout` | 624 ms | **20,3 s** — cuando muere el nieto |
/// | `listen` + `cancel()` al vencer | 624 ms | **0,9 s** |
///
/// En producción ese nieto es `git-remote-https` contra una conexión muerta,
/// o sea sin cota: el proceso queda vivo hasta que el sistema corte el
/// socket. Cancelar la suscripción es lo único que cierra el descriptor.
///
/// **El texto ya leído se conserva** al soltar: se acumula a medida que
/// llega, no al final, así que un vencimiento pierde lo que faltaba y no lo
/// que ya había.
final class _Drenaje {
  final StringBuffer _acumulado = StringBuffer();
  final Completer<void> _cerrado = Completer<void>();
  late final StreamSubscription<String> _suscripcion;

  /// **`allowMalformed`**, porque lo que sale de `git` son bytes y no una
  /// promesa de UTF-8: un nombre de rama o un mensaje del remoto en otra
  /// codificación haría que el decodificador estricto lanzara, y esa
  /// excepción escaparía de `empujar` —que el puerto declara que no lanza—
  /// en vez de convertirse en una causa.
  ///
  /// **Y un error del flujo termina el drenaje en vez de propagarse**: lo que
  /// queda es el texto leído hasta ahí, que el clasificador lee como una
  /// causa más pobre —un reintento de más—, nunca como una publicación
  /// completa.
  _Drenaje(Stream<List<int>> flujo) {
    _suscripcion = const Utf8Decoder(allowMalformed: true)
        .bind(flujo)
        .listen(
          _acumulado.write,
          onError: (Object _) => _marcarCerrado(),
          onDone: _marcarCerrado,
          cancelOnError: true,
        );
  }

  void _marcarCerrado() {
    if (!_cerrado.isCompleted) _cerrado.complete();
  }

  /// Lo que el hijo escribió, esperando a que el flujo termine **con
  /// [presupuesto]**. Si vence, suelta la tubería y devuelve lo leído.
  Future<String> texto(Duration presupuesto) async {
    try {
      await _cerrado.future.timeout(presupuesto);
    } on TimeoutException {
      await soltar();
    }
    return _acumulado.toString();
  }

  /// Suelta la tubería **sin esperar a que termine**: cancela la suscripción,
  /// que es lo que cierra el descriptor de este lado.
  ///
  /// `cancel()` no espera a que el que escribe deje de escribir —por eso es
  /// seguro llamarlo con un nieto vivo del otro lado—, y llamarlo dos veces
  /// no es un error.
  Future<void> soltar() async {
    await _suscripcion.cancel();
    _marcarCerrado();
  }
}
