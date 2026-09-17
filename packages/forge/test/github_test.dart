import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer api;
  late List<Map<String, Object?>> prsExistentes;
  int creados = 0;
  bool cortarLaRespuestaDelPost = false;

  setUp(() async {
    prsExistentes = [];
    creados = 0;
    cortarLaRespuestaDelPost = false;
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((p) async {
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
  }) => SalidaDePrDeGitHub(
    configuracion: ConfiguracionDeGitHub(
      duenio: 'duenio',
      repositorio: 'repo',
      baseDeLaApi: Uri.parse('http://127.0.0.1:$puerto'),
      urlDelRemoto: 'http://127.0.0.1:$puerto/duenio/repo.git',
    ),
    credenciales: _CredencialFija(
      const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
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
