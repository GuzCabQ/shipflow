/// `--retry-publication` **de punta a punta**: desde la bandera hasta el pull
/// request, con el documento de la corrida como única fuente de todo lo que
/// no se vuelve a medir.
///
/// **El repositorio es de verdad**, en un directorio temporal, por el mismo
/// motivo que en las otras suites de este comando: lo que estas pruebas
/// afirman —qué padre, qué árbol, qué mensaje y qué índice tiene la revisión
/// candidata— no lo puede producir ningún doble sin reimplementar la
/// herramienta.
///
/// **Y la forja también es de verdad, con el remoto reemplazado.** El doble
/// de esta suite NO implementa el puerto de publicación: envuelve al adapter
/// REAL —armado por la misma fábrica de nombre neutro que usa la raíz de
/// composición— y solo registra qué solicitud le pasó por adentro. Lo que se
/// reemplaza es la API del otro lado, por un servidor local que guarda los
/// pull requests que le crean y los devuelve cuando se los buscan. La razón
/// es la prueba del segundo reintento: **la búsqueda idempotente que esa
/// prueba ejercita tiene que ser la del adapter**, porque si un doble la
/// simulara, lo que la prueba mediría es el doble. Acá no hay nada que la
/// simule — el marcador estable se escribe, se busca y se compara con el
/// código que corre en producción.
///
/// **Cada corrida arma un adapter NUEVO**, y eso es lo que hace de esta suite
/// una prueba entre procesos y no una entre dos llamadas: nada de lo que la
/// primera publicación dejó en memoria sobrevive a la segunda. Lo único que
/// cruza de una a otra es lo que cruzaría de verdad — el disco y el remoto.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

import 'apoyo.dart';

/// El archivo de la rebanada: versionado desde el primer commit, y la corrida
/// lo modifica.
const _archivo = 'lib/a.txt';

/// Lo que la corrida original dijo que iba a publicar. Es también el mensaje
/// del commit candidato: el paso 3 de la reconciliación compara justamente
/// esos dos.
const _intencion = 'publicar el cambio';

/// Un remoto que la fábrica del paquete de la forja SÍ atiende. Nadie sale a
/// la red por él: la base de la API se reemplaza por el servidor local.
const _remoto = 'https://github.com/duenio/repo.git';

/// La URL del pull request que una corrida ya publicada dejó anotado. **No es
/// la que produce el servidor local**, a propósito: si fueran la misma, una
/// prueba que afirma que el reintento NO publicó de nuevo pasaría igual
/// habiendo publicado.
const _urlYaAnotada = 'https://forja.invalida/pr/anotado-antes';

/// La forja del otro lado, y el doble que registra qué le llegó.
///
/// **Guarda HECHOS, no llamadas**: qué solicitudes le pasaron por adentro
/// —`recibidas`— y cuántos pull requests quedaron ABIERTOS del otro lado
/// —`pullRequestsAbiertos`—. Los dos números son distintos a propósito: un
/// reintento que vuelve a pedir la publicación suma una solicitud recibida y
/// NO suma un pull request, y esa diferencia es exactamente lo que la
/// búsqueda idempotente compra.
class ForjaDeLaPrueba {
  final HttpServer _api;

  /// La revisión con la que el servidor marca la cabeza de todo pull request
  /// que crea. La sabe el mundo porque él hizo el commit; el adapter real la
  /// compara contra la que trae la solicitud.
  final String revision;

  final List<Map<String, Object?>> _abiertos = [];

  /// Cada solicitud que le llegó al puerto, en orden.
  final List<PullRequestRequest> recibidas = [];

  /// Cuántos pull requests existen del otro lado.
  int get pullRequestsAbiertos => _abiertos.length;

  ForjaDeLaPrueba._(this._api, this.revision) {
    _api.listen((pedido) async {
      if (pedido.method == 'GET') {
        pedido.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_abiertos));
        await pedido.response.close();
        return;
      }
      final cuerpo =
          jsonDecode(await utf8.decoder.bind(pedido).join())
              as Map<String, Object?>;
      _abiertos.add({
        'html_url': 'https://forja.invalida/pr/${_abiertos.length + 1}',
        'state': 'open',
        'merged_at': null,
        // **El cuerpo se guarda tal cual llegó**, con el marcador estable
        // adentro: es la única clave por la que la búsqueda del adapter puede
        // reconocer este pull request más adelante, y reescribirlo acá sería
        // fabricar la coincidencia que la prueba tiene que medir.
        'body': cuerpo['body'],
        'head': {'sha': revision},
      });
      pedido.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_abiertos.last));
      await pedido.response.close();
    });
  }

  static Future<ForjaDeLaPrueba> nueva(String revision) async =>
      ForjaDeLaPrueba._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        revision,
      );

  Future<void> cerrar() => _api.close(force: true);

  /// El puerto de publicación de UNA corrida: el adapter real, envuelto.
  PullRequestSink puerto({required String directorio, required String url}) {
    final real = salidaDePrDelRemoto(
      urlDelRemoto: url,
      credenciales: const FuenteDeCredencialFalsa(
        credenciales: {
          claveDeCredencialDeLaForja: Credential(
            'un-secreto',
            label: claveDeCredencialDeLaForja,
          ),
        },
      ),
      claveDeCredencial: claveDeCredencialDeLaForja,
      directorio: directorio,
      entornoDelPadre: EntornoDelProceso(const {}),
      baseDeLaApi: Uri.parse('http://127.0.0.1:${_api.port}'),
      // Sale con cero sin hacer nada: lo que esta suite mide es la API, y el
      // empuje tiene su propia suite en el paquete de la forja. Se resuelve
      // por `PATH` porque su ruta difiere entre sistemas.
      programaDeGit: 'true',
    );
    if (real == null) {
      throw StateError(
        'La fábrica del paquete de la forja no atiende «$url». Este mundo lo '
        'compone con un remoto que sí atiende, así que un nulo acá es un '
        'defecto del montaje, no un hecho de la corrida.',
      );
    }
    return _PuertoQueRegistra(this, real);
  }
}

class _PuertoQueRegistra implements PullRequestSink {
  final ForjaDeLaPrueba _forja;
  final PullRequestSink _real;

  _PuertoQueRegistra(this._forja, this._real);

  @override
  Future<PublicationOutcome> open(PullRequestRequest request) async {
    _forja.recibidas.add(request);
    return _real.open(request);
  }
}

/// Un repositorio de verdad, con una corrida ya anotada en su documento, y la
/// invocación entera de `--retry-publication` por la frontera.
class MundoDeReintento {
  /// La identidad de la corrida que quedó a medias. Fijada porque la ruta de
  /// su documento tiene que ser conocida antes de escribirlo.
  static const idDeLaCorrida = 'r-1';

  /// La corrida que este mundo dejó a medias. **Getter de instancia sobre la
  /// constante**, para que una prueba pida el identificador AL MUNDO que lo
  /// escribió y no a la clase: dos mundos vivos a la vez comparten hoy el
  /// valor, y leerlo del mundo es lo que deja que eso cambie sin tocar
  /// ninguna prueba.
  String get runId => idDeLaCorrida;

  final Directory raiz;
  final RepositorioGit repo;
  final RegistroDeCorridas registro;
  final ForjaDeLaPrueba forja;

  /// El árbol de la revisión candidata, leído del repositorio con la
  /// herramienta y no por el camino que se está probando.
  final String arbolLeidoDelRepo;

  /// Cuántas cascadas corrió este mundo. La fábrica de cascadas se invoca en
  /// el único sitio que la corre —la línea que la construye sobre la raíz del
  /// candidato y le pide correr— así que cero acá es cero corridas.
  int cascadasCorridas = 0;

  String _salida = '';
  int _codigo = -1;
  ShipOutcome? _ultimoDesenlace;

  MundoDeReintento._({
    required this.raiz,
    required this.repo,
    required this.registro,
    required this.forja,
    required this.arbolLeidoDelRepo,
  });

  /// Un mundo con un repositorio y una forja, **y sin ningún documento**.
  static Future<MundoDeReintento> nuevo({
    EstadoDelDocumento? estado,
    EstadoDeCorrida verificacion = EstadoDeCorrida.verde,
    String? mensajeDelCommit,
    String? arbolDeclarado,
    String? rutaExtra,
  }) async {
    final raiz = Directory.systemTemp.createTempSync('ship_reintento_');
    addTearDown(() => raiz.deleteSync(recursive: true));

    String git(List<String> args) {
      final r = Process.runSync('git', args, workingDirectory: raiz.path);
      if (r.exitCode != 0) {
        throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
      }
      return (r.stdout as String).trim();
    }

    void escribir(String ruta, String contenido) {
      File('${raiz.path}/$ruta')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(contenido);
    }

    escribir(_archivo, 'antes\n');
    git(['init', '--initial-branch=main', '.']);
    git(['config', 'user.email', 'p@p']);
    git(['config', 'user.name', 'prueba']);
    git(['add', '-A']);
    git(['commit', '-m', 'base']);
    git(['switch', '-c', 'trabajo']);
    escribir(_archivo, 'después\n');
    git(['add', '-A']);
    git(['commit', '-m', mensajeDelCommit ?? _intencion]);
    git(['remote', 'add', 'origin', _remoto]);

    final revision = git(['rev-parse', 'HEAD']);
    final arbol = git(['rev-parse', 'HEAD^{tree}']);
    final base = git(['rev-parse', 'HEAD^']);

    final mundo = MundoDeReintento._(
      raiz: raiz,
      repo: RepositorioGit(
        directorio: raiz.path,
        politica: PoliticaDeArtefactosFalsa(),
      ),
      registro: RegistroDeCorridas(raiz: '${raiz.path}/.shipflow'),
      forja: await ForjaDeLaPrueba.nueva(revision),
      arbolLeidoDelRepo: arbol,
    );
    addTearDown(mundo.forja.cerrar);

    if (estado != null) {
      await mundo.registro.escribir(
        idDeLaCorrida,
        _documentoEn(
          estado,
          revision: revision,
          arbol: arbolDeclarado ?? arbol,
          base: base,
          verificacion: verificacion,
          rutas: [_archivo, if (rutaExtra != null) rutaExtra],
        ),
      );
    }
    return mundo;
  }

  /// Un mundo cuyo documento ya está en [estado].
  static Future<MundoDeReintento> conDocumentoEn(
    EstadoDelDocumento estado, {
    EstadoDeCorrida verificacion = EstadoDeCorrida.verde,
    String? mensajeDelCommit,
    String? arbolDeclarado,
    String? rutaExtra,
  }) => nuevo(
    estado: estado,
    verificacion: verificacion,
    mensajeDelCommit: mensajeDelCommit,
    arbolDeclarado: arbolDeclarado,
    rutaExtra: rutaExtra,
  );

  /// El documento tal como lo habría dejado la corrida original.
  ///
  /// **Se arma con [DocumentoDeCorrida.avanzarA] y no a mano**, por el mismo
  /// motivo por el que la corrida real lo hace así: un documento construido
  /// salteando el grafo puede afirmar un estado que ningún camino produce, y
  /// entonces el reintento se probaría contra una forma que en el disco no
  /// existe.
  static DocumentoDeCorrida _documentoEn(
    EstadoDelDocumento estado, {
    required String revision,
    required String arbol,
    required String base,
    required EstadoDeCorrida verificacion,
    required List<String> rutas,
  }) {
    final publicable = EstadoPublicable.desde(verificacion)!;
    final preparado = DocumentoDeCorrida.preparado(
      revision: revision,
      draft: PullRequestDraft(
        runId: idDeLaCorrida,
        branch: 'trabajo',
        base: 'main',
        artefacto: ArtefactoDeRevision(
          superficie: SuperficieDeVerificacion(
            cubierto: const [],
            requiereCriterio: const [],
            estado: verificacion,
          ),
          candidato: CandidateIdentity(
            contentRevision: arbol,
            baseRevision: base,
          ),
          intent: _intencion,
          plan: null,
          sinPlanPorque: 'esta corrida entra por el modo «solo PR»',
          alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
        ),
        rutas: rutas,
      ),
    );
    return switch (estado) {
      EstadoDelDocumento.prepared => preparado,
      EstadoDelDocumento.committed => preparado.avanzarA(
        EstadoDelDocumento.committed,
      ),
      EstadoDelDocumento.publicationComplete =>
        preparado
            .avanzarA(EstadoDelDocumento.committed)
            .avanzarA(
              EstadoDelDocumento.publicationComplete,
              desenlace: ShipOutcome.publicadoParaLaPrueba(
                pr: PullRequestOpen(url: _urlYaAnotada),
                verificacion: publicable,
              ),
            ),
      EstadoDelDocumento.publicationIncomplete =>
        preparado
            .avanzarA(EstadoDelDocumento.committed)
            .avanzarA(
              EstadoDelDocumento.publicationIncomplete,
              desenlace: ShipOutcome.publicacionIncompletaParaLaPrueba(
                remoto: PushUnknown(causa: CausaDePublicacion.red),
                verificacion: publicable,
              ),
            ),
      EstadoDelDocumento.notApplied => preparado.avanzarA(
        EstadoDelDocumento.notApplied,
        desenlace: ShipOutcome.noAplicadoParaLaPrueba(
          causa: CausaDeNoAplicacion.baseMovida,
          headObservado: base,
        ),
      ),
      EstadoDelDocumento.localInconsistent => preparado.avanzarA(
        EstadoDelDocumento.localInconsistent,
        desenlace: ShipOutcome.localInconsistenteParaLaPrueba(
          revision: revision,
        ),
      ),
    };
  }

  ColaboradoresDeShip _colaboradores(String directorio, Globales g) {
    final pasos = [Paso.verde('doble')];
    return ColaboradoresDeShip(
      repo: repo,
      ambiente: EntornoFalso(),
      construirCascada: (_) {
        cascadasCorridas++;
        return Cascada(
          pasos,
          observador: ObservadorDeAlcanceFalso(
            observados: {
              _archivo: ObservedSubject(
                subject: _archivo,
                ofStack: true,
                files: 1,
              ),
            },
          ),
        );
      },
      controles: {for (final p in pasos) p.id: p},
      credenciales: const FuenteDeCredencialFalsa(
        credenciales: {
          claveDeCredencialDeLaForja: Credential(
            'un-secreto',
            label: claveDeCredencialDeLaForja,
          ),
        },
      ),
      urlDelRemoto: repo.urlDelRemoto,
      // **Un adapter NUEVO por corrida.** Es lo que vuelve a esta suite una
      // prueba entre procesos: la segunda invocación no hereda nada de lo que
      // la primera haya podido recordar.
      forjaDelRemoto: (url) => forja.puerto(directorio: raiz.path, url: url),
      registro: registro,
      cambiosAjenos: (archivos) =>
          cambiosAjenosDelArbol(directorio: raiz.path, deLaRebanada: archivos),
      // **Nadie confirma nada, y no hace falta**: la compuerta y la
      // confirmación de esta corrida ya pasaron cuando corrió de verdad.
      responder: null,
      leerArchivo: (ruta) => File(ruta).readAsString(),
      nuevoRunId: () => throw StateError(
        'Un reintento NO emite una identidad nueva: termina la corrida cuyo '
        'identificador pidió quien corre. Que esta fábrica se haya llamado '
        'significa que el camino del reintento se cayó al de una corrida '
        'nueva.',
      ),
      baseConfigurada: 'main',
    );
  }

  /// Corre `shipflow ship --retry-publication <runId>` ENTERO, por la
  /// frontera, y devuelve **qué quedó en el documento de esa corrida**.
  ///
  /// Es el hecho que el reintento deja atrás, no lo que la función interna
  /// devolvió: nulo cuando no hay documento, y el desenlace que el documento
  /// lleva adentro cuando sí lo hay.
  Future<ShipOutcome?> correr(String cual, {bool dryRun = false}) async {
    final salida = StringBuffer();
    _codigo = await ejecutar(
      ['ship', '--retry-publication', cual, if (dryRun) '--dry-run'],
      directorio: raiz.path,
      salida: salida,
      error: StringBuffer(),
      construirShip: _colaboradores,
    );
    _salida = salida.toString();
    _ultimoDesenlace = await _desenlaceAnotadoEn(cual);
    return _ultimoDesenlace;
  }

  /// El desenlace que el documento de [cual] lleva anotado, o nulo si no hay
  /// documento **o si no se puede leer**.
  ///
  /// Tolera el fallo de lectura porque uno de los casos que esta suite mide
  /// es justamente un documento que no se deja leer: sin esta tolerancia, el
  /// mundo se caería antes de poder afirmar con qué código terminó la corrida
  /// que lo encontró.
  Future<ShipOutcome?> _desenlaceAnotadoEn(String cual) async {
    try {
      return (await registro.leer(cual))?.desenlace;
    } catch (_) {
      return null;
    }
  }

  /// El documento de esta corrida. **Lanza si no hay ninguno**: una prueba
  /// que le pregunte el estado a un documento que no existe está afirmando
  /// algo sobre nada.
  Future<DocumentoDeCorrida> documento() async {
    final d = await registro.leer(runId);
    if (d == null) {
      throw StateError('No hay documento para «$runId» en este mundo.');
    }
    return d;
  }

  /// Todo lo que la última corrida le escribió a quien la corrió.
  String get mensaje => _salida;

  /// La acción siguiente de la última corrida, o vacía si no dio ninguna.
  ///
  /// Sale del ÚNICO formato con el que las dos salidas humanas de este
  /// comando la escriben —el texto, un salto, y la flecha—: derivarla así es
  /// lo que hace que una acción ausente se lea como vacía en vez de como
  /// cualquier otra línea del mensaje.
  String get accion {
    const flecha = '\n  → ';
    final i = _salida.indexOf(flecha);
    return i < 0 ? '' : _salida.substring(i + flecha.length).trim();
  }

  /// El código con el que terminó la corrida que devolvió [desenlace].
  ///
  /// **Se OBSERVA, no se deriva.** Calcularlo acá con la misma función que
  /// usa la composición dejaría a la prueba midiendo esa derivación en vez de
  /// lo que el comando contestó. [desenlace] se exige —y se comprueba que sea
  /// el de la última corrida— para que el código que vuelve no pueda ser el
  /// de otra.
  int codigo(ShipOutcome? desenlace) {
    if (!identical(desenlace, _ultimoDesenlace)) {
      throw StateError(
        'Ese desenlace no es el de la última corrida de este mundo: el código '
        'que saldría de acá sería el de otra.',
      );
    }
    return _codigo;
  }

  /// Vuelve a dejar el documento en [estado], como si el proceso que acaba de
  /// correr hubiera muerto antes de sellarlo.
  ///
  /// **Es el único montaje que reproduce el escenario que la idempotencia
  /// existe para cubrir**: el pull request quedó abierto del otro lado y el
  /// documento local no llegó a enterarse.
  Future<void> rebobinarA(EstadoDelDocumento estado) async {
    final viejo = await documento();
    await registro.escribir(
      idDeLaCorrida,
      _documentoEn(
        estado,
        revision: viejo.revision,
        arbol: viejo.draft.artefacto.candidato.contentRevision,
        base: viejo.draft.artefacto.candidato.baseRevision,
        verificacion: viejo.draft.artefacto.superficie.estado,
        rutas: viejo.draft.rutas,
      ),
    );
  }
}

void main() {
  test(
    'un identificador que no existe sale con configuración y dice dónde buscó',
    () async {
      final m = await MundoDeReintento.nuevo();
      final r = await m.correr('r-inexistente');
      expect(m.codigo(r), Codigo.errorDeConfiguracion);
      expect(m.mensaje, contains('runs'));
    },
  );

  test('desde commiteado publica y sella, SIN correr la cascada', () async {
    final m = await MundoDeReintento.conDocumentoEn(
      EstadoDelDocumento.committed,
    );
    final d = await m.correr(m.runId);
    expect(d, isA<Publicado>());
    expect(m.forja.recibidas, hasLength(1));
    expect(
      m.cascadasCorridas,
      0,
      reason:
          'el documento lleva el borrador completo justamente para que '
          'la recuperación no vuelva a verificar nada',
    );
    expect(
      (await m.documento()).estado,
      EstadoDelDocumento.publicationComplete,
    );
  });

  test('el árbol de la solicitud se MIDE, no se copia del documento', () async {
    // **El brief pedía afirmar `recibidas.single.arbolDeLaRevision`, y ese
    // getter NO EXISTE.** `PullRequestRequest` RECIBE el árbol, lo valida
    // contra lo que el candidato declaró y no lo guarda: guardarlo sería
    // tener como campo asignable algo derivable de otro campo, que es lo que
    // este proyecto prohíbe en el paquete del dominio.
    //
    // **Y aunque existiera, una igualdad entre los dos no podría fallar.**
    // Sobre un documento sano coinciden byte a byte —el árbol de un objeto
    // commit no cambia nunca—, así que copiar el `contentRevision` del
    // candidato en vez de medirlo produce EXACTAMENTE el mismo valor y
    // ninguna aserción sobre su igualdad distingue las dos versiones.
    //
    // Lo que sí las distingue es un documento cuyo árbol declarado no es el
    // de su revisión: midiendo, la guarda del constructor de la solicitud
    // rechaza y no se publica nada; copiando, esa guarda compara el valor
    // contra sí mismo, pasa, y se abre un pull request que afirma
    // verificación sobre contenido que no contiene.
    //
    // **Residuo declarado:** hoy ese rechazo sale por la red de último
    // recurso —el constructor lanza, y una solicitud mal compuesta es «un
    // defecto de quien compone»—, así que esta prueba afirma lo que importa
    // —que no se publicó— y no el código con el que se detuvo.
    final m = await MundoDeReintento.conDocumentoEn(
      EstadoDelDocumento.committed,
      arbolDeclarado: '0000000000000000000000000000000000000000',
    );
    await m.correr(m.runId);
    expect(
      m.forja.recibidas,
      isEmpty,
      reason:
          'copiar el contenido del candidato satisface el constructor '
          'comparando el valor contra sí mismo y vacía su guarda',
    );
    expect(m.forja.pullRequestsAbiertos, 0);
  });

  test('una corrida ROJA autorizada en su momento se publica igual', () async {
    final m = await MundoDeReintento.conDocumentoEn(
      EstadoDelDocumento.committed,
      verificacion: EstadoDeCorrida.rojo,
    );
    final d = await m.correr(m.runId);
    expect(d, isA<Publicado>());
    expect(
      (d as Publicado).verificacion,
      EstadoPublicable.rojo,
      reason:
          'la compuerta pasó cuando la corrida corrió; volver a '
          'evaluarla acá derivaría NoIntentado y el sellado reventaría',
    );
  });

  test('desde una publicación incompleta reintenta y completa', () async {
    final m = await MundoDeReintento.conDocumentoEn(
      EstadoDelDocumento.publicationIncomplete,
    );
    final d = await m.correr(m.runId);
    expect(d, isA<Publicado>());
  });

  test('UN SEGUNDO reintento NO abre un segundo pull request', () async {
    final m = await MundoDeReintento.conDocumentoEn(
      EstadoDelDocumento.committed,
    );
    await m.correr(m.runId);
    final segundo = await m.correr(m.runId);
    expect(
      m.forja.pullRequestsAbiertos,
      1,
      reason: 'es el fallo más caro que esta rebanada puede producir',
    );
    expect(segundo, isA<Publicado>());
  });

  test(
    'una corrida ya publicada NO se reintenta, y sale con éxito diciendo dónde',
    () async {
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.publicationComplete,
      );
      final r = await m.correr(m.runId);
      expect(m.codigo(r), Codigo.exito);
      expect(m.mensaje, contains('http'));
      expect(m.forja.recibidas, isEmpty);
    },
  );

  test(
    'un CAS rechazado NO se reintenta, y manda a correr ship de nuevo',
    () async {
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.notApplied,
      );
      await m.correr(m.runId);
      expect(m.accion, contains('ship'));
      expect(m.forja.recibidas, isEmpty);
    },
  );

  test(
    '--dry-run con reintento NO deja NADA: ni publicación ni sellado',
    () async {
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.committed,
      );
      final antes = await m.documento();
      await m.correr(m.runId, dryRun: true);
      expect(m.forja.recibidas, isEmpty);
      expect((await m.documento()).estado, antes.estado);
    },
  );

  test('desde preparado con reconciliación ambigua NO publica', () async {
    final m = await MundoDeReintento.conDocumentoEn(
      EstadoDelDocumento.prepared,
      mensajeDelCommit: 'otra cosa',
    );
    await m.correr(m.runId);
    expect(m.forja.recibidas, isEmpty);
    expect(m.accion, isNotEmpty);
  });

  group('lo que el brief no cubría', () {
    test(
      'desde preparado, la reconciliación que cierra promueve y publica',
      () async {
        // El camino POSITIVO de los cinco pasos. Sin esta prueba, lo único que
        // la suite mide de `prepared` es que una reconciliación ambigua frena,
        // y eso pasaría igual con la promoción entera desconectada.
        final m = await MundoDeReintento.conDocumentoEn(
          EstadoDelDocumento.prepared,
        );
        final d = await m.correr(m.runId);
        expect(d, isA<Publicado>());
        expect(
          (await m.documento()).estado,
          EstadoDelDocumento.publicationComplete,
        );
      },
    );

    test(
      'desde el índice inconsistente, si ya coincide se promueve y publica',
      () async {
        // La otra reconciliación de §9, la que no tiene ninguna otra prueba en
        // esta suite: el commit existe, el índice ya no difiere, y la corrida
        // se termina por la arista condicionada del documento.
        final m = await MundoDeReintento.conDocumentoEn(
          EstadoDelDocumento.localInconsistent,
        );
        final d = await m.correr(m.runId);
        expect(d, isA<Publicado>());
        expect(
          (await m.documento()).estado,
          EstadoDelDocumento.publicationComplete,
        );
      },
    );

    test('desde el índice inconsistente, si NO coincide dice con qué comando '
        'repararlo', () async {
      // Una ruta que la rebanada declaró, que el árbol de la revisión NO
      // tiene y que el índice de quien corre SÍ: es la diferencia que la
      // comparación acotada a las rutas de la rebanada tiene que ver.
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.localInconsistent,
        rutaExtra: 'lib/b.txt',
      );
      File('${m.raiz.path}/lib/b.txt').writeAsStringSync('de al lado\n');
      Process.runSync('git', [
        'add',
        'lib/b.txt',
      ], workingDirectory: m.raiz.path);
      await m.correr(m.runId);
      expect(m.forja.recibidas, isEmpty);
      expect(m.accion, contains('git reset'));
      expect(m.accion, contains('lib/b.txt'));
      expect(
        (await m.documento()).estado,
        EstadoDelDocumento.localInconsistent,
      );
    });

    test(
      'parado en OTRA rama el reintento no actúa, y dice a cuál cambiarse',
      () async {
        final m = await MundoDeReintento.conDocumentoEn(
          EstadoDelDocumento.committed,
        );
        Process.runSync('git', [
          'switch',
          '-c',
          'otra',
        ], workingDirectory: m.raiz.path);
        final r = await m.correr(m.runId);
        expect(m.codigo(r), Codigo.errorDeConfiguracion);
        expect(m.accion, contains('trabajo'));
        expect(m.forja.recibidas, isEmpty);
      },
    );

    test(
      'un documento que no se puede leer NO sale como error del arnés',
      () async {
        final m = await MundoDeReintento.nuevo();
        File(m.registro.documentoDe(MundoDeReintento.idDeLaCorrida))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('{"formatVersion": 99}\n');
        final r = await m.correr(m.runId);
        expect(
          m.codigo(r),
          Codigo.errorDeConfiguracion,
          reason:
              'un documento de otra versión no es el arnés roto: es una '
              'precondición del entorno, y el 70 manda a reportar una traza '
              'sobre una corrida donde no se rompió nada',
        );
        expect(m.mensaje, isNot(contains('error interno del arnés')));
      },
    );

    test('con el pull request YA abierto por otro proceso, el reintento NO '
        'abre un segundo', () async {
      // **Éste es el escenario que la idempotencia entre procesos existe para
      // cubrir, y el único que la ejercita.** La prueba del segundo reintento
      // —la que pedía el brief— no llega hasta la búsqueda: el filtro por
      // estado ve un documento ya publicado y frena antes, así que la forja
      // no se toca. Acá el documento se rebobina a `committed`, que es
      // exactamente lo que queda cuando el proceso muere DESPUÉS de que la
      // forja creó el pull request y ANTES de sellar. El segundo proceso no
      // sabe nada de lo que hizo el primero: lo único que lo salva de abrir
      // un segundo pull request es que el marcador estable se reconstruye
      // igual desde el disco y la búsqueda del adapter lo encuentra.
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.committed,
      );
      await m.correr(m.runId);
      expect(m.forja.pullRequestsAbiertos, 1);
      await m.rebobinarA(EstadoDelDocumento.committed);

      final d = await m.correr(m.runId);
      expect(
        m.forja.recibidas,
        hasLength(2),
        reason: 'el segundo proceso SÍ le pidió publicar a la forja',
      );
      expect(
        m.forja.pullRequestsAbiertos,
        1,
        reason:
            'y la forja no abrió un segundo: la búsqueda idempotente '
            'del adapter reconoció el marcador que el primero escribió',
      );
      expect(d, isA<Publicado>());
      expect((d! as Publicado).pr.url, contains('/pr/1'));
    });
  });
}
