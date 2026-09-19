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
/// es la prueba que rebobina el documento a `committed` —la única que llega
/// hasta la búsqueda—: **la búsqueda idempotente que esa
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

  /// Si el otro lado RECHAZA la creación. Con esto puesto, la búsqueda sigue
  /// contestando y el `POST` vuelve con un rechazo de la forja: el adapter lo
  /// clasifica como una publicación NO utilizable, que es el único hecho
  /// remoto que deja al reintento en el mismo estado del que salió.
  final bool rechazaLaCreacion;

  ForjaDeLaPrueba._(this._api, this.revision, this.rechazaLaCreacion) {
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
      if (rechazaLaCreacion) {
        pedido.response
          ..statusCode = HttpStatus.unprocessableEntity
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(const {'message': 'no'}));
        await pedido.response.close();
        return;
      }
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

  static Future<ForjaDeLaPrueba> nueva(
    String revision, {
    bool rechazaLaCreacion = false,
  }) async => ForjaDeLaPrueba._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    revision,
    rechazaLaCreacion,
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
    String? revisionDeclarada,
    String? rutaExtra,
    bool sinRemoto = false,
    bool laForjaRechaza = false,
    bool ramaAvanzada = false,
    bool conflictoSinResolver = false,
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
    if (!sinRemoto) git(['remote', 'add', 'origin', remotoAtendible]);

    final revision = git(['rev-parse', 'HEAD']);
    final arbol = git(['rev-parse', 'HEAD^{tree}']);
    final base = git(['rev-parse', 'HEAD^']);
    if (ramaAvanzada) {
      // Otra cosa avanzó la rama DESPUÉS de que la corrida anotara su
      // revisión: el `HEAD` ya no es ni la base ni la revisión candidata.
      escribir('otro.txt', 'de otra persona\n');
      git(['add', '-A']);
      git(['commit', '-m', 'trabajo de al lado']);
    }

    if (conflictoSinResolver) {
      // Un `merge` que no cerró sobre la MISMA ruta que la rebanada declaró.
      // No mueve el `HEAD` —un merge con conflicto no commitea nada—, así que
      // la revisión que el documento afirma sigue siendo la de la rama: lo
      // único que cambia es que el índice queda con una entrada sin fusionar.
      git(['switch', '-c', 'de-al-lado', '$revision^']);
      escribir(_archivo, 'de al lado\n');
      git(['commit', '-am', 'de al lado']);
      git(['switch', 'trabajo']);
      Process.runSync('git', [
        'merge',
        'de-al-lado',
      ], workingDirectory: raiz.path);
    }

    final mundo = MundoDeReintento._(
      raiz: raiz,
      repo: RepositorioGit(
        directorio: raiz.path,
        politica: PoliticaDeArtefactosFalsa(),
      ),
      registro: RegistroDeCorridas(raiz: '${raiz.path}/.shipflow'),
      forja: await ForjaDeLaPrueba.nueva(
        revision,
        rechazaLaCreacion: laForjaRechaza,
      ),
      arbolLeidoDelRepo: arbol,
    );
    addTearDown(mundo.forja.cerrar);

    if (estado != null) {
      await mundo.registro.escribir(
        idDeLaCorrida,
        _documentoEn(
          estado,
          revision: revisionDeclarada ?? revision,
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
    String? revisionDeclarada,
    String? rutaExtra,
    bool sinRemoto = false,
    bool laForjaRechaza = false,
    bool ramaAvanzada = false,
    bool conflictoSinResolver = false,
  }) => nuevo(
    estado: estado,
    conflictoSinResolver: conflictoSinResolver,
    verificacion: verificacion,
    mensajeDelCommit: mensajeDelCommit,
    arbolDeclarado: arbolDeclarado,
    revisionDeclarada: revisionDeclarada,
    rutaExtra: rutaExtra,
    sinRemoto: sinRemoto,
    laForjaRechaza: laForjaRechaza,
    ramaAvanzada: ramaAvanzada,
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
  Future<ShipOutcome?> correr(
    String cual, {
    bool dryRun = false,
    bool json = false,
  }) async {
    final salida = StringBuffer();
    _codigo = await ejecutar(
      [
        'ship',
        '--retry-publication',
        cual,
        if (dryRun) '--dry-run',
        if (json) '--json',
      ],
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

  /// El documento de esta corrida ENTERO, serializado.
  ///
  /// **Comparar la instantánea y no solo el estado** es lo que convierte «no
  /// se tocó» en una afirmación sobre el documento y no sobre uno de sus
  /// campos: un camino que no publica tampoco puede cambiarle el desenlace, la
  /// revisión ni el borrador, y un control que mirara solo `estado` decidiría
  /// sobre una representación más pobre que su criterio.
  Future<String> instantanea() async =>
      jsonEncode((await documento()).toJson());

  /// Todo lo que la última corrida le escribió a quien la corrió.
  String get mensaje => _salida;

  /// El payload de máquina del resultado de la última corrida, que tiene que
  /// haberse corrido con `json: true`.
  ///
  /// **Se lee el ÚLTIMO sobre y no el primero**: el protocolo emite cero o
  /// más eventos y después exactamente un resultado, y lo que esta lectura
  /// necesita es el resultado.
  Map<String, Object?> get payload {
    final lineas = _salida.split('\n').where((l) => l.trim().isNotEmpty);
    if (lineas.isEmpty) {
      throw StateError(
        'Esa corrida no escribió ningún sobre: ¿se corrió sin `json: true`?',
      );
    }
    final sobre = jsonDecode(lineas.last) as Map<String, Object?>;
    return Map<String, Object?>.from(sobre['data']! as Map);
  }

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
    final antes = await m.instantanea();
    await m.correr(m.runId);
    expect(
      m.forja.recibidas,
      isEmpty,
      reason:
          'copiar el contenido del candidato satisface el constructor '
          'comparando el valor contra sí mismo y vacía su guarda',
    );
    expect(m.forja.pullRequestsAbiertos, 0);
    expect(await m.instantanea(), antes);
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

  test(
    'un reintento sobre un documento YA SELLADO ni llega a la forja',
    () async {
      // **El nombre dice lo que esta prueba mide, y NO es la idempotencia.**
      // Se llamaba «un segundo reintento no abre un segundo pull request», con
      // la razón «es el fallo más caro que esta rebanada puede producir», y no
      // lo medía: tras el primer reintento el documento queda publicado, la
      // puerta por estado contesta «ya publicado» y la forja no se toca. La
      // cuenta se queda en uno **sin que la búsqueda idempotente llegue a
      // correr**, y el desenlace que se lee abajo es el que dejó la PRIMERA
      // corrida. Con dos pruebas diciendo cubrir lo mismo y una sin cubrirlo,
      // el nombre y la razón se corrigen en vez de borrarse: este camino
      // —entrar dos veces y que la segunda frene antes de la forja— vale por
      // sí solo.
      //
      // Quien sí mide la idempotencia entre procesos es la prueba que rebobina
      // el documento a `committed`, al final de este archivo.
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.committed,
      );
      await m.correr(m.runId);
      final segundo = await m.correr(m.runId);
      expect(
        m.forja.recibidas,
        hasLength(1),
        reason:
            'la segunda invocación no le pidió NADA a la forja: la puerta por '
            'estado frenó antes de componer ninguna solicitud',
      );
      expect(m.forja.pullRequestsAbiertos, 1);
      expect(segundo, isA<Publicado>());
    },
  );

  test(
    'una corrida ya publicada NO se reintenta, y sale con éxito diciendo dónde',
    () async {
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.publicationComplete,
      );
      final antes = await m.instantanea();
      final r = await m.correr(m.runId);
      expect(m.codigo(r), Codigo.exito);
      expect(m.mensaje, contains('http'));
      expect(m.forja.recibidas, isEmpty);
      expect(await m.instantanea(), antes);
    },
  );

  test(
    'un CAS rechazado NO se reintenta, y manda a correr ship de nuevo',
    () async {
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.notApplied,
      );
      final antes = await m.instantanea();
      await m.correr(m.runId);
      expect(m.accion, contains('ship'));
      expect(m.forja.recibidas, isEmpty);
      expect(await m.instantanea(), antes);
    },
  );

  test(
    '--dry-run con reintento NO deja NADA: ni publicación ni sellado',
    () async {
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.committed,
      );
      final antes = await m.instantanea();
      await m.correr(m.runId, dryRun: true);
      expect(m.forja.recibidas, isEmpty);
      expect(await m.instantanea(), antes);
    },
  );

  test('desde preparado con reconciliación ambigua NO publica', () async {
    final m = await MundoDeReintento.conDocumentoEn(
      EstadoDelDocumento.prepared,
      mensajeDelCommit: 'otra cosa',
    );
    final antes = await m.instantanea();
    await m.correr(m.runId);
    expect(m.forja.recibidas, isEmpty);
    // **La aserción heredada del brief era `isNotEmpty`, y la aceptaba
    // cualquier texto**; su hermana del índice sí exige el comando y la ruta.
    // Acá se exige lo mismo —qué hacer, concreto— y además CUÁL de los cuatro
    // chequeos falló: es lo que el orden argumentado de la reconciliación
    // decide, y hasta acá ninguna prueba lo miraba de punta a punta.
    expect(m.mensaje, contains(CausaDeAmbiguedad.mensajeDistinto.name));
    expect(m.accion, contains('volver a correr'));
    expect(m.accion, contains('ship'));
    expect(await m.instantanea(), antes);
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
      final antes = await m.instantanea();
      await m.correr(m.runId);
      expect(m.forja.recibidas, isEmpty);
      expect(m.accion, contains('git reset'));
      expect(m.accion, contains('lib/b.txt'));
      expect(await m.instantanea(), antes);
    });

    test('un rechazo que sale con ÉXITO no manda una clave de error, y uno '
        'que no, sí', () async {
      // **Las dos reglas no podían ser las dos.** Este camino decidía salir
      // con éxito argumentando que lo es —«ya está publicado»: lo que se
      // pidió ya es cierto— y mandaba igual `error` en sus datos, mientras
      // el ensayo, tres casos más abajo, omite esa clave precisamente porque
      // ahí no hubo ninguno. Un consumidor automático tenía que elegir a cuál
      // de los dos creerle.
      final publicada = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.publicationComplete,
      );
      final r = await publicada.correr(publicada.runId, json: true);
      expect(publicada.codigo(r), Codigo.exito);
      expect(publicada.payload, isNot(contains('error')));
      expect(
        publicada.payload['causaDeNoReintento'],
        CausaDeNoReintento.yaPublicado.name,
        reason: 'el discriminador se manda igual: es lo que distingue el caso',
      );

      // Y la otra mitad de la regla: donde el código SÍ dice que algo falta,
      // la clave sigue estando. Sin esta segunda mitad, omitirla siempre
      // pasaría la prueba.
      final otraRama = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.committed,
      );
      Process.runSync('git', [
        'switch',
        '-c',
        'otra',
      ], workingDirectory: otraRama.raiz.path);
      final r2 = await otraRama.correr(otraRama.runId, json: true);
      expect(otraRama.codigo(r2), Codigo.errorDeConfiguracion);
      expect(otraRama.payload, contains('error'));
    });

    test('desde el índice inconsistente, con la rama YA EN OTRA revisión no '
        'se promueve', () async {
      // **La asimetría entre las dos reconciliaciones, cerrada y medida.**
      // Desde `prepared`, la comparación de tres casos exige que el `HEAD`
      // sea la revisión candidata; desde `localInconsistent` no lo exigía
      // nadie. El índice acá COINCIDE —el commit de al lado tocó otra ruta—,
      // así que sin la comprobación nueva este caso promovía y publicaba: un
      // pull request con lo que otro commiteó encima adentro, sobre un
      // artefacto que solo afirma la verificación de este candidato.
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.localInconsistent,
        ramaAvanzada: true,
      );
      final antes = await m.instantanea();
      final r = await m.correr(m.runId);
      expect(m.codigo(r), Codigo.errorDeConfiguracion);
      expect(m.forja.recibidas, isEmpty);
      expect(m.mensaje, contains(QueHacerAlRecuperar.alguienMasAvanzo.name));
      expect(m.accion, contains('volver a correr'));
      expect(await m.instantanea(), antes);

      // **El encabezado no puede contradecir a su propia línea siguiente.**
      // Esta respuesta se reusó de un origen donde «no dejó ninguna revisión
      // en la rama» es defendible —desde `prepared` el compare-and-swap pudo
      // no haber corrido nunca—. Acá es falso: el estado del índice
      // desincronizado solo existe DESPUÉS de que ese compare-and-swap
      // corrió, así que la revisión SÍ está en la rama, de antepasado del
      // `HEAD`. Lo que dejó de valer es que esté PUESTA, y eso es lo que la
      // acción siguiente ya decía mientras el encabezado decía lo contrario.
      expect(
        m.mensaje,
        isNot(contains('no dejó ninguna revisión en la rama')),
        reason:
            'la revisión está en la rama: este estado no existe sin que el '
            'compare-and-swap haya corrido',
      );
      expect(m.mensaje, contains('ya no está en la revisión'));

      // Y el payload dice lo mismo que el texto, con su propio
      // discriminador: sin él, un consumidor automático no puede separar los
      // dos orígenes —`queHacerAlRecuperar` vale lo mismo en los dos—.
      await m.correr(m.runId, json: true);
      expect(
        m.payload['laRevisionEnLaRama'],
        LaRevisionEnLaRama.estaPeroNoPuesta.name,
      );
      expect(m.payload['error'], isNot(contains('no hay revisión')));
    });

    test('un conflicto SIN RESOLVER sale como índice distinto, no como el '
        'arnés roto', () async {
      // **La misma ruta de la rebanada, con un `merge` que no cerró.** La
      // lectura del índice está ANTES de la bifurcación entre las dos
      // reconciliaciones, así que este estado alcanzaba a las dos: la letra
      // de una entrada sin fusionar llegaba al parser compartido, que falla
      // cerrado, y su excepción no es de la familia que la composición
      // atrapa — subía hasta la red de último recurso y salía «se rompió el
      // arnés, reportalo con la traza» sobre una corrida donde lo único que
      // pasa es que quien corre tiene un conflicto.
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.localInconsistent,
        conflictoSinResolver: true,
      );
      final antes = await m.instantanea();
      final r = await m.correr(m.runId);
      expect(m.codigo(r), Codigo.errorDeConfiguracion);
      expect(
        m.mensaje,
        isNot(contains('error interno del arnés')),
        reason: 'un conflicto sin resolver no es el arnés roto',
      );
      expect(m.accion, contains('git reset'));
      expect(m.accion, contains(_archivo));
      expect(m.forja.recibidas, isEmpty);
      expect(await m.instantanea(), antes);
    });

    test(
      'y desde PREPARADO también: el conflicto llega por la misma lectura',
      () async {
        // El otro camino de reconciliación, con el mismo estado del índice. No
        // es una repetición: lo que fija es que la lectura compartida está
        // ANTES de la bifurcación, así que cerrar esto de un solo lado no
        // alcanzaba. Acá el conflicto sale por el paso 4 de los cinco.
        final m = await MundoDeReintento.conDocumentoEn(
          EstadoDelDocumento.prepared,
          conflictoSinResolver: true,
        );
        final antes = await m.instantanea();
        final r = await m.correr(m.runId);
        expect(m.codigo(r), Codigo.errorDeConfiguracion);
        expect(m.mensaje, contains(CausaDeAmbiguedad.indiceDistinto.name));
        expect(m.accion, contains('git reset'));
        expect(m.forja.recibidas, isEmpty);
        expect(await m.instantanea(), antes);
      },
    );

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
        final antes = await m.instantanea();
        final r = await m.correr(m.runId);
        expect(m.codigo(r), Codigo.errorDeConfiguracion);
        expect(m.accion, contains('trabajo'));
        expect(m.forja.recibidas, isEmpty);
        expect(await m.instantanea(), antes);
      },
    );

    test(
      'sin revisión en la rama, el reintento manda a correr ship de nuevo',
      () async {
        // La cuarta respuesta de la reconciliación, y la única que no tenía
        // prueba: los cinco pasos cierran sin ambigüedad y lo que contestan NO
        // es promover, porque otra cosa avanzó la rama después de que esta
        // corrida anotara su revisión. Su detalle son seis líneas que hasta acá
        // no ejercitaba nadie.
        final m = await MundoDeReintento.conDocumentoEn(
          EstadoDelDocumento.prepared,
          ramaAvanzada: true,
        );
        final antes = await m.instantanea();
        final r = await m.correr(m.runId);
        expect(m.codigo(r), Codigo.errorDeConfiguracion);
        expect(m.mensaje, contains(QueHacerAlRecuperar.alguienMasAvanzo.name));
        // **La otra mitad de la regla.** Por ESTE origen la frase sí es
        // defendible —desde `prepared` nadie sabe si el compare-and-swap
        // llegó a correr—, así que se fija acá. Sin las dos mitades, darles
        // el mismo encabezado a los dos orígenes vuelve a pasar la suite.
        expect(m.mensaje, contains('no dejó ninguna revisión en la rama'));
        expect(m.accion, contains('volver a correr'));
        expect(
          m.accion,
          contains('almacén de objetos'),
          reason:
              'la alternativa dice POR QUÉ no se puede reintentar el '
              'compare-and-swap desde acá, no solo que no se puede',
        );
        expect(m.forja.recibidas, isEmpty);
        expect(await m.instantanea(), antes);
      },
    );

    test(
      'sin remoto, el reintento sale por configuración y NO por el arnés',
      () async {
        // **Ancla de la cláusula que deja publicar cuando hay reintento**, en
        // la raíz de composición. El intérprete RECHAZA `--yes` junto con la
        // bandera y acá no hay terminal, así que sin esa cláusula la
        // composición contesta que esta corrida no podría publicar, se saltea
        // la detención por falta de forja, y termina pidiéndole un pull request
        // a la forja que no está compuesta: un error interno del arnés por no
        // tener remoto configurado.
        final m = await MundoDeReintento.conDocumentoEn(
          EstadoDelDocumento.committed,
          sinRemoto: true,
        );
        final antes = await m.instantanea();
        final r = await m.correr(m.runId);
        expect(m.codigo(r), Codigo.errorDeConfiguracion);
        expect(m.mensaje, contains('no tiene remoto configurado'));
        expect(
          m.mensaje,
          isNot(contains('error interno del arnés')),
          reason: 'es una precondición del entorno, no el arnés roto',
        );
        // **Y la acción, no solo el texto humano.** Esta prueba afirmaba el
        // hecho y nunca lo que hay que hacer con él, así que no delataba dos
        // cosas falsas por este camino: que «no quedó ni un objeto ni un
        // commit» —la premisa de un reintento es que SÍ hay commit— y una
        // alternativa que no corre.
        expect(
          m.accion,
          isNot(contains('no quedó ni un objeto ni un commit')),
          reason: 'por este camino el commit existe: es la premisa entera',
        );
        expect(
          m.accion,
          contains('--retry-publication ${m.runId} --dry-run'),
          reason:
              'el ensayo alternativo tiene que ser el de ESTA invocación: '
              'sin la bandera del reintento sale por error de uso',
        );
        expect(await m.instantanea(), antes);
      },
    );

    test('un reintento que vuelve a fallar NO revienta el documento', () async {
      // **Ancla de la guarda que evita pedir una transición hacia el mismo
      // estado.** Desde `publicationIncomplete`, un remoto que vuelve a
      // rechazar produce otra publicación incompleta: el destino que ese
      // desenlace afirma es el estado en el que el documento YA está, y el
      // grafo de §9 no tiene esa arista. Sin la guarda, pedirla lanza y sale
      // «se rompió el arnés» sobre una corrida donde lo único que pasó es que
      // el remoto volvió a fallar.
      final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.publicationIncomplete,
        laForjaRechaza: true,
      );
      final antes = await m.instantanea();
      final r = await m.correr(m.runId);
      expect(r, isA<PublicacionIncompleta>());
      expect(m.codigo(r), Codigo.entregaIncompleta);
      expect(
        m.mensaje,
        isNot(contains('error interno del arnés')),
        reason: 'el remoto falló; el arnés no',
      );
      expect(m.forja.pullRequestsAbiertos, 0);
      expect(
        await m.instantanea(),
        antes,
        reason:
            'el documento ya afirma ese estado: no hay nada que avanzar, y '
            'la causa nueva del fallo remoto viaja entera en el desenlace',
      );
    });

    test(
      'una revisión que ya no está en el repositorio sale por configuración',
      () async {
        // **Ancla de la traducción del fallo de la herramienta a código de
        // configuración**, en la composición del reintento. Una corrida que
        // murió deja un objeto commit que ninguna rama alcanza y que el
        // recolector junta; leerlo falla, y sin esa traducción el fallo sube
        // hasta la red de último recurso y sale «reportalo con la traza» sobre
        // una corrida donde el arnés no se rompió.
        final m = await MundoDeReintento.conDocumentoEn(
          EstadoDelDocumento.committed,
          revisionDeclarada: 'ffffffffffffffffffffffffffffffffffffffff',
        );
        final r = await m.correr(m.runId);
        expect(m.codigo(r), Codigo.errorDeConfiguracion);
        expect(
          m.mensaje,
          isNot(contains('error interno del arnés')),
          reason:
              'que la revisión ya no esté es una precondición del entorno que '
              'dejó de valer, no el arnés roto',
        );
        expect(m.accion, contains('recolector'));
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
      // cubrir, y el único que la ejercita.** La prueba de entrar dos veces
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

    test(
      'desde la publicación INCOMPLETA tampoco se abre un segundo',
      () async {
        // **El ancla de una afirmación que estaba escrita y sin medir.** El
        // README dice que el reintento publica desde `publicationIncomplete`
        // sin abrir un segundo pull request; era cierto por mecanismo —el
        // camino es el mismo— y ninguna prueba salía de ese estado con un pull
        // request ya abierto del otro lado: la que mide la idempotencia
        // arranca desde `committed`. Y es el estado que MÁS lo necesita: un
        // documento en `publicationIncomplete` es justamente el que quedó
        // cuando el efecto remoto no se pudo confirmar, así que el reintento
        // desde ahí corre sin saber si del otro lado hay uno o ninguno.
        final m = await MundoDeReintento.conDocumentoEn(
          EstadoDelDocumento.committed,
        );
        await m.correr(m.runId);
        expect(m.forja.pullRequestsAbiertos, 1);
        await m.rebobinarA(EstadoDelDocumento.publicationIncomplete);

        final d = await m.correr(m.runId);
        expect(
          m.forja.recibidas,
          hasLength(2),
          reason: 'este camino SÍ le vuelve a pedir publicar a la forja',
        );
        expect(m.forja.pullRequestsAbiertos, 1);
        expect(d, isA<Publicado>());
        expect((d! as Publicado).pr.url, contains('/pr/1'));
        expect(
          (await m.documento()).estado,
          EstadoDelDocumento.publicationComplete,
        );
      },
    );
  });
}
