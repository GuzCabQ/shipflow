/// Suite de contrato de `PullRequestSink`, contra las DOS implementaciones.
///
/// `docs/08` §2: *un fake solo es sustituto válido si cumple el mismo
/// contrato que el real. Sin eso se testea contra un fake que miente y la
/// suite queda verde por construcción.* Este archivo vive en `cli` —no en
/// `forge` ni en `plugin_fake`— porque es el único paquete que ve a las dos
/// implementaciones a la vez.
///
/// **Este archivo nombra a GitHub y a su forma de responder.** La regla
/// `forja-en-su-adapter` lo permite a propósito: su alcance excluye `test/`
/// porque una suite de contrato necesita poder fijar el comportamiento contra
/// la forma real del proveedor para poder decir que el adapter cumple lo que
/// promete — es la vara con la que se mide `forge`, no la fuga que la regla
/// caza.
///
/// LO QUE PRUEBA Y LO QUE NO
///     Prueba que las dos implementaciones respondan lo mismo ante las
///     mismas preguntas del puerto: que `open` nunca lanza, y que repetirlo
///     con la misma solicitud no crea un segundo pull request — incluido
///     cuando la primera respuesta fue ambigua (`unknown`), que es el caso
///     que de verdad separa una implementación correcta de una que confunde
///     «no sé si funcionó» con «funcionó» o con «falló». **No** prueba que
///     la real esté bien contra la API de GitHub de verdad — para eso está
///     `packages/forge/test/github_test.dart`, con su propio servidor local y
///     sus propias inyecciones de fallo — ni repite esas pruebas acá: lo que
///     se repite acá es solo lo que el PUERTO promete, no lo que un
///     proveedor concreto hace.
///
/// **Lo que NO se copió del brief**: la pregunta «un desenlace utilizable
/// siempre trae URL con contenido» no entró. `PublicacionUtilizable` la
/// exige en su propio constructor —lanza si `url` viene en blanco—, así que
/// ninguna de las dos implementaciones puede construir un desenlace
/// utilizable con URL vacía: la pregunta la responde el tipo, no la
/// implementación, y las dos la pasarían aunque una de las dos estuviera mal
/// escrita. En su lugar va el grupo de abajo, que sí puede fallar si una
/// implementación reintenta mal.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';

/// La revisión de esta suite. **Un OID completo de verdad —40 caracteres
/// hexadecimales, el largo de SHA-1 medido con `git rev-parse`—**, igual que
/// en `packages/forge/test/github_test.dart`: `PullRequestRequest` rechaza
/// cualquier otra cosa desde que una revisión vacía se reveló capaz de
/// convertirse en `:refs/heads/<rama>`, que borra la rama del remoto.
const revisionDePrueba = 'a4e66d50d152b67d451a9028fd1cf54c71e18e79';

void main() {
  // Los mismos valores que usa `packages/forge/test/github_test.dart`, para
  // que «la misma solicitud» signifique lo mismo en las dos suites.
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
    intent: 'probar el contrato de PullRequestSink',
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
      rutas: const ['a.txt'],
    ),
    revision: revisionDePrueba,
    arbolDeLaRevision: 'arbol-1',
  );

  // --- El servidor que sostiene a la implementación real -----------------
  //
  // Igual que en `github_test.dart`, salvo por `perderRespuestaDelPost`: acá
  // el PR SE CREA del lado del servidor —queda en `prsExistentes`, `creados`
  // ya lo cuenta— y lo que se pierde es solo la respuesta al cliente, vía
  // `detachSocket`. Es el caso que separa `unknown` de `failed`: si esta
  // suite solo pudiera simular «nada pasó», nunca podría exigir que un
  // reintento después de una respuesta perdida encuentre el PR que sí se
  // creó, en vez de abrir uno nuevo.
  late HttpServer api;
  late List<Map<String, Object?>> prsExistentes;
  var creados = 0;
  var perderRespuestaDelPost = false;

  setUp(() async {
    prsExistentes = [];
    creados = 0;
    perderRespuestaDelPost = false;
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
      final cuerpo = jsonDecode(await utf8.decoder.bind(p).join()) as Map;
      creados++;
      final nuevo = {
        'html_url': 'https://forja/pr/$creados',
        'state': 'open',
        'merged_at': null,
        'body': cuerpo['body'],
        'head': {'sha': revisionDePrueba},
      };
      prsExistentes.add(nuevo);
      if (perderRespuestaDelPost) {
        final socket = await p.response.detachSocket(writeHeaders: false);
        await socket.close();
        return;
      }
      p.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(nuevo));
      await p.response.close();
    });
  });

  tearDown(() => api.close(force: true));

  SalidaDePrDeGitHub sinkReal({
    Duration presupuestoDeRed = SalidaDePrDeGitHub.presupuestoDeRedPorDefecto,
  }) => SalidaDePrDeGitHub(
    configuracion: ConfiguracionDeGitHub(
      duenio: 'duenio',
      repositorio: 'repo',
      baseDeLaApi: Uri.parse('http://127.0.0.1:${api.port}'),
      urlDelRemoto: 'http://127.0.0.1:${api.port}/duenio/repo.git',
    ),
    // `FuenteDeCredencialFalsa`, no un stub privado: es el mismo
    // `CredentialSource` falso que esta tarea le suma a `plugin_fake`, y
    // usarlo acá lo ejercita contra el único consumidor que hoy lo
    // construye de verdad.
    credenciales: const FuenteDeCredencialFalsa(
      credenciales: {
        'SHIPFLOW_GITHUB_TOKEN': Credential(
          'ghp_x',
          label: 'SHIPFLOW_GITHUB_TOKEN',
        ),
      },
    ),
    // `true` sale con 0 sin tocar nada: esta suite prueba `PullRequestSink`,
    // no el `git push`, que ya tiene la suya bajo `packages/forge/test`.
    empuje: EmpujeAislado(
      directorio: Directory.systemTemp.path,
      entornoDelPadre: EntornoDelProceso(Platform.environment),
      programa: 'true',
    ),
    presupuestoDeRed: presupuestoDeRed,
  );

  // Las dos implementaciones, con nombre. Que sean dos no es un detalle: es
  // la condición para que esta suite signifique algo.
  final implementaciones = <String, PullRequestSink Function()>{
    'real · SalidaDePrDeGitHub contra un servidor local': sinkReal,
    'falsa · SalidaDePrFalsa configurada en abierto': () =>
        SalidaDePrFalsa(respuesta: PullRequestOpen(url: 'https://falsa/pr/1')),
  };

  test('la suite corre contra DOS implementaciones, no una', () {
    expect(implementaciones, hasLength(2));
    expect(
      implementaciones.keys.where((k) => k.startsWith('real')),
      hasLength(1),
      reason: 'sin la implementación real esto no prueba nada de GitHub',
    );
    expect(
      implementaciones.keys.where((k) => k.startsWith('falsa')),
      hasLength(1),
      reason: 'sin el fake no hay segundo punto de vista que contrastar',
    );
  });

  for (final entrada in implementaciones.entries) {
    group(entrada.key, () {
      late PullRequestSink sink;
      setUp(() => sink = entrada.value());

      test('open devuelve un desenlace tipado, nunca lanza', () async {
        expect(await sink.open(solicitud()), isA<PublicationOutcome>());
      });

      test(
        'repetir open con la misma solicitud no crea un segundo PR',
        () async {
          final a = await sink.open(solicitud());
          final b = await sink.open(solicitud());
          if (a is PublicacionUtilizable) {
            expect(b, isA<PublicacionUtilizable>());
            expect((b as PublicacionUtilizable).url, a.url);
          }
        },
      );
    });
  }

  group('el reintento tras un desenlace ambiguo no crea un segundo PR', () {
    // Esta es la pregunta que de verdad distingue una implementación
    // correcta de una que no lo es: las dos anteriores las pasa cualquier
    // fake trivial y cualquier real bien escrito con la misma facilidad. Acá
    // hace falta que la implementación efectivamente busque antes de crear.

    test('real: una respuesta perdida en la creación no impide que el '
        'reintento recupere el mismo PR', () async {
      perderRespuestaDelPost = true;
      final sink = sinkReal(presupuestoDeRed: const Duration(seconds: 2));

      final primero = await sink.open(solicitud());
      expect(
        primero,
        isA<PullRequestUnknown>(),
        reason:
            'la creación se hizo del lado del servidor; lo que se '
            'perdió fue la respuesta — eso es «no sé», no «falló»',
      );
      expect(primero.retryable, isTrue);
      expect(
        creados,
        1,
        reason: 'el servidor sí creó el PR antes de perder la respuesta',
      );

      perderRespuestaDelPost = false;
      final segundo = await sink.open(solicitud());
      expect(segundo, isA<PullRequestOpen>());
      expect(
        (segundo as PullRequestOpen).url,
        prsExistentes.single['html_url'],
      );
      expect(
        creados,
        1,
        reason:
            'el reintento tenía que ENCONTRAR el PR ya creado, no '
            'abrir uno segundo',
      );
    });

    test('falsa: configurada con un desenlace ambiguo, lo devuelve tal cual '
        'y no lo confunde con éxito', () async {
      final falsa = SalidaDePrFalsa(
        respuesta: PullRequestUnknown(causa: CausaDePublicacion.red),
      );
      final primero = await falsa.open(solicitud());
      final segundo = await falsa.open(solicitud());
      expect(primero, isA<PullRequestUnknown>());
      expect(segundo, isA<PullRequestUnknown>());
      expect(
        falsa.recibidas,
        hasLength(2),
        reason:
            'el reintento sí volvió a llamar a open; lo que no hizo '
            'es fingir que la segunda vez salió bien',
      );
    });
  });
}
