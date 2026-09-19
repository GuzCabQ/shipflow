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

import 'apoyo.dart';

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
  // El repositorio, la rama y la base que `solicitud` va a usar. **Escritos
  // una vez**: la partición del servidor y la siembra de las pruebas tienen
  // que hablar de la misma consulta, y dos copias divergen.
  const duenio = 'duenio';
  const repositorio = 'repo';
  const rama = 'rama-1';
  const base = 'main';
  final claveDeLaSolicitud = claveDeLaConsultaDePrs(
    ruta: '/repos/$duenio/$repositorio/pulls',
    head: '$duenio:$rama',
    base: base,
  );

  late HttpServer api;

  // Los pull requests que existen del otro lado, POR REPOSITORIO, RAMA Y
  // BASE — ver `claveDeLaConsultaDePrs`, que argumenta las tres dimensiones y
  // lo que costaba que faltaran. Este servidor guardaba una sola lista para
  // todos y nunca miraba la ruta ni la consulta: con la búsqueda del adapter
  // apuntada a otro repositorio, o a una rama que no existe, esta suite
  // quedaba entera en verde.
  late Map<String, List<Map<String, Object?>>> prsPorConsulta;

  // Lo que el servidor VIO cuando le pidieron la búsqueda idempotente: la
  // ruta y los dos filtros, crudos y sin pasar por la clave de partición. Un
  // ancla escrita con esa clave pasa verde con la partición colapsada, porque
  // las dos mitades de la comparación se colapsan juntas: medido.
  late List<ConsultaVista> busquedasVistas;

  // Los pull requests de la consulta que `solicitud` va a hacer. Es la
  // partición por omisión: las pruebas que siembran un pull request ya
  // existente hablan siempre del que existiría para ESTA rebanada.
  List<Map<String, Object?>> prsExistentes() =>
      prsPorConsulta.putIfAbsent(claveDeLaSolicitud, () => []);

  var creados = 0;
  var perderRespuestaDelPost = false;

  setUp(() async {
    prsPorConsulta = {};
    busquedasVistas = [];
    creados = 0;
    perderRespuestaDelPost = false;
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((p) async {
      final esBusqueda = p.method == 'GET';
      final cuerpo = esBusqueda
          ? null
          : jsonDecode(await utf8.decoder.bind(p).join())
                as Map<String, Object?>;
      final clave = esBusqueda
          ? claveDeLaConsultaDePrs(
              ruta: p.uri.path,
              head: p.uri.queryParameters['head'],
              base: p.uri.queryParameters['base'],
            )
          : claveDeLaConsultaDePrs(
              ruta: p.uri.path,
              head: headDeLaCreacion(
                ruta: p.uri.path,
                ramaDelCuerpo: cuerpo!['head']! as String,
              ),
              base: cuerpo['base']! as String,
            );
      if (esBusqueda) {
        busquedasVistas.add((
          ruta: p.uri.path,
          head: p.uri.queryParameters['head'],
          base: p.uri.queryParameters['base'],
        ));
      }
      final delOtroLado = prsPorConsulta.putIfAbsent(clave, () => []);
      if (esBusqueda) {
        p.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(delOtroLado));
        await p.response.close();
        return;
      }
      creados++;
      final nuevo = {
        'html_url': 'https://forja/pr/$creados',
        'state': 'open',
        'merged_at': null,
        'body': cuerpo!['body'],
        'head': {'sha': revisionDePrueba},
      };
      delOtroLado.add(nuevo);
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
    // Para la prueba que le pide lo MISMO a dos repositorios distintos: por
    // omisión es el de esta suite.
    String duenioDelRemoto = duenio,
    String repositorioDelRemoto = repositorio,
  }) => SalidaDePrDeGitHub(
    configuracion: ConfiguracionDeGitHub(
      duenio: duenioDelRemoto,
      repositorio: repositorioDelRemoto,
      baseDeLaApi: Uri.parse('http://127.0.0.1:${api.port}'),
      urlDelRemoto:
          'http://127.0.0.1:${api.port}/$duenioDelRemoto/$repositorioDelRemoto.git',
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

  test('real: la búsqueda idempotente pregunta por ESTE repositorio, ESTA '
      'rama y ESTA base', () async {
    // **Nada en el árbol cubría esta elección**, y es la misma prueba que
    // ancla las otras dos suites: las tres tienen que medir lo mismo, o la que
    // falte vuelve a ser el lugar por donde se cuela. Se mide sobre lo que el
    // servidor VIO llegar, no sobre la clave con la que particiona.
    await sinkReal().open(solicitud());
    expect(busquedasVistas, hasLength(1));
    expect(busquedasVistas.single.ruta, '/repos/$duenio/$repositorio/pulls');
    expect(busquedasVistas.single.head, '$duenio:$rama');
    expect(busquedasVistas.single.base, base);
  });

  test(
    'real: un pull request de OTRO repositorio no contesta esta búsqueda',
    () async {
      // El ancla de la partición del servidor de esta suite, medida por el
      // efecto: dos pedidos idénticos a dos repositorios dejan DOS pull
      // requests. Con una sola lista para todos —como guardaba— el segundo
      // encontraba el del primero y no creaba ninguno, y esta suite quedaba
      // entera en verde con la búsqueda apuntada al repositorio equivocado.
      await sinkReal().open(solicitud());
      await sinkReal(
        duenioDelRemoto: 'otro',
        repositorioDelRemoto: 'repositorio',
      ).open(solicitud());
      expect(creados, 2);
    },
  );

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
        prsExistentes().single['html_url'],
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
