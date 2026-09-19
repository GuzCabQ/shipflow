/// El cliente de GitHub: la primera implementación viva de `PullRequestSink`.
///
/// Habla con la API REST usando solo la biblioteca estándar de entrada y
/// salida del lenguaje —sin dependencias externas, como pide `contexto.md`—
/// y hace la búsqueda idempotente que impide que un reintento abra un
/// segundo pull request.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

import 'cuerpo.dart';
import 'empuje.dart';

/// Dónde vive el repositorio y cómo se habla con su API. **Quién es la
/// forja no lo sabe `core`**: vive acá, en su propio adapter.
class ConfiguracionDeGitHub {
  final String duenio;
  final String repositorio;
  final Uri baseDeLaApi;
  final String urlDelRemoto;

  const ConfiguracionDeGitHub({
    required this.duenio,
    required this.repositorio,
    required this.baseDeLaApi,
    required this.urlDelRemoto,
  });
}

/// La línea del marcador estable: la clave de la búsqueda idempotente.
///
/// **Vive acá y no en quien arma el cuerpo del PR**, porque es
/// [SalidaDePrDeGitHub] quien la busca — la clave de una búsqueda pertenece a
/// quien busca. `cuerpoDeGitHub`, en el módulo vecino que arma el cuerpo,
/// llama a esta misma función para incluir la línea, así que la búsqueda y el
/// render comparten una única fuente para la clave.
///
/// Va en el cuerpo y no en el título porque el título se trunca (ver
/// `PullRequestRequest.titulo`). Lleva su propio `formatVersion` —del
/// marcador, no de ningún otro formato del repositorio— para poder
/// DISTINGUIR una forma de otra el día que esta línea cambie.
///
/// **Lo que ese campo NO hace hoy, y hay que decirlo porque la diferencia es
/// de comportamiento:** no existe ninguna ruta que lea una versión distinta
/// de la actual. La búsqueda es `cuerpoDelPr.contains(marcador)` con el
/// marcador que produce ESTA función (ver [SalidaDePrDeGitHub._buscarExistente]),
/// así que subir a `formatVersion=2` dejaría de encontrar todos los pull
/// requests que llevan la forma vieja. Quien suba la versión tiene que
/// escribir esa ruta —buscar por cada forma conocida, no solo por la
/// actual— o aceptar que el corte pierde a los anteriores.
String marcadorEstable(PullRequestRequest solicitud) =>
    '<!-- shipflow:pr formatVersion=1 '
    'runId=${solicitud.draft.runId} revision=${solicitud.revision} -->';

/// La salida real: por acá sale un pull request de verdad.
///
/// **El título y el cuerpo que arma [open] son `tituloDeGitHub` y
/// `cuerpoDeGitHub`**, en el módulo vecino que arma el cuerpo: la única pieza
/// que conoce la sintaxis de GitHub —la alerta `> [!WARNING]`, el límite de
/// 256 caracteres del título—. Este archivo solo llama a esa función y a
/// [marcadorEstable] para la búsqueda idempotente; no arma sintaxis de
/// proveedor por su cuenta.
class SalidaDePrDeGitHub implements PullRequestSink {
  final ConfiguracionDeGitHub configuracion;
  final CredentialSource credenciales;
  final EmpujeAislado empuje;
  final HttpClient Function() _crearCliente;
  final Duration _presupuestoDeRed;

  /// **30 segundos por pedido**, no por toda la llamada a [open]. Cubre las
  /// TRES fases en las que un pedido puede quedarse esperando para
  /// siempre: conectar (`HttpClient.connectionTimeout`, para el extremo que
  /// descarta el `SYN` en silencio — un firewall, una ruta muerta, una IP
  /// que no contesta), recibir la respuesta (`close()`) y leer el cuerpo.
  /// Es el mismo valor para las tres a propósito: son la misma pregunta
  /// —¿el otro lado contestó a tiempo?— hecha en tres momentos distintos
  /// del mismo pedido, y no hay motivo para que uno tolere una espera
  /// distinta de otro.
  ///
  /// Treinta segundos es generoso para una respuesta HTTP de un solo
  /// pedido —búsqueda o creación— contra una API remota: cubre una
  /// lentitud de red real sin acercarse al presupuesto de la corrida
  /// entera, que se mide en minutos. Un valor más corto arriesgaba falsos
  /// `unknown` en una red simplemente lenta; uno más largo dejaba la
  /// corrida completa esperando por un solo pedido colgado casi tanto como
  /// si no hubiera límite. Inyectable para que la prueba del vencimiento
  /// no tenga que esperar treinta segundos.
  static const presupuestoDeRedPorDefecto = Duration(seconds: 30);

  SalidaDePrDeGitHub({
    required this.configuracion,
    required this.credenciales,
    required this.empuje,
    HttpClient Function()? clienteHttp,
    Duration presupuestoDeRed = presupuestoDeRedPorDefecto,
  }) : _crearCliente = clienteHttp ?? HttpClient.new,
       _presupuestoDeRed = presupuestoDeRed;

  @override
  Future<PublicationOutcome> open(PullRequestRequest request) async {
    final credencial = await credenciales.read(claveDeCredencialDeLaForja);
    if (credencial == null) {
      // Sin credencial no se toca la red: no hay con qué autenticar ni la
      // búsqueda ni el push. Es `PushFailed` y no `PullRequestFailed` porque
      // todavía no se intentó nada de lo que hace específicamente a un pull
      // request — nada remoto ocurrió en absoluto.
      return PushFailed(causa: CausaDePublicacion.autenticacion);
    }

    // Con una `baseDeLaApi` que no es `https`, el `Bearer <token>` que arma
    // `_autenticar` viaja legible: el encabezado se cifra o no según el
    // esquema de la URL, y quien produce esa URL es la raíz de composición,
    // no este adapter. Se valida acá —una vez, antes del primer pedido— y no
    // adentro de `_autenticar`, porque las DOS URLs que este archivo arma
    // salen de la misma `baseDeLaApi`: validarla una vez cubre la búsqueda y
    // la creación, y deja un solo lugar donde mirar.
    //
    // Es `PushFailed` por el mismo motivo que la rama de arriba: nada remoto
    // ocurrió en absoluto, ni siquiera se abrió un socket, así que todavía no
    // se intentó nada que haga específicamente a un pull request. Y el
    // desenlace no nombra la URL — es justamente la que iba a llevar la
    // credencial adjunta.
    if (!esCanalSeguroParaLaCredencial(configuracion.baseDeLaApi.toString())) {
      return PushFailed(causa: CausaDePublicacion.configuracionInsegura);
    }

    final cliente = _crearCliente();
    // La fase de CONEXIÓN no la cubre `.timeout(...)` sobre `close()`: para
    // cuando esa llamada existe, la conexión ya se estableció. Un extremo
    // que descarta el `SYN` en silencio —firewall, ruta muerta, IP que no
    // contesta— cuelga adentro de `getUrl`/`postUrl`, antes de que haya
    // nada que envolver en `.timeout(...)`. `connectionTimeout` es el
    // límite que `HttpClient` ya trae para esa fase específica.
    cliente.connectionTimeout = _presupuestoDeRed;
    try {
      // **Lo que devuelve la búsqueda corta la corrida, y no siempre porque
      // haya encontrado algo.** Puede ser el pull request que ya existe, o
      // puede ser un fallo de la búsqueda misma —una página que contestó
      // `401`, un `Link` fuera del origen, el tope de páginas agotado—. Los
      // dos frenan acá, y por el mismo motivo: seguir hacia la creación con
      // la búsqueda incompleta es abrir un segundo pull request a ciegas.
      final PublicationOutcome? desenlaceDeLaBusqueda;
      try {
        desenlaceDeLaBusqueda = await _buscarExistente(
          cliente,
          request,
          credencial,
        );
      } on Object {
        // Solo llega acá lo que no es una respuesta clasificable: una
        // excepción de transporte, un vencimiento, o un cuerpo que dice ser
        // una lista y no lo es. Los códigos de estado ya los clasificó
        // `_buscarExistente` y no pasan por este `catch`.
        //
        // La búsqueda es de solo lectura: no tiene efecto remoto que dejar a
        // medias. Un fallo acá es un fallo común y reintentable, no un
        // `unknown` — `unknown` está reservado para el paso que sí puede
        // haber escrito algo del otro lado.
        return PullRequestFailed(causa: CausaDePublicacion.red);
      }
      if (desenlaceDeLaBusqueda != null) return desenlaceDeLaBusqueda;

      final resultadoDelEmpuje = await empuje.empujar(
        urlDelRemoto: configuracion.urlDelRemoto,
        credencial: credencial,
        revision: request.revision,
        rama: request.draft.branch,
      );
      // `NoEmpujado.desenlace` ya es un `PublicationOutcome`: se devuelve tal
      // cual, sin envolverlo en nada que pierda la distinción entre `push`
      // fallido y `push` desconocido que `EmpujeAislado` ya hizo.
      if (resultadoDelEmpuje is NoEmpujado) {
        return resultadoDelEmpuje.desenlace;
      }

      return await _crearPr(cliente, request, credencial);
    } finally {
      // **`force: true` es EL mecanismo que suelta, no una prolijidad.**
      //
      // Todos los `.timeout(...)` de este archivo ABANDONAN lo que estaban
      // esperando: un futuro abandonado no cancela la lectura que lo
      // alimentaba ni cierra el socket de abajo. Con un extremo que manda
      // encabezados y no cierra el cuerpo, `open` devuelve a tiempo —eso lo
      // comprueban las pruebas de la paginación— y el proceso queda vivo con
      // el socket abierto. `packages/cli/bin/` vuelve de `main` en vez de
      // llamar a `exit`, así que eso es el comando que no termina.
      //
      // Medido contra un servidor así, con un proceso que vuelve de `main`:
      // con `force: true` el proceso termina en 0,5 s; con `close()` a secas
      // seguía vivo a los 400 s, cuando lo maté. La diferencia es esta
      // palabra.
      //
      // **Se eligió un mecanismo único y declarado antes que cancelar en cada
      // sitio.** Cancelar suscripción por suscripción dejaría afuera la fase
      // de PEDIDO —`pedido.close().timeout(...)` espera un futuro, no un
      // flujo: ahí no hay suscripción que cancelar, haría falta `abort()`— y
      // dejaría igual el grupo de conexiones abierto. Cerrar el cliente
      // cubre las tres fases de los dos pedidos de una vez.
      //
      // Lo sostiene «el proceso TERMINA aunque la forja deje el cuerpo a
      // medias», en la suite de este archivo, que mide el fin de un proceso
      // de verdad: si alguien saca el `force`, esa prueba se pone roja.
      cliente.close(force: true);
    }
  }

  /// Encabeza el pedido con la credencial. **Nunca la interpola fuera de
  /// [Credential.use]**: el encabezado se arma adentro, y lo que sale de acá
  /// es el pedido ya autenticado, nunca el secreto suelto.
  ///
  /// **Y apaga el seguimiento de redirects ANTES de adjuntarla, en la misma
  /// función y no en cada sitio de llamada.** Un pedido con
  /// `followRedirects = true` —el valor por omisión de `HttpClient`— sigue
  /// por su cuenta el `3xx` que conteste el otro lado, y el destino de ese
  /// salto lo elige la RESPUESTA, no la configuración. Esta es la única
  /// función que pone el `Authorization`, así que apagarlo acá es lo que
  /// hace imposible que un pedido salga autenticado y seguidor a la vez:
  /// ponerlo en los dos sitios de llamada sería una disciplina que el
  /// próximo pedido puede olvidar.
  ///
  /// **Lo que el SDK hace por su cuenta NO alcanza, y está medido.** Una
  /// revisión anterior dio esto por seguro porque la biblioteca de entrada y
  /// salida no copia el `authorization` cuando el redirect cambia de
  /// esquema, host o puerto. La regla real es más ancha:
  /// `_HttpClient.shouldCopyHeaderOnRedirect` copia TODOS los encabezados
  /// —`authorization` incluido— cuando `_isSubdomain(destino, origen)`, y
  /// esa función da verdadero si el host del destino **termina en `.` más el
  /// host del origen**. Medido en esta plataforma con el SDK 3.12.0 del
  /// lenguaje (la implementación del cliente HTTP en su biblioteca de entrada
  /// y salida, `lib/_http/http_impl`), con la API en `http://localhost:<puerto>`
  /// y un `302` —y un `303` para el `POST`— hacia
  /// `http://sub.localhost:<el mismo puerto>`: el segundo destino recibió
  /// `Authorization: Bearer <secreto>` en los dos métodos. O sea que el
  /// filtro del SDK protege del salto a otro host, y no del salto a un
  /// SUBDOMINIO del configurado, que es el que un `Location` hostil elige.
  ///
  /// **Y el `3xx` no se sigue a mano tampoco.** Se podría, validando esquema,
  /// host y puerto exactos con [_mismoOrigen] antes de repetir el pedido;
  /// no se hace porque un redirect DENTRO del mismo origen no agrega nada
  /// que la API de esta forja necesite —sus dos URLs salen de
  /// `baseDeLaApi`—, y cada camino que reintenta con la credencial adjunta
  /// es un camino más donde revalidar. El `3xx` se trata como respuesta
  /// fallida: en la búsqueda cae en la rama de «no es 200» —la búsqueda
  /// quedó incompleta— y en la creación tiene su propia rama, porque ahí un
  /// `303` puede venir DESPUÉS de haber creado el pull request.
  void _autenticar(HttpClientRequest pedido, Credential credencial) {
    // Antes del encabezado, no después: lo que se está impidiendo es que
    // este mismo pedido lleve la credencial a un destino que elija la
    // respuesta.
    pedido.followRedirects = false;
    pedido.headers.set(
      HttpHeaders.authorizationHeader,
      credencial.use((secreto) => 'Bearer $secreto'),
    );
    pedido.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    pedido.headers.set('X-GitHub-Api-Version', '2022-11-28');
  }

  Uri _urlDePulls({Map<String, String>? query}) {
    final base = configuracion.baseDeLaApi;
    final path =
        '${base.path}/repos/${configuracion.duenio}/${configuracion.repositorio}/pulls';
    return query == null
        ? base.replace(path: path)
        : base.replace(path: path, queryParameters: query);
  }

  /// Cuántos pull requests se piden por página.
  ///
  /// **Medido contra el contrato del proveedor, no elegido**: esta operación
  /// pagina, con 30 elementos por omisión y 100 como máximo configurable. Se
  /// pide el máximo porque cada página es un pedido más —con su propio
  /// presupuesto de red y su propia chance de fallar—, no porque 100 alcance:
  /// [_maximoDePaginas] existe justamente porque no alcanza.
  static const _porPagina = 100;

  /// El tope de páginas que la búsqueda recorre, **y por qué hay uno**.
  ///
  /// El recorrido termina cuando una respuesta ya no trae `rel="next"`. Eso
  /// depende de lo que conteste el otro lado, y un `Link` que apunte a una
  /// página ya vista —un proxy mal configurado, una forja con un bug de
  /// paginación, una respuesta hostil— haría girar este bucle para siempre:
  /// el cuelgue que el presupuesto por pedido NO cubre, porque cada pedido
  /// individual contesta a tiempo.
  ///
  /// Diez páginas de a 100 son mil pull requests para la MISMA rama origen y
  /// la MISMA rama base. Un repositorio real no llega ahí: la consulta ya
  /// está filtrada por `head` y `base`. O sea que agotar el tope no significa
  /// «hay más de mil», significa que las páginas no se agotan, y por eso el
  /// desenlace de agotarlo no es «no encontré nada» sino un fallo — ver
  /// [_buscarExistente].
  static const _maximoDePaginas = 10;

  /// Cómo se lee un código de estado de la forja. **Uno solo para los dos
  /// pedidos**, y eso es el arreglo y no una refactorización.
  ///
  /// La búsqueda no miraba el código: le pasaba cualquier cuerpo a
  /// `jsonDecode(...) as List<Object?>`. Un `401` de la forja trae un OBJETO
  /// —`{"message": "Bad credentials", ...}`—, el cast fallaba, y el `catch`
  /// exterior de [open] lo convertía en `PullRequestFailed(red)`: «la red
  /// falló» sobre una credencial rechazada. Y como la corrida se detenía ahí,
  /// en el GET, la clasificación correcta del `401` del POST era
  /// prácticamente inalcanzable — estaba escrita y no la llegaba a ejercer
  /// nadie.
  ///
  /// **El cuerpo de la respuesta de error no se mira nunca**, ni acá ni en la
  /// creación: solo el código decide la causa. Copiar el texto del servidor a
  /// `safeReason` sería exactamente lo que esa cadena promete no hacer.
  ///
  /// **Residuo declarado:** un `403` de esta forja también aparece por límite
  /// de tasa, no solo por permisos insuficientes. Se clasifica como
  /// `permisos` —que es lo que ya hacía la creación, y la coherencia entre
  /// los dos pedidos es lo que esta función existe para garantizar—, con el
  /// precio de que un límite de tasa se reporta como no reintentable. Separar
  /// los dos pide mirar los encabezados de límite de tasa, que es un control
  /// nuevo y no un arreglo de este.
  static CausaDePublicacion _causaDelCodigo(int codigo) => switch (codigo) {
    HttpStatus.unauthorized => CausaDePublicacion.autenticacion,
    HttpStatus.forbidden => CausaDePublicacion.permisos,
    HttpStatus.unprocessableEntity => CausaDePublicacion.rechazoDeLaForja,
    _ => CausaDePublicacion.desconocida,
  };

  /// Un enlace del encabezado `Link`: `<url>; rel="next", <url>; rel="last"`.
  static final _patronDeEnlace = RegExp(r'<([^>]*)>([^,]*)');

  /// El valor de `rel` dentro de los parámetros de UN enlace.
  static final _patronDeRel = RegExp(r'\brel\s*=\s*"?([^";]*)"?');

  /// La URL de la página siguiente, o `null` si esta era la última.
  ///
  /// **Sale del encabezado `Link` y no de contar elementos.** «Vinieron menos
  /// de [_porPagina], entonces se acabó» es una inferencia sobre el
  /// comportamiento del servidor, no su contrato; el contrato es este
  /// encabezado, y es el que la forja documenta para recorrer el resto.
  static Uri? _siguientePagina(HttpClientResponse respuesta, Uri pedida) {
    // `HttpHeaders` no tiene constante para este encabezado; el nombre va
    // literal. La biblioteca de entrada y salida compara los nombres en
    // minúscula, así que `Link` y `link` son el mismo.
    final valores = respuesta.headers['link'];
    if (valores == null) return null;
    for (final valor in valores) {
      for (final enlace in _patronDeEnlace.allMatches(valor)) {
        final rel = _patronDeRel.firstMatch(enlace.group(2)!)?.group(1);
        if (rel == null) continue;
        // `rel` admite varios tipos separados por espacios; lo que importa es
        // que `next` sea uno de ellos, no que sea el texto entero.
        if (!rel.trim().split(RegExp(r'\s+')).contains('next')) continue;
        return pedida.resolve(enlace.group(1)!.trim());
      }
    }
    return null;
  }

  /// ¿Las dos URLs son del MISMO origen?
  ///
  /// Hace falta porque cada página se pide con el `Authorization` puesto. Un
  /// `Link` que apuntara a otro host mandaría la credencial ahí, a un destino
  /// que eligió la respuesta y no la configuración — y `open` valida el canal
  /// UNA vez, sobre `baseDeLaApi`, precisamente porque hasta esta ronda todas
  /// las URLs salían de ella.
  ///
  /// **Exacta, y eso es el punto: un subdominio NO es el mismo origen.** Es
  /// justamente donde la regla del SDK se queda corta —`_isSubdomain`, en la
  /// implementación del cliente HTTP de su biblioteca de entrada y salida,
  /// acepta cualquier host que termine en `.` más
  /// el host original y por eso copia el `authorization` hacia
  /// `sub.localhost`—. Acá los tres componentes se comparan por igualdad, así
  /// que `api.forja` y `malo.api.forja` son orígenes distintos. Quien afloje
  /// esta comparación a un sufijo reabre, por el camino del `Link`, el mismo
  /// agujero que [_autenticar] cierra por el camino del redirect.
  static bool _mismoOrigen(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  /// La búsqueda idempotente. **Rama y base no alcanzan**: una rama
  /// reutilizada recuperaría un PR ajeno. La clave completa es
  /// repositorio/remoto (fijos en [configuracion]), rama origen, rama base,
  /// la revisión esperada, el marcador estable con su propio `runId` y
  /// `revision`, y el estado del PR.
  ///
  /// **Recorre TODAS las páginas, no la primera.** La forja pagina esta
  /// operación y entrega el resto por el encabezado `Link`. Una sola petición
  /// dejaba el contrato a medias, y el modo de fallo está reproducido: con el
  /// pull request coincidente en la segunda página, el cliente no la pedía,
  /// seguía como si no existiera y creaba un SEGUNDO pull request — que es
  /// exactamente lo que esta búsqueda existe para impedir. Subir `per_page` a
  /// 100 no lo arregla: corre el borde, no lo cierra.
  ///
  /// **El presupuesto de red y la clasificación del código valen en CADA
  /// página**, no solo en la primera: cada página es un pedido entero, con su
  /// propia forma de colgarse y su propia forma de fallar.
  ///
  /// Lo que devuelve, y no es solo «lo que encontré»:
  ///
  /// - el desenlace del pull request que YA existe, si aparece;
  /// - un [PullRequestFailed] si alguna página falló, si el `Link` sale del
  ///   origen configurado, o si el tope de páginas se agota — los tres son
  ///   «la búsqueda no se pudo completar», y seguir hacia la creación con la
  ///   búsqueda incompleta es abrir el segundo pull request a ciegas;
  /// - `null` si las páginas se agotaron sin coincidencia, que es la única
  ///   forma de decir «no existe» con fundamento.
  Future<PublicationOutcome?> _buscarExistente(
    HttpClient cliente,
    PullRequestRequest request,
    Credential credencial,
  ) async {
    final marcador = marcadorEstable(request);
    var uri = _urlDePulls(
      query: {
        'head': '${configuracion.duenio}:${request.draft.branch}',
        'base': request.draft.base,
        'state': 'all',
        'per_page': '$_porPagina',
      },
    );

    for (var pagina = 1; pagina <= _maximoDePaginas; pagina++) {
      final pedido = await cliente.getUrl(uri);
      _autenticar(pedido, credencial);
      final respuesta = await pedido.close().timeout(_presupuestoDeRed);

      // **Clasificar ANTES de decodificar.** Un cuerpo de error no es una
      // lista, y tratar de convertirlo en una borra la única información que
      // sí dice qué pasó: el código.
      //
      // **Un `3xx` entra por acá y eso es deliberado.** Con
      // `followRedirects = false` —que pone [_autenticar]— la respuesta al
      // redirect llega tal cual en vez de seguirse, y para la búsqueda un
      // redirect es exactamente lo mismo que cualquier otra respuesta que no
      // sea `200`: no trae la página que se pidió, así que la búsqueda quedó
      // incompleta y `_causaDelCodigo` la deja en `desconocida`. Seguirlo
      // sería mandar el `Bearer` adonde diga el `Location`.
      if (respuesta.statusCode != HttpStatus.ok) {
        final causa = _causaDelCodigo(respuesta.statusCode);
        // El cuerpo se descarta, no se lee: libera la conexión sin que su
        // texto llegue a ninguna parte. **Con presupuesto, y tragándose su
        // vencimiento**: un cuerpo de error que no termina de llegar colgaría
        // la corrida igual que uno bueno, y una vez que el CÓDIGO clasificó,
        // que el cuerpo se haya terminado de descartar o no ya no cambia la
        // causa. Dejar que el vencimiento saliera por excepción convertiría
        // un `401` bien clasificado en un `red` del catch de arriba.
        await respuesta
            .drain<void>()
            .timeout(_presupuestoDeRed)
            .catchError((Object _) {});
        return PullRequestFailed(causa: causa);
      }

      // Abandona la lectura al vencer, y quien la SUELTA es el
      // `close(force: true)` del `finally` de [open] — ver ahí por qué el
      // mecanismo está en un solo lugar y qué prueba lo pincha.
      final cuerpo = await utf8.decoder
          .bind(respuesta)
          .join()
          .timeout(_presupuestoDeRed);
      final lista = jsonDecode(cuerpo) as List<Object?>;
      final encontrado = _coincidenciaEnLaPagina(lista, request, marcador);
      if (encontrado != null) return encontrado;

      final siguiente = _siguientePagina(respuesta, uri);
      if (siguiente == null) return null;
      if (!_mismoOrigen(siguiente, uri)) {
        // No se sigue, y no se calla: seguir mandaría el `Bearer` a un host
        // que eligió la respuesta; callar y devolver `null` diría «no hay
        // ningún PR» sobre una búsqueda que se cortó a la mitad.
        return PullRequestFailed(causa: CausaDePublicacion.desconocida);
      }
      uri = siguiente;
    }

    // El tope se agotó. Ver [_maximoDePaginas]: esto no es «hay demasiados»,
    // es «las páginas no se terminan», y la búsqueda quedó incompleta.
    return PullRequestFailed(causa: CausaDePublicacion.desconocida);
  }

  /// La coincidencia dentro de UNA página ya decodificada.
  PublicationOutcome? _coincidenciaEnLaPagina(
    List<Object?> lista,
    PullRequestRequest request,
    String marcador,
  ) {
    for (final item in lista) {
      final pr = item as Map<String, Object?>;
      final cabeza = pr['head'] as Map<String, Object?>?;
      // **Los dos lados de la comparación en la MISMA escritura.**
      // `request.revision` ya viene canonicalizado a minúsculas por
      // `PullRequestRequest` —ahí está escrito por qué la canonicalización
      // vive en la frontera del dominio—, y el `sha` que llega en esta
      // respuesta es un dato AJENO: la forja de hoy lo manda en minúsculas,
      // pero eso es su costumbre y no un contrato que este cliente pueda
      // exigir. Leerlo a la forma canónica es traducir una entrada ajena, no
      // una segunda representación nuestra; sin eso, un `sha` en mayúsculas
      // haría pasar por «no existe» al pull request que sí existe, y el
      // desenlace sería un SEGUNDO pull request.
      final sha = cabeza?['sha'];
      if (sha is! String || sha.toLowerCase() != request.revision) continue;
      final cuerpoDelPr = pr['body'] as String? ?? '';
      if (!cuerpoDelPr.contains(marcador)) continue;

      final url = pr['html_url']! as String;
      final estado = pr['state'] as String?;
      final fusionadoEl = pr['merged_at'];
      if (estado == 'open') {
        // Ya hay un PR abierto para esta misma revisión: no se empuja de
        // nuevo, se devuelve el que ya existe.
        return PullRequestOpen(url: url);
      }
      if (fusionadoEl != null) return PullRequestMerged(url: url);
      if (estado == 'closed') return PullRequestClosed(url: url);
    }
    return null;
  }

  Future<PublicationOutcome> _crearPr(
    HttpClient cliente,
    PullRequestRequest request,
    Credential credencial,
  ) async {
    final String cuerpoDeLaRespuesta;
    final int codigo;
    final ContentType? tipoDeContenido;
    try {
      final pedido = await cliente.postUrl(_urlDePulls());
      _autenticar(pedido, credencial);
      pedido.headers.contentType = ContentType.json;
      pedido.write(
        jsonEncode({
          'title': tituloDeGitHub(request),
          'head': request.draft.branch,
          'base': request.draft.base,
          'body': cuerpoDeGitHub(request),
        }),
      );
      final respuesta = await pedido.close().timeout(_presupuestoDeRed);
      codigo = respuesta.statusCode;
      tipoDeContenido = respuesta.headers.contentType;
      cuerpoDeLaRespuesta = await utf8.decoder
          .bind(respuesta)
          .join()
          .timeout(_presupuestoDeRed);
    } on Object {
      // Ni excepción, ni socket cortado, ni tiempo agotado —en cualquiera
      // de sus tres fases— dicen si el POST llegó a crear el PR del otro
      // lado. Un `TimeoutException` de `.timeout(...)` y un
      // `SocketException` del `connectionTimeout` de [cliente] caen los
      // dos en este mismo `catch`, igual que cualquier otra excepción de
      // red. Reportarlo como `failed` haría que quien reintenta abra un
      // segundo pull request; `unknown` es lo que lo manda de nuevo por la
      // búsqueda idempotente en vez de por una creación ciega.
      return PullRequestUnknown(causa: CausaDePublicacion.red);
    }

    if (codigo >= 300 && codigo < 400) {
      // **El redirect no se sigue —lo apaga [_autenticar]— y acá se declara
      // qué significa no haberlo seguido.** Va ANTES de mirar el
      // `Content-Type` porque un `3xx` no trae cuerpo JSON y caería en la
      // rama de abajo por el motivo equivocado: no es una respuesta ajena a
      // la forja, es la forja mandando a otra parte.
      //
      // Es `unknown` y no `failed` porque un `303 See Other` es la forma
      // documentada de contestar «lo creé, mirá allá»: el pull request pudo
      // quedar creado del otro lado. Reportarlo como fallo haría que quien
      // reintenta abriera un segundo pull request; `unknown` lo manda de
      // vuelta por la búsqueda idempotente.
      return PullRequestUnknown(causa: CausaDePublicacion.desconocida);
    }

    if (tipoDeContenido?.mimeType != 'application/json') {
      // **No es una defensa contra una conexión cortada a mitad de trama**:
      // eso ya termina en una excepción, y la atrapa el `catch` de arriba.
      // Esto es otra cosa: la forja real contesta este endpoint en JSON
      // tanto si crea el PR como si lo rechaza, así que una respuesta
      // sintácticamente completa que NO lo es no vino de GitHub tal como
      // este cliente lo conoce — es la página de un balanceador, de un
      // proxy o de un WAF intermedio, con SU PROPIO código de estado, que
      // puede coincidir por accidente con uno de los que sí clasificamos
      // (un `403` de un WAF no es un `403` de GitHub) y llevar a una causa
      // que no es la real. No hay código de estado ajeno a GitHub que este
      // cliente pueda clasificar con confianza, así que se declara
      // `unknown` en vez de inventar una causa sobre una respuesta que no
      // es la que se estaba esperando.
      return PullRequestUnknown(causa: CausaDePublicacion.red);
    }

    if (codigo == HttpStatus.created) {
      try {
        final data = jsonDecode(cuerpoDeLaRespuesta) as Map<String, Object?>;
        final url = data['html_url'] as String?;
        if (url == null || url.trim().isEmpty) {
          // 201 sin URL utilizable es una respuesta incompleta, no un
          // fallo: el servidor puede haber creado el PR igual.
          return PullRequestUnknown(causa: CausaDePublicacion.red);
        }
        return PullRequestOpen(url: url);
      } on Object {
        // No alcanza con `FormatException`: un `201` con `Content-Type:
        // application/json` y un cuerpo que es JSON válido pero de otra
        // forma —una lista, `null`, un `html_url` que no es texto— no
        // lanza `FormatException` al decodificar. `jsonDecode(...) as
        // Map<String, Object?>` y `data['html_url'] as String?` lanzan
        // `TypeError` en esos casos, y el puerto declara que `open` nunca
        // lanza por un fallo remoto. Es, además, exactamente la misma
        // incertidumbre que el brief pide tratar como `unknown`: un `201`
        // dice que el servidor creó algo, y su cuerpo no siendo el
        // esperado no vuelve falso ese `201`.
        return PullRequestUnknown(causa: CausaDePublicacion.red);
      }
    }
    // El cuerpo de la respuesta de error no se mira nunca: solo el código de
    // estado decide la causa, y por [_causaDelCodigo], que es el MISMO
    // clasificador que usa la búsqueda. Que los dos pedidos coincidan dejó de
    // ser una promesa de dos `switch` parecidos.
    return PullRequestFailed(causa: _causaDelCodigo(codigo));
  }
}
