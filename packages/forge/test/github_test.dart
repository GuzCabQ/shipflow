import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

/// El secreto que esta suite le da a la salida. Es una constante y no un
/// literal repetido para que la aserción sobre el encabezado pueda exigir
/// ESTE secreto y no una cadena cualquiera: con `_autenticar` reemplazado por
/// un `Bearer` de relleno, la prueba tiene que ponerse roja.
const secretoDePrueba = 'ghp_x';

/// La revisión que esta suite publica. **Es un OID completo de verdad —40
/// caracteres hexadecimales, el largo de SHA-1 medido con `git rev-parse`— y
/// no una cadena con forma de nombre**: desde esta ronda
/// `PullRequestRequest` rechaza cualquier cosa que no sea un OID completo,
/// porque una revisión vacía termina en el refspec `:refs/heads/<rama>`, que
/// BORRA la rama del remoto.
const revisionDePrueba = 'a4e66d50d152b67d451a9028fd1cf54c71e18e79';

void main() {
  late HttpServer api;
  late List<Map<String, Object?>> prsExistentes;
  int creados = 0;
  bool cortarLaRespuestaDelPost = false;

  /// Lo que el servidor VIO llegar, pedido por pedido: el método y el
  /// encabezado `Authorization` tal cual. Sin esto, la única parte del
  /// camino de la credencial que llega hasta la forja —el encabezado que
  /// arma `_autenticar`— no la mira nadie: borrar esa llamada dejaba la
  /// suite entera en verde, y el modo de fallo en producción es
  /// TRANQUILIZADOR (la forja contesta 401 y eso se traduce a «la credencial
  /// no fue aceptada», o sea que un bug nuestro se le reporta al usuario
  /// como un problema de su token).
  final pedidosVistos = <({String metodo, String? autorizacion})>[];

  setUp(() async {
    prsExistentes = [];
    creados = 0;
    cortarLaRespuestaDelPost = false;
    pedidosVistos.clear();
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((p) async {
      pedidosVistos.add((
        metodo: p.method,
        autorizacion: p.headers.value(HttpHeaders.authorizationHeader),
      ));
      if (p.method == 'GET') {
        p.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(prsExistentes));
        await p.response.close();
        return;
      }
      if (cortarLaRespuestaDelPost) {
        await p.response.close();
        await api.close(force: true);
        return;
      }
      creados++;
      final cuerpo = jsonDecode(await utf8.decoder.bind(p).join()) as Map;
      prsExistentes.add({
        'html_url': 'https://forja/pr/$creados',
        'state': 'open',
        'merged_at': null,
        'body': cuerpo['body'],
        'head': {'sha': revisionDePrueba},
      });
      p.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(prsExistentes.last));
      await p.response.close();
    });
  });

  tearDown(() async => api.close(force: true));

  // Los mismos valores que la tarea 5 usa en su suite «el borrador y la
  // solicitud», bajo `packages/core/test`: `runId: 'corrida-1'`, un OID
  // completo como revisión, y `arbolDeLaRevision` igual al
  // `candidato.contentRevision` del artefacto.
  ArtefactoDeRevision artefacto() => ArtefactoDeRevision(
    superficie: SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: const [],
      estado: EstadoDeCorrida.verde,
    ),
    candidato: CandidateIdentity(
      contentRevision: 'arbol-1',
      baseRevision: 'base-1',
    ),
    intent: 'probar la salida de GitHub',
    plan: null,
    sinPlanPorque: 'no hay elementos de trabajo',
    alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
  );

  PullRequestRequest solicitud() => PullRequestRequest(
    draft: PullRequestDraft(
      runId: 'corrida-1',
      branch: 'rama-1',
      base: 'main',
      artefacto: artefacto(),
    ),
    revision: revisionDePrueba,
    arbolDeLaRevision: 'arbol-1',
  );

  String marcadorEsperado() => marcadorEstable(solicitud());

  SalidaDePrDeGitHub construirSalida(
    int puerto, {
    Duration presupuestoDeRed = SalidaDePrDeGitHub.presupuestoDeRedPorDefecto,
    Uri? baseDeLaApi,
    CredentialSource? credenciales,
  }) => SalidaDePrDeGitHub(
    configuracion: ConfiguracionDeGitHub(
      duenio: 'duenio',
      repositorio: 'repo',
      baseDeLaApi: baseDeLaApi ?? Uri.parse('http://127.0.0.1:$puerto'),
      urlDelRemoto: 'http://127.0.0.1:$puerto/duenio/repo.git',
    ),
    credenciales:
        credenciales ??
        _CredencialFija(
          const Credential(secretoDePrueba, label: 'SHIPFLOW_GITHUB_TOKEN'),
        ),
    // `true` sale con 0 sin hacer nada: esta suite prueba la API, no el
    // push, y el push ya tiene su propia suite bajo este mismo directorio.
    // Se resuelve por `PATH` —no por una ruta absoluta— porque esa ruta
    // difiere entre macOS (`/usr/bin/true`) y Linux (`/bin/true`), y
    // `Process.run` ya sabe resolver un nombre sin separadores contra el
    // `PATH` que le llega.
    empuje: EmpujeAislado(
      directorio: Directory.systemTemp.path,
      entornoDelPadre: EntornoDelProceso(Platform.environment),
      programa: 'true',
    ),
    presupuestoDeRed: presupuestoDeRed,
  );

  test('open repetido no crea un segundo PR', () async {
    final salida = construirSalida(api.port);
    final primero = await salida.open(solicitud());
    final segundo = await salida.open(solicitud());
    expect(primero, isA<PullRequestOpen>());
    expect(segundo, isA<PullRequestOpen>());
    expect((primero as PullRequestOpen).url, (segundo as PullRequestOpen).url);
    expect(creados, 1);
  });

  test('un PR con la misma rama pero otra revisión NO se reutiliza', () async {
    prsExistentes.add({
      'html_url': 'https://forja/pr/ajeno',
      'state': 'open',
      'merged_at': null,
      'body': '<!-- shipflow:pr formatVersion=1 runId=otra revision=OTRA -->',
      'head': {'sha': 'OTRA'},
    });
    final salida = construirSalida(api.port);
    final r = await salida.open(solicitud());
    expect(creados, 1, reason: 'rama y base no alcanzan como clave');
    expect((r as PullRequestOpen).url, isNot(contains('ajeno')));
  });

  test('un PR con la misma revisión pero el marcador equivocado NO se '
      'reutiliza', () async {
    // El `sha` coincide con la revisión esperada — a propósito. Si el
    // filtro del marcador se rompiera y el de `sha` quedara intacto, esta
    // es la única prueba que lo notaría: la anterior descarta su PR
    // ajeno por `sha`, así que nunca llega a evaluar el marcador.
    prsExistentes.add({
      'html_url': 'https://forja/pr/ajeno-por-marcador',
      'state': 'open',
      'merged_at': null,
      'body':
          '<!-- shipflow:pr formatVersion=1 runId=otra '
          'revision=$revisionDePrueba -->',
      'head': {'sha': revisionDePrueba},
    });
    final salida = construirSalida(api.port);
    final r = await salida.open(solicitud());
    expect(
      creados,
      1,
      reason: 'el sha coincide, pero el marcador no: no alcanza como clave',
    );
    expect((r as PullRequestOpen).url, isNot(contains('ajeno-por-marcador')));
  });

  test('una respuesta perdida produce unknown, no failed', () async {
    cortarLaRespuestaDelPost = true;
    final salida = construirSalida(api.port);
    final r = await salida.open(solicitud());
    expect(r, isA<PullRequestUnknown>());
    expect(r.retryable, isTrue);
  });

  test(
    'un POST que nunca contesta produce unknown, y no cuelga la corrida',
    () async {
      // Un servidor propio: acepta la conexión —a diferencia de un puerto
      // cerrado, que es la prueba de red que ya tiene la suite de empuje en
      // este mismo directorio— y para el `POST` simplemente no contesta
      // nunca. Sin un presupuesto
      // de tiempo, el `await` de `open` quedaría esperando para siempre.
      final servidorQueCuelga = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      servidorQueCuelga.listen((p) async {
        if (p.method == 'GET') {
          p.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(const <Object?>[]));
          await p.response.close();
        }
        // Un `POST` no recibe respuesta: ni se cierra ni se escribe nada.
      });
      addTearDown(() => servidorQueCuelga.close(force: true));

      final salida = construirSalida(
        servidorQueCuelga.port,
        presupuestoDeRed: const Duration(milliseconds: 200),
      );
      final r = await salida.open(solicitud());
      expect(r, isA<PullRequestUnknown>());
      expect(r.retryable, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test('un 201 con un cuerpo de otra forma no lanza: da unknown', () async {
    // JSON válido pero de otra forma —una lista, un `html_url` que no es
    // texto— no lanza `FormatException` al decodificar: `jsonDecode(...)
    // as Map<String, Object?>` y `data['html_url'] as String?` lanzan
    // `TypeError`. El puerto `PullRequestSink` declara que `open` nunca
    // lanza por un fallo remoto, así que esto tiene que dar un desenlace,
    // no una excepción que se escape.
    final servidorRaro = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var cuerpoDelPost = jsonEncode(const <Object?>[]);
    servidorRaro.listen((p) async {
      if (p.method == 'GET') {
        p.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(const <Object?>[]));
        await p.response.close();
        return;
      }
      await utf8.decoder.bind(p).join();
      p.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..write(cuerpoDelPost);
      await p.response.close();
    });
    addTearDown(() => servidorRaro.close(force: true));

    final salida = construirSalida(servidorRaro.port);

    cuerpoDelPost = jsonEncode(const <Object?>[]);
    expect(await salida.open(solicitud()), isA<PullRequestUnknown>());

    cuerpoDelPost = jsonEncode({'html_url': 42});
    expect(await salida.open(solicitud()), isA<PullRequestUnknown>());
  });

  test('cada pedido a la forja lleva la credencial en el encabezado '
      'Authorization', () async {
    // La mutación que esta prueba existe para romper es BORRAR la llamada a
    // `_autenticar` —cualquiera de las dos—. Sin ella la suite entera seguía
    // en 858/858: ningún servidor de prueba leía los encabezados, así que el
    // único tramo del camino de la credencial que llega hasta la forja no lo
    // sostenía nada, mientras el doc comment de `_autenticar` prometía que
    // «nunca la interpola fuera de `Credential.use`».
    final salida = construirSalida(api.port);
    expect(await salida.open(solicitud()), isA<PullRequestOpen>());

    expect(
      pedidosVistos.map((p) => p.metodo),
      containsAll(<String>['GET', 'POST']),
      reason:
          'esta prueba solo cubre las dos llamadas a `_autenticar` si los '
          'dos pedidos llegaron de verdad',
    );
    for (final p in pedidosVistos) {
      expect(
        p.autorizacion,
        'Bearer $secretoDePrueba',
        reason:
            'el pedido ${p.metodo} llegó sin el encabezado con el secreto '
            'que corresponde. Sin él la forja contesta 401 y el desenlace '
            'dice «la credencial no fue aceptada»: un bug nuestro '
            'reportado como un problema del token del usuario.',
      );
    }
  });

  test('sin credencial no se toca la red, y es PushFailed y no '
      'PullRequestFailed', () async {
    // El README hace un punto explícito de esta distinción —«nada remoto
    // ocurrió en absoluto»— y hasta ahora nadie la probaba: cambiar la rama
    // a `PullRequestFailed` no rompía nada.
    final salida = construirSalida(api.port, credenciales: _SinCredencial());
    final r = await salida.open(solicitud());

    expect(r, isA<PushFailed>());
    expect((r as PushFailed).causa, CausaDePublicacion.autenticacion);
    expect(
      pedidosVistos,
      isEmpty,
      reason: 'sin credencial no se toca la red: no hay con qué autenticar',
    );
    expect(creados, 0);
  });

  test('una base de la API que no es https se rechaza antes de mandar el '
      'Bearer', () async {
    // `_autenticar` pone `Bearer <token>` sin mirar el esquema: con `http://`
    // contra un host que no es loopback el token viaja legible. Nadie
    // produce hoy esa URL —la raíz de composición es de la rebanada de
    // `ship`— y por eso ninguna revisión por tarea lo vio.
    final salida = construirSalida(
      api.port,
      baseDeLaApi: Uri.parse('http://api.forja.invalido'),
    );
    final r = await salida.open(solicitud());

    expect(r, isA<PushFailed>());
    expect((r as PushFailed).causa, CausaDePublicacion.configuracionInsegura);
    expect(r.retryable, isFalse, reason: 'el mismo canal falla igual mañana');
    expect(r.nextAction, AccionSiguiente.corregirConfiguracion);
    expect(
      r.safeReason,
      isNot(contains('forja.invalido')),
      reason: 'la URL rechazada es la que iba a llevar el secreto adjunto',
    );
    expect(pedidosVistos, isEmpty);
    expect(creados, 0);
  });

  test('una base de la API https NO se rechaza: la validación mira el '
      'esquema, no rechaza todo', () {
    // El control negativo de la anterior. Sin esto, una validación que
    // devolviera `false` siempre pasaría la prueba de arriba y rompería la
    // publicación entera sin que nada lo notara — salvo por las pruebas de
    // loopback, que son la excepción declarada y no el caso de producción.
    expect(
      esCanalSeguroParaLaCredencial('https://api.github.com'),
      isTrue,
      reason: 'https es el canal que la validación existe para exigir',
    );
    expect(esCanalSeguroParaLaCredencial('http://api.forja.invalido'), isFalse);
    // La excepción declarada en el doc comment de la función, probada como
    // tal y no dada por sentada.
    expect(esCanalSeguroParaLaCredencial('http://127.0.0.1:8080/x'), isTrue);
    expect(esCanalSeguroParaLaCredencial('http://[::1]:8080/x'), isTrue);
    expect(esCanalSeguroParaLaCredencial('http://localhost:8080/x'), isTrue);
    // Ni un remoto de SSH ni una cadena que no parsea pasan por seguros.
    expect(esCanalSeguroParaLaCredencial('ssh://git@forja/x.git'), isFalse);
    expect(esCanalSeguroParaLaCredencial('git@forja:duenio/x.git'), isFalse);
    expect(esCanalSeguroParaLaCredencial('http://[no es una url'), isFalse);
  });

  group('la respuesta del GET se clasifica antes de decodificarla', () {
    // El defecto que este grupo fija: `_buscarExistente` no miraba el código
    // de estado y le pasaba CUALQUIER cuerpo a `jsonDecode(...) as
    // List<Object?>`. Un `401` de la forja trae un OBJETO, el cast tiraba
    // `TypeError`, y el `catch` exterior de `open` lo convertía en
    // `PullRequestFailed(red)`: «la red falló» sobre una credencial
    // rechazada. Reproducido por el autor — se esperaba `autenticacion` y
    // salía `red`.
    //
    // Y había un segundo efecto, peor porque es invisible: como la corrida
    // se detenía en el GET, la clasificación del `401` del POST no la
    // alcanzaba ninguna corrida. Estaba escrita y no la ejercía nadie.

    /// Un servidor que contesta el GET con [codigo] y [cuerpo], y cuenta los
    /// POST que recibe. Lo que importa medir es que el POST NO llegue: un
    /// fallo de la búsqueda no puede terminar creando un pull request.
    Future<({HttpServer servidor, List<String> metodos})> forjaQueContesta(
      int codigo,
      String cuerpo, {
      ContentType? tipo,
    }) async {
      final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final metodos = <String>[];
      servidor.listen((p) async {
        metodos.add(p.method);
        p.response.statusCode = codigo;
        if (tipo != null) p.response.headers.contentType = tipo;
        p.response.write(cuerpo);
        await p.response.close();
      });
      addTearDown(() => servidor.close(force: true));
      return (servidor: servidor, metodos: metodos);
    }

    // El cuerpo real de esta forja para un `401`: un OBJETO, no una lista.
    // Es el dato que hacía fallar el cast.
    const cuerpoDe401 =
        '{"message":"Bad credentials",'
        '"documentation_url":"https://docs.github.com/rest"}';

    final casos =
        <String, ({int codigo, String cuerpo, CausaDePublicacion causa})>{
          'un 401 es autenticación, no red': (
            codigo: HttpStatus.unauthorized,
            cuerpo: cuerpoDe401,
            causa: CausaDePublicacion.autenticacion,
          ),
          'un 403 es permisos, igual que en la creación': (
            codigo: HttpStatus.forbidden,
            cuerpo:
                '{"message":"Resource not accessible by personal access token"}',
            causa: CausaDePublicacion.permisos,
          ),
          'un error del servidor no se disfraza de causa conocida': (
            codigo: HttpStatus.internalServerError,
            cuerpo: '{"message":"Server Error"}',
            causa: CausaDePublicacion.desconocida,
          ),
        };

    for (final caso in casos.entries) {
      test(caso.key, () async {
        final forja = await forjaQueContesta(
          caso.value.codigo,
          caso.value.cuerpo,
          tipo: ContentType.json,
        );
        final r = await construirSalida(forja.servidor.port).open(solicitud());

        expect(r, isA<PullRequestFailed>());
        expect(
          (r as PullRequestFailed).causa,
          caso.value.causa,
          reason:
              'el GET contestó ${caso.value.codigo} y el desenlace dice '
              '«${r.safeReason}». Sin mirar el código, cualquiera de estos '
              'termina en `red` porque el cuerpo no es una lista.',
        );
        expect(
          forja.metodos,
          isNot(contains('POST')),
          reason:
              'la búsqueda falló: seguir hasta el POST crearía un pull '
              'request sin haber podido comprobar si ya existía uno',
        );
      });
    }

    test('un 200 con un cuerpo que no es una lista es un fallo de red, no una '
        'búsqueda vacía', () async {
      // El control que separa «clasifiqué el código» de «entendí la
      // respuesta». Un `200` cuyo cuerpo no es una lista —la página de un
      // proxy, un objeto de error de un intermediario— no puede leerse como
      // «no hay ningún PR»: eso mandaría a crear uno sin haber buscado.
      final forja = await forjaQueContesta(
        HttpStatus.ok,
        '{"message":"esto no es una lista"}',
        tipo: ContentType.json,
      );
      final r = await construirSalida(forja.servidor.port).open(solicitud());

      expect(r, isA<PullRequestFailed>());
      expect((r as PullRequestFailed).causa, CausaDePublicacion.red);
      expect(r.retryable, isTrue);
      expect(
        forja.metodos,
        isNot(contains('POST')),
        reason: 'no se pudo buscar: no se puede crear',
      );
    });

    test('un 200 con una lista SÍ se decodifica: la clasificación no rechaza '
        'todo', () async {
      // El control positivo del grupo. Sin él, un `_buscarExistente` que
      // devolviera un fallo ante CUALQUIER respuesta pasaría las cuatro
      // pruebas de arriba y rompería la publicación entera.
      final salida = construirSalida(api.port);
      expect(await salida.open(solicitud()), isA<PullRequestOpen>());
      expect(creados, 1);
    });
  });

  group('la búsqueda idempotente recorre TODAS las páginas', () {
    /// Una forja que pagina: [paginas] es lo que devuelve cada página, en
    /// orden, y cada una menos la última anuncia la siguiente por `Link`.
    ///
    /// **Anunciar por `Link` y no por conteo** es lo que hace la forja de
    /// verdad, y es lo único que un cliente puede seguir sin adivinar.
    Future<({HttpServer servidor, List<String> rutas, int Function() creados})>
    forjaPaginada(List<List<Map<String, Object?>>> paginas) async {
      final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final rutas = <String>[];
      var creados = 0;
      servidor.listen((p) async {
        if (p.method == 'GET') {
          rutas.add(p.uri.toString());
          final numero =
              int.tryParse(p.uri.queryParameters['page'] ?? '1') ?? 1;
          final indice = numero - 1;
          final pagina = indice < paginas.length
              ? paginas[indice]
              : const <Map<String, Object?>>[];
          if (indice + 1 < paginas.length) {
            final siguiente = p.uri.replace(
              queryParameters: {
                ...p.uri.queryParameters,
                'page': '${numero + 1}',
              },
            );
            p.response.headers.add(
              'link',
              '<http://127.0.0.1:${servidor.port}${siguiente.path}'
                  '?${siguiente.query}>; rel="next", '
                  '<http://127.0.0.1:${servidor.port}${siguiente.path}'
                  '?${siguiente.query}>; rel="last"',
            );
          }
          p.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(pagina));
          await p.response.close();
          return;
        }
        creados++;
        await utf8.decoder.bind(p).join();
        p.response
          ..statusCode = 201
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'html_url': 'https://forja/pr/nuevo'}));
        await p.response.close();
      });
      addTearDown(() => servidor.close(force: true));
      return (servidor: servidor, rutas: rutas, creados: () => creados);
    }

    Map<String, Object?> prCoincidente() => {
      'html_url': 'https://forja/pr/el-que-ya-existe',
      'state': 'open',
      'merged_at': null,
      'body': marcadorEsperado(),
      'head': {'sha': revisionDePrueba},
    };

    Map<String, Object?> prAjeno(int n) => {
      'html_url': 'https://forja/pr/ajeno-$n',
      'state': 'open',
      'merged_at': null,
      'body': '<!-- shipflow:pr formatVersion=1 runId=otra revision=OTRA -->',
      'head': {'sha': 'OTRA'},
    };

    test(
      'el PR que coincide está en la SEGUNDA página, y se encuentra',
      () async {
        // Reproducido por el autor con un servidor local: con una sola
        // petición, el cliente no veía esta página, seguía como si el pull
        // request no existiera y llegaba al POST — o sea que creaba un
        // segundo pull request, que es exactamente lo que la búsqueda
        // idempotente existe para impedir.
        final forja = await forjaPaginada([
          [prAjeno(1), prAjeno(2)],
          [prAjeno(3), prCoincidente()],
        ]);

        final r = await construirSalida(forja.servidor.port).open(solicitud());

        expect(r, isA<PullRequestOpen>());
        expect((r as PullRequestOpen).url, 'https://forja/pr/el-que-ya-existe');
        expect(
          forja.creados(),
          0,
          reason:
              'se creó un segundo pull request para una revisión que ya tenía '
              'uno: la búsqueda se quedó en la primera página',
        );
        expect(
          forja.rutas,
          hasLength(2),
          reason: 'la segunda página nunca se pidió',
        );
        expect(
          forja.rutas.first,
          contains('per_page=100'),
          reason:
              'sin `per_page` la forja devuelve 30 por página: más páginas y '
              'más pedidos para la misma respuesta',
        );
      },
    );

    test('sin `rel="next"` no se piden páginas de más', () async {
      // El control negativo: una implementación que siguiera pidiendo
      // páginas hasta el tope gastaría diez pedidos por cada búsqueda y
      // pasaría igual la prueba de arriba.
      final forja = await forjaPaginada([
        [prAjeno(1)],
      ]);
      await construirSalida(forja.servidor.port).open(solicitud());
      expect(forja.rutas, hasLength(1));
    });

    /// Un servidor que contesta bien la PRIMERA página —con su `Link` a la
    /// segunda— y le da a la segunda el tratamiento que diga [segunda].
    ///
    /// Existe porque «el presupuesto y la clasificación valen en CADA página»
    /// era, hasta acá, una propiedad que solo sostenía la lectura del código:
    /// todas las pruebas de fallo atacaban la PRIMERA página, así que un
    /// `if (pagina == 1 && ...)` alrededor de la clasificación —o un
    /// `.timeout` puesto solo en la primera— pasaba la suite entera en verde.
    Future<({HttpServer servidor, List<String> metodos})> forjaConSegundaPagina(
      Future<void> Function(HttpRequest pedido) segunda,
    ) async {
      final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final metodos = <String>[];
      servidor.listen((p) async {
        metodos.add(p.method);
        if (p.method != 'GET') {
          await utf8.decoder.bind(p).join();
          p.response
            ..statusCode = 201
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'html_url': 'https://forja/pr/nuevo'}));
          await p.response.close();
          return;
        }
        if (p.uri.queryParameters['page'] == '2') {
          await segunda(p);
          return;
        }
        p.response.headers.add(
          'link',
          '<http://127.0.0.1:${servidor.port}/repos/duenio/repo/pulls'
              '?page=2>; rel="next"',
        );
        p.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(const <Object?>[]));
        await p.response.close();
      });
      addTearDown(() => servidor.close(force: true));
      return (servidor: servidor, metodos: metodos);
    }

    test('la SEGUNDA página que contesta 401 se clasifica igual que la '
        'primera', () async {
      final forja = await forjaConSegundaPagina((p) async {
        p.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write('{"message":"Bad credentials"}');
        await p.response.close();
      });

      final r = await construirSalida(forja.servidor.port).open(solicitud());

      expect(r, isA<PullRequestFailed>());
      expect(
        (r as PullRequestFailed).causa,
        CausaDePublicacion.autenticacion,
        reason:
            'la clasificación tiene que valer en CADA página. Aplicada solo '
            'a la primera, el cuerpo de error de la segunda vuelve a fallar '
            'en el cast y el desenlace vuelve a ser `red`.',
      );
      expect(
        forja.metodos,
        isNot(contains('POST')),
        reason: 'la búsqueda no se pudo completar: crear sería a ciegas',
      );
    });

    test(
      'la SEGUNDA página que no contesta vence, y no cuelga la corrida',
      () async {
        // El pedido de la segunda página queda sin respuesta: ni se cierra ni
        // se escribe nada. Sin el presupuesto aplicado a ESTA página, `open`
        // espera para siempre.
        final forja = await forjaConSegundaPagina((p) async {});

        final r = await construirSalida(
          forja.servidor.port,
          presupuestoDeRed: const Duration(milliseconds: 200),
        ).open(solicitud());

        expect(r, isA<PullRequestFailed>());
        expect(
          (r as PullRequestFailed).causa,
          CausaDePublicacion.red,
          reason: 'un pedido que no contesta a tiempo es un fallo de red',
        );
        expect(r.retryable, isTrue);
        expect(forja.metodos, isNot(contains('POST')));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('un `Link` que cicla no gira para siempre: se corta y se declara '
        'fallo', () async {
      // Un `Link` que apunta siempre a la misma página —un proxy roto, un
      // bug de paginación, una respuesta hostil— es el cuelgue que el
      // presupuesto POR PEDIDO no cubre: cada pedido contesta a tiempo y el
      // bucle no termina nunca. El tope existe por eso, y agotarlo NO es
      // «no encontré nada»: es «no pude terminar de buscar», que no
      // autoriza a crear.
      final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final vistos = <String>[];
      var creados = 0;
      servidor.listen((p) async {
        if (p.method != 'GET') {
          creados++;
          await utf8.decoder.bind(p).join();
          p.response
            ..statusCode = 201
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'html_url': 'https://forja/pr/nuevo'}));
          await p.response.close();
          return;
        }
        vistos.add(p.uri.toString());
        p.response.headers.add(
          'link',
          '<http://127.0.0.1:${servidor.port}/repos/duenio/repo/pulls'
              '?page=ciclo>; rel="next"',
        );
        p.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(const <Object?>[]));
        await p.response.close();
      });
      addTearDown(() => servidor.close(force: true));

      final r = await construirSalida(servidor.port).open(solicitud());

      expect(r, isA<PullRequestFailed>());
      expect((r as PullRequestFailed).causa, CausaDePublicacion.desconocida);
      expect(
        vistos.length,
        lessThanOrEqualTo(10),
        reason: 'el recorrido tiene que tener un tope declarado',
      );
      expect(
        creados,
        0,
        reason:
            'la búsqueda no terminó: crear acá es abrir un segundo pull '
            'request a ciegas',
      );
    });

    test('un `Link` a otro origen no se sigue: la credencial no viaja adonde '
        'diga la respuesta', () async {
      // Cada página se pide con el `Authorization` puesto. Seguir un `Link`
      // a otro host mandaría el token a un destino que eligió la respuesta y
      // no la configuración — y `open` valida el canal UNA vez, sobre
      // `baseDeLaApi`, precisamente porque hasta esta ronda todas las URLs
      // salían de ahí.
      final ajeno = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final autorizacionesAjenas = <String?>[];
      ajeno.listen((p) async {
        autorizacionesAjenas.add(
          p.headers.value(HttpHeaders.authorizationHeader),
        );
        p.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(const <Object?>[]));
        await p.response.close();
      });
      addTearDown(() => ajeno.close(force: true));

      final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var creados = 0;
      servidor.listen((p) async {
        if (p.method != 'GET') {
          creados++;
          await utf8.decoder.bind(p).join();
          p.response
            ..statusCode = 201
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'html_url': 'https://forja/pr/nuevo'}));
          await p.response.close();
          return;
        }
        p.response.headers.add(
          'link',
          '<http://127.0.0.1:${ajeno.port}/repos/duenio/repo/pulls?page=2>; '
              'rel="next"',
        );
        p.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(const <Object?>[]));
        await p.response.close();
      });
      addTearDown(() => servidor.close(force: true));

      final r = await construirSalida(servidor.port).open(solicitud());

      expect(
        autorizacionesAjenas,
        isEmpty,
        reason: 'el `Bearer` llegó a un host que eligió la respuesta',
      );
      expect(r, isA<PullRequestFailed>());
      expect(creados, 0, reason: 'la búsqueda quedó incompleta');
    });
  });

  test('un PR fusionado devuelve URL; uno cerrado da incompleto no '
      'reintentable', () async {
    prsExistentes.add({
      'html_url': 'https://forja/pr/7',
      'state': 'closed',
      'merged_at': '2026-09-14T00:00:00Z',
      'body': marcadorEsperado(),
      'head': {'sha': revisionDePrueba},
    });
    expect(
      await construirSalida(api.port).open(solicitud()),
      isA<PullRequestMerged>(),
    );

    prsExistentes.clear();
    prsExistentes.add({
      'html_url': 'https://forja/pr/8',
      'state': 'closed',
      'merged_at': null,
      'body': marcadorEsperado(),
      'head': {'sha': revisionDePrueba},
    });
    final cerrado = await construirSalida(api.port).open(solicitud());
    expect(cerrado, isA<PullRequestClosed>());
    expect(cerrado.retryable, isFalse);
    expect(cerrado.nextAction, AccionSiguiente.entregaNuevaExplicita);
  });
}

/// Una `CredentialSource` que siempre entrega la misma credencial. Esta suite
/// prueba la API de GitHub y la búsqueda idempotente, no la fuente de
/// credenciales — eso lo prueba la suite de credenciales bajo
/// `packages/cli/test`.
class _CredencialFija implements CredentialSource {
  final Credential _credencial;

  const _CredencialFija(this._credencial);

  @override
  Future<Credential?> read(String key) async => _credencial;
}

/// Una `CredentialSource` que no tiene la clave. Es lo que devuelve
/// `FuenteDeEntorno` cuando la variable no está en el entorno.
class _SinCredencial implements CredentialSource {
  @override
  Future<Credential?> read(String key) async => null;
}
