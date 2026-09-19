/// La fábrica neutra: **lo único que la raíz de composición nombra de este
/// paquete**.
///
/// Mide cuatro cosas que ninguna otra suite puede medir. La primera, que de
/// una URL de `git` salen el dueño y el repositorio —y nulo, nunca una
/// excepción, cuando no sale—. La segunda, que «saber atender» quiere decir el
/// camino entero y no el parseo: una forma que se lee perfectamente pero que
/// la publicación rechazaría vuelve nula acá, antes de que la corrida escriba
/// nada. La tercera, que una credencial embebida en la autoridad de esa URL no
/// termina adentro de lo que se construye. Y la cuarta, la que justifica que
/// esta suite exista: que **envolver al adapter no le tapó las costuras**. El
/// adapter recibe una fábrica de cliente y dos presupuestos a propósito, para
/// que sus pruebas no salgan a la red ni esperen minutos; una fábrica que los
/// fijara adentro dejaría a este archivo sin forma de probarse sin red.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

/// La clave bajo la que viaja la credencial en esta suite. **No es la que el
/// adapter traía escrita adentro**, y por eso esta constante existe: con la
/// clave fija en el adapter, la prueba que la usa se pone roja.
const claveDePrueba = 'UNA_CLAVE_QUE_ELIGE_QUIEN_COMPONE';

const secretoDePrueba = 'ghp_secreto';

const revisionDePrueba = 'a4e66d50d152b67d451a9028fd1cf54c71e18e79';

/// Contesta **solo** a su clave. `_CredencialFija`, en la suite vecina,
/// contesta a cualquiera: con ese doble, una fábrica que ignorara la clave
/// pasaría igual.
class _CredencialPorClave implements CredentialSource {
  final String clave;
  const _CredencialPorClave(this.clave);

  @override
  Future<Credential?> read(String key) async =>
      key == clave ? const Credential(secretoDePrueba, label: 'x') : null;
}

void main() {
  late Directory raiz;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('forge_composicion_');
  });

  tearDown(() => raiz.deleteSync(recursive: true));

  PullRequestSink? construir(
    String urlDelRemoto, {
    Uri? baseDeLaApi,
    String clave = claveDePrueba,
    CredentialSource? credenciales,
    Duration presupuestoDeRed = SalidaDePrDeGitHub.presupuestoDeRedPorDefecto,
  }) => salidaDePrDelRemoto(
    urlDelRemoto: urlDelRemoto,
    credenciales: credenciales ?? const _CredencialPorClave(claveDePrueba),
    claveDeCredencial: clave,
    directorio: raiz.path,
    entornoDelPadre: EntornoDelProceso(const {}),
    baseDeLaApi: baseDeLaApi,
    // `true` sale con cero sin hacer nada: acá se mide la composición, no el
    // empuje, que tiene su propia suite en este mismo directorio.
    programaDeGit: 'true',
    presupuestoDeRed: presupuestoDeRed,
  );

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
    intent: 'probar la fábrica',
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

  group('las formas con las que git escribe un remoto', () {
    for (final (nombre, url) in const [
      ('https con sufijo', 'https://github.com/duenio/repo.git'),
      ('https sin sufijo', 'https://github.com/duenio/repo'),
      ('https con barra final', 'https://github.com/duenio/repo/'),
      (
        'con credencial en la autoridad',
        'https://x-access-token:$secretoDePrueba@github.com/duenio/repo.git',
      ),
    ]) {
      test('$nombre da el dueño y el repositorio', () {
        final salida = construir(url);
        expect(salida, isNotNull, reason: url);
        final configuracion = (salida! as SalidaDePrDeGitHub).configuracion;
        expect(configuracion.duenio, 'duenio', reason: url);
        expect(configuracion.repositorio, 'repo', reason: url);
      });
    }
  });

  group('lo que no se atiende vuelve nulo, no lanza', () {
    for (final (nombre, url) in const [
      ('un host que este adapter no atiende', 'https://otra.forja/d/r.git'),
      (
        'un host que solo TERMINA como el atendido',
        'https://no-github.com/d/r.git',
      ),
      ('sin repositorio', 'https://github.com/duenio'),
      ('sin dueño ni repositorio', 'https://github.com/'),
      (
        'más segmentos que dueño y repositorio',
        'https://github.com/duenio/repo/extra',
      ),
      ('una ruta local, que no es de ninguna forja', '/un/directorio/repo.git'),
      ('texto que no es una URL', 'no es una url'),
      ('vacía', ''),
      // El esquema es el del canal que sí se atiende, pero no hay autoridad:
      // lo que parece el host es en realidad la primera parte de la ruta.
      // Atenderla armaría un destino con un host inventado.
      ('el esquema atendido sin autoridad', 'https:duenio/repo'),
    ]) {
      test('$nombre → nulo', () {
        expect(construir(url), isNull, reason: url);
      });
    }
  });

  group('un canal por el que el empuje no publicaría no se atiende', () {
    // **Estas formas se leen bien y AUN ASÍ vuelven nulas**, que es lo que las
    // separa del grupo de arriba: de todas salen el dueño y el repositorio, y
    // de todas el empuje se negaría a publicar porque adjunta la credencial en
    // la parte de usuario de la URL y ahí no la protege nada. Atenderlas
    // significaría correr la corrida entera —commit y documento incluidos—
    // para fallar recién en la publicación, que es justo lo que el preflight
    // existe para evitar. Quien decide es el MISMO predicado que decide el
    // empuje, así que las dos no pueden divergir.
    for (final (nombre, url) in const [
      ('la forma corta de ssh', 'git@github.com:duenio/repo.git'),
      ('la forma corta de ssh sin sufijo', 'git@github.com:duenio/repo'),
      ('ssh explícito', 'ssh://git@github.com/duenio/repo.git'),
      (
        'la forma corta con una contraseña adentro',
        'usuario:$secretoDePrueba@github.com:duenio/repo.git',
      ),
      (
        'el protocolo propio de git, sin cifrar',
        'git://github.com/duenio/repo',
      ),
      ('el esquema sin cifrar', 'http://github.com/duenio/repo.git'),
      (
        'el esquema sin cifrar con la credencial adentro',
        'http://x-access-token:$secretoDePrueba@github.com/duenio/repo.git',
      ),
    ]) {
      test('$nombre → nulo', () {
        expect(construir(url), isNull, reason: url);
      });
    }

    test('y el predicado es el del empuje, no una copia', () {
      // La prueba que impide que las dos definiciones se separen: lo que esta
      // función atiende tiene que ser exactamente lo que `empujar` acepta. Si
      // alguien ensancha una de las dos sin la otra, esto se pone rojo.
      for (final url in const [
        'https://github.com/duenio/repo.git',
        'http://github.com/duenio/repo.git',
        'git@github.com:duenio/repo.git',
        'ssh://git@github.com/duenio/repo.git',
        'git://github.com/duenio/repo',
      ]) {
        expect(
          construir(url) != null,
          esCanalSeguroParaLaCredencial(url),
          reason: url,
        );
      }
    });
  });

  test('la credencial de la URL no entra en lo que se construye', () {
    // Lo que se construye guarda la URL del remoto para empujar. Si la
    // credencial embebida viajara ahí, cualquier mensaje o volcado que la
    // nombre la publica — y quien la puso en el remoto no autorizó eso.
    final salida =
        construir(
              'https://x-access-token:$secretoDePrueba@github.com/duenio/repo.git',
            )!
            as SalidaDePrDeGitHub;
    expect(salida.configuracion.urlDelRemoto, isNot(contains(secretoDePrueba)));
    expect(
      salida.configuracion.urlDelRemoto,
      'https://github.com/duenio/repo.git',
    );
    expect(
      '${salida.configuracion.baseDeLaApi}',
      isNot(contains(secretoDePrueba)),
    );
  });

  group('las costuras del adapter siguen abiertas', () {
    late HttpServer api;
    late List<String> autorizaciones;
    late int creados;

    setUp(() async {
      autorizaciones = [];
      creados = 0;
      api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      api.listen((p) async {
        autorizaciones.add(
          p.headers.value(HttpHeaders.authorizationHeader) ?? '',
        );
        if (p.method == 'GET') {
          p.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write('[]');
          await p.response.close();
          return;
        }
        creados++;
        await utf8.decoder.bind(p).join();
        p.response
          ..statusCode = 201
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'html_url': 'http://127.0.0.1/pr/1',
              'state': 'open',
              'merged_at': null,
              'body': '',
              'head': {'sha': revisionDePrueba},
            }),
          );
        await p.response.close();
      });
    });

    tearDown(() async => api.close(force: true));

    test(
      'la base de la API se puede pasar: la corrida no sale a la red',
      () async {
        final salida = construir(
          'https://github.com/duenio/repo.git',
          baseDeLaApi: Uri.parse('http://127.0.0.1:${api.port}'),
        )!;
        expect(await salida.open(solicitud()), isA<PullRequestOpen>());
        expect(creados, 1, reason: 'el pedido llegó al servidor de esta suite');
      },
    );

    test('la clave de la credencial es la que se le pasa', () async {
      // El adapter la traía escrita adentro. Con la clave fija, este caso
      // sale `PushFailed(autenticacion)`: la fuente no contesta a esa clave.
      final salida = construir(
        'https://github.com/duenio/repo.git',
        baseDeLaApi: Uri.parse('http://127.0.0.1:${api.port}'),
      )!;
      await salida.open(solicitud());
      expect(
        autorizaciones,
        everyElement(contains(secretoDePrueba)),
        reason: 'el secreto que llegó es el de LA clave que se pasó',
      );
    });

    test('una clave que la fuente no tiene no toca la red', () async {
      final salida = construir(
        'https://github.com/duenio/repo.git',
        baseDeLaApi: Uri.parse('http://127.0.0.1:${api.port}'),
        clave: 'OTRA_QUE_NADIE_TIENE',
      )!;
      final r = await salida.open(solicitud());
      expect(r, isA<PushFailed>());
      expect((r as PushFailed).causa, CausaDePublicacion.autenticacion);
      expect(autorizaciones, isEmpty);
    });
  });

  test(
    'el presupuesto de red se puede acortar: la prueba no espera 30 s',
    () async {
      // La costura que más cara sale perder al envolver. Un servidor que acepta
      // la conexión y no contesta nunca: con el presupuesto por omisión esta
      // prueba tardaría treinta segundos, y con la costura tapada no habría
      // manera de acortarlo.
      final mudo = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => mudo.close(force: true));
      mudo.listen((_) {});
      final salida = construir(
        'https://github.com/duenio/repo.git',
        baseDeLaApi: Uri.parse('http://127.0.0.1:${mudo.port}'),
        presupuestoDeRed: const Duration(milliseconds: 50),
      )!;
      final reloj = Stopwatch()..start();
      final r = await salida.open(solicitud());
      reloj.stop();
      expect(r, isA<PullRequestFailed>());
      expect(reloj.elapsed, lessThan(const Duration(seconds: 5)));
    },
  );
}
