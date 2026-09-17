import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer api;
  late List<String> pedidos;
  late List<Map<String, Object?>> prsExistentes;
  int creados = 0;
  bool cortarLaRespuestaDelPost = false;

  setUp(() async {
    pedidos = [];
    prsExistentes = [];
    creados = 0;
    cortarLaRespuestaDelPost = false;
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((p) async {
      pedidos.add('${p.method} ${p.uri.path}?${p.uri.query}');
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

  SalidaDePrDeGitHub construirSalida(int puerto) => SalidaDePrDeGitHub(
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
    // Se resuelve por
    // `PATH` —no por una ruta absoluta— porque esa ruta difiere entre macOS
    // (`/usr/bin/true`) y Linux (`/bin/true`), y `Process.run` ya sabe
    // resolver un nombre sin separadores contra el `PATH` que le llega.
    empuje: EmpujeAislado(
      directorio: Directory.systemTemp.path,
      entornoDelPadre: EntornoDelProceso(Platform.environment),
      programa: 'true',
    ),
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

  test('una respuesta perdida produce unknown, no failed', () async {
    cortarLaRespuestaDelPost = true;
    final salida = construirSalida(api.port);
    final r = await salida.open(solicitud());
    expect(r, isA<PullRequestUnknown>());
    expect(r.retryable, isTrue);
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
