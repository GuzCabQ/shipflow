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
        'head': {'sha': 'commit-1'},
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
  // solicitud», bajo `packages/core/test`: `runId: 'corrida-1'`,
  // `revision: 'commit-1'`, y `arbolDeLaRevision` igual al
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
    revision: 'commit-1',
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
          'revision=commit-1 -->',
      'head': {'sha': 'commit-1'},
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

  test('un PR fusionado devuelve URL; uno cerrado da incompleto no '
      'reintentable', () async {
    prsExistentes.add({
      'html_url': 'https://forja/pr/7',
      'state': 'closed',
      'merged_at': '2026-09-14T00:00:00Z',
      'body': marcadorEsperado(),
      'head': {'sha': 'commit-1'},
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
      'head': {'sha': 'commit-1'},
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
