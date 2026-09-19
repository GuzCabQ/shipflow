/// Los dieciséis pasos, camino por camino: qué queda escrito y qué no.
///
/// **Las pruebas son de camino, no de llamada.** Cada una fija un desenlace y
/// mide lo que la corrida DEJÓ: objetos en el repositorio, commits en la rama,
/// pull requests pedidos, temporales sobrevivientes, documentos en el disco.
/// Un doble que cuente invocaciones diría que el commit «se llamó»; lo que
/// estas pruebas necesitan afirmar es que el commit NO OCURRIÓ.
///
/// **Por eso el repositorio es de verdad**, en un directorio temporal, como ya
/// hacen `packages/vcs/test/candidato_test` y `entorno_del_candidato_test`. Es
/// más lento y es lo correcto: contra un doble de `git`, «no se commiteó» solo
/// probaría que el doble hace lo que se le programó.
///
/// **Y los dobles que ya existen se reusan**: `SalidaDePrFalsa`,
/// `FuenteDeCredencialFalsa`, `PoliticaDeArtefactosFalsa` y
/// `ObservadorDeAlcanceFalso` de `plugin_fake`, y `Paso` y `EntornoFalso` de
/// `apoyo`. Un doble nuevo al lado de uno que ya existe es una segunda
/// definición del mismo contrato, y divergen. `EntornoFalso` vive en `apoyo` y
/// no en `plugin_fake` porque agregarle un doble de ese puerto es una decisión
/// de aquel paquete, no de una suite; y no vive acá porque la suite del comando
/// necesita el mismo, y dos copias del mismo doble divergen igual.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

import '../apoyo.dart';

/// El archivo de la rebanada. Está versionado desde el primer commit y la
/// corrida lo modifica: sin un cambio contra la base, `prepareCandidate`
/// rechaza la rebanada —y con razón—.
const _archivo = 'lib/a.txt';

/// La clave de la credencial. **La elige quien compone**, y por eso viaja como
/// dato: `ship` no sabe quién es la forja.
const _clave = 'CREDENCIAL_DE_LA_FORJA';

/// Una ruta sucia que no es de la rebanada. Queda en el árbol de trabajo, no
/// se publica y no entra en el artefacto: por eso la previsualización la
/// nombra aparte y con su cuenta.
const _ajeno = 'ajeno.txt';

/// Una línea que el detector de secretos reconoce por el NOMBRE al que se
/// asigna, no por la forma del valor: no se parece a la credencial de ningún
/// proveedor y aun así es exactamente lo que no se commitea.
const _lineaConSecreto = 'password = "no-deberia-estar-acá-nunca"';

/// El repositorio REAL, que además anota qué rebanada se le pidió y devuelve
/// un candidato que anota lo suyo.
///
/// **Extiende en vez de doblar.** Todo lo que hace `git` lo sigue haciendo
/// `git`: acá no hay ninguna respuesta programada, solo un registro de lo que
/// pasó por el medio.
class RepoQueAnota extends RepositorioGit {
  RepoQueAnota({
    required super.directorio,
    required super.politica,
    this.lanzaAlLiberar = false,
  });

  /// Se le traslada al candidato que se prepare: liberar va a fallar.
  final bool lanzaAlLiberar;

  PullRequestSlice? rebanadaQueSePidio;
  CandidatoQueAnota? candidato;

  @override
  Future<PreparedCandidate> prepareCandidate(PullRequestSlice slice) async {
    rebanadaQueSePidio = slice;
    return candidato = CandidatoQueAnota(await super.prepareCandidate(slice))
      ..lanzaAlLiberar = lanzaAlLiberar;
  }
}

/// El candidato REAL, con el registro de lo que informó y de si lo liberaron.
class CandidatoQueAnota implements PreparedCandidate {
  final PreparedCandidate _real;

  /// Cada alteración que este candidato DEVOLVIÓ, por ruta. **No es lo que la
  /// superficie recibió**: entre una cosa y la otra está la acumulación por
  /// ruta que hace la orquestación, y quien lea este registro no puede saber
  /// si ese argumento llegó. Lo que la superficie recibió se observa por su
  /// producto —el artefacto publicado—, nunca por una sonda en producción.
  final Map<String, AlteracionDelCandidato> alteracionesInformadas = {};

  bool liberado = false;

  /// Liberar falla. Pasa de verdad: borrar un directorio puede fallar por
  /// permisos o porque otro proceso lo tiene tomado.
  bool lanzaAlLiberar = false;

  CandidatoQueAnota(this._real);

  @override
  CandidateIdentity get identity => _real.identity;

  @override
  String get root => _real.root;

  @override
  List<String> get changedPaths => _real.changedPaths;

  @override
  List<RutaNoMaterializada> get noMaterializadas => _real.noMaterializadas;

  @override
  Future<List<AlteracionDelCandidato>> alteraciones() async {
    final informadas = await _real.alteraciones();
    for (final a in informadas) {
      alteracionesInformadas[a.ruta] = a;
    }
    return informadas;
  }

  @override
  Future<void> exigirSinSecretos() => _real.exigirSinSecretos();

  @override
  Future<String> createRevision() => _real.createRevision();

  @override
  Future<CommitOutcome> applyRevision() => _real.applyRevision();

  @override
  Future<void> dispose() async {
    liberado = true;
    await _real.dispose();
    if (lanzaAlLiberar) {
      throw const FileSystemException('no se pudo borrar el temporal');
    }
  }
}

/// El mundo de una corrida: un repositorio de verdad y los dobles de todos los
/// colaboradores que `correrShip` recibe.
///
/// **Registra hechos, no llamadas.** Qué objetos quedaron en el almacén real,
/// qué commits tiene la rama, qué pull requests se pidieron, qué temporales
/// sobrevivieron, qué documento quedó en el disco. Nada de eso se deduce de
/// haber contado invocaciones.
class MundoDePrueba {
  /// La rebanada trae un secreto. Es lo que permite fijar que el hallazgo gana
  /// sobre la confirmación, que hasta esta rebanada no se podía alcanzar.
  final bool conSecreto;

  /// Qué estado produce la cascada.
  final EstadoDeCorrida estado;

  /// Alguien más commitea en la rama mientras la corrida verifica. Es la
  /// ventana real: verificar tarda, y nada congela el repositorio entretanto.
  final bool headSeMueveAntesDelCas;

  /// Quien corre se cambia de rama mientras la corrida verifica. **Es la OTRA
  /// causa de no aplicar, y no es la misma**: la rama de la corrida no se
  /// movió, no se intenta ningún compare-and-swap, y el `HEAD` observado es
  /// el de otra rama. Es alcanzable porque la promoción comprueba que la rama
  /// de ahora sea la de antes y una cascada real dura lo suficiente.
  final bool laRamaCambiaAntesDelCas;

  /// La cascada lanza en vez de devolver un desenlace. No es un paso roto —eso
  /// la cascada lo convierte en `Broken`—: es el observador de alcance
  /// fallando, que sí sube.
  final bool laCascadaExplota;

  /// Alguien escribe en el árbol del candidato entre la derivación y la
  /// cascada.
  final bool candidatoAlterado;

  /// No hay credencial para la forja. Es lo que el preflight rechaza, y el
  /// rechazo sale por excepción: no hay corrida que describir.
  final bool sinCredencial;

  /// El documento de esta corrida ya está en el índice de `git`. Entonces
  /// `check-ignore` lo declara NO ignorado —una ruta seguida no la ignora
  /// ninguna regla— y terminaría commiteado dentro del pull request.
  final bool documentoVersionado;

  /// Ya hay un `.gitignore` en el directorio de corridas, con un contenido
  /// que este mecanismo no escribiría. No se pisa: puede ser deliberado.
  final bool gitignoreAjeno;

  /// El árbol de trabajo tiene una ruta sucia que NO es de la rebanada. Es lo
  /// que la previsualización tiene que nombrar con su cuenta: quien confirma
  /// es la única persona a la que se le puede mostrar, porque el revisor
  /// remoto nunca la ve.
  final bool conCambioAjeno;

  /// Alguien escribe en el árbol del candidato MIENTRAS se deriva el entorno,
  /// y lo deshace antes de la cascada. **Solo la primera lectura de
  /// integridad lo ve**: para la segunda, el árbol volvió a coincidir.
  final bool alteracionSoloAntesDeLaCascada;

  /// Liberar el candidato falla. Es lo que distingue una limpieza que corre de
  /// una limpieza que además decide qué excepción ve quien corrió `ship`.
  final bool alLiberarFalla;

  late final Directory _raiz;
  late final RepoQueAnota repo;
  late final RegistroDeCorridas registro;

  late final EntornoFalso ambiente;
  final SalidaDePrFalsa forja = SalidaDePrFalsa(
    respuesta: PullRequestOpen(url: 'https://forja.invalida/pr/1'),
  );

  /// Los commits que hizo ESTE mundo, no la corrida. Se descuentan: si no,
  /// la interferencia que el mundo provoca contaría como trabajo de `ship`.
  final Set<String> _mios = {};

  Set<String> _objetosAntes = const {};
  String _cabezaEsperada = '';

  /// Cada texto que la corrida mandó al canal de salida. **Es el producto de
  /// un ensayo**: sin canal propio, `--dry-run` no imprimía nada y nadie
  /// aguas arriba podía taparlo, porque lo único que recibe es el desenlace.
  final List<String> mostrado = [];

  /// Lo que quedó, una vez que la corrida terminó —o explotó—.
  Set<String> objetosPersistentes = const {};
  List<String> commits = const [];
  List<String> temporalesQueQuedaron = const [];
  List<String> proyeccionesEscritas = const [];
  DocumentoDeCorrida? documento;
  bool ramaSeMovio = false;

  MundoDePrueba({
    this.conSecreto = false,
    this.estado = EstadoDeCorrida.verde,
    this.headSeMueveAntesDelCas = false,
    this.laRamaCambiaAntesDelCas = false,
    this.laCascadaExplota = false,
    this.candidatoAlterado = false,
    this.sinCredencial = false,
    this.documentoVersionado = false,
    this.gitignoreAjeno = false,
    this.conCambioAjeno = false,
    this.alteracionSoloAntesDeLaCascada = false,
    this.alLiberarFalla = false,
  }) {
    ambiente = EntornoFalso(
      alDerivar: alteracionSoloAntesDeLaCascada
          ? (raiz) => File(
              '$raiz/$_archivo',
            ).writeAsStringSync('alguien escribió mientras se derivaba\n')
          : null,
    );
    _raiz = Directory.systemTemp.createTempSync('ship_orquestacion_');
    addTearDown(() => _raiz.deleteSync(recursive: true));
    _escribir(_archivo, 'antes\n');
    _git(['init', '--initial-branch=main', '.']);
    _git(['config', 'user.email', 'p@p']);
    _git(['config', 'user.name', 'prueba']);
    _git(['add', '-A']);
    _git(['commit', '-m', 'base']);
    _git(['switch', '-c', 'trabajo']);
    repo = RepoQueAnota(
      directorio: _raiz.path,
      politica: PoliticaDeArtefactosFalsa(),
      lanzaAlLiberar: alLiberarFalla,
    );
    registro = RegistroDeCorridas(raiz: '${_raiz.path}/.shipflow');
    if (documentoVersionado) {
      // El índice es lo que cuenta: se agrega y se borra del árbol, así que
      // la ruta queda SEGUIDA sin dejar en el disco un documento que no se
      // puede leer. `check-ignore` no ignora una ruta seguida.
      _escribir('.shipflow/runs/r-1.json', '{}\n');
      _git(['add', '-f', '.shipflow/runs/r-1.json']);
      File('${_raiz.path}/.shipflow/runs/r-1.json').deleteSync();
    }
    if (conCambioAjeno) {
      _escribir(_ajeno, 'trabajo de al lado, sin commitear\n');
    }
    if (gitignoreAjeno) {
      _escribir(
        '.shipflow/.gitignore',
        '# lo puso otra persona, a propósito\n',
      );
    }
  }

  String _git(List<String> args) => _gitCrudo(args).trim();

  /// Lo mismo, **sin recortar por la izquierda**. `git status --porcelain`
  /// codifica el estado en las dos primeras columnas, y la primera suele ser
  /// un espacio: recortar la salida entera se come el espacio inicial de la
  /// PRIMERA línea y corre su ruta un carácter. Con eso, la ruta de la
  /// rebanada salía mutilada, no coincidía consigo misma y la rebanada se
  /// contaba como cambio ajeno. No se veía porque `confirmar` era nulo y esta
  /// función nunca corría.
  String _gitCrudo(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: _raiz.path);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
    }
    return (r.stdout as String).trimRight();
  }

  void _escribir(String ruta, String contenido) {
    final f = File('${_raiz.path}/$ruta');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  /// Los objetos sueltos del almacén REAL. Es la medida de «no dejó nada»: el
  /// candidato escribe en un almacén temporal hasta que alguien autoriza.
  Set<String> _objetos() {
    final almacen = Directory('${_raiz.path}/.git/objects');
    if (!almacen.existsSync()) return const {};
    return {
      for (final e in almacen.listSync(recursive: true))
        if (e is File && !e.path.contains('/info/')) e.path,
    };
  }

  /// La cascada de esta corrida, y —según el interruptor— la interferencia que
  /// ocurre justo acá: entre que el candidato quedó fijado y que el
  /// compare-and-swap corre.
  Cascada _cascada(String raizDelCandidato) {
    if (alteracionSoloAntesDeLaCascada) {
      // Se deshace, byte por byte: a partir de acá el árbol vuelve a coincidir
      // con la revisión que el candidato fijó, y la segunda lectura no tiene
      // nada que informar.
      File(
        '$raizDelCandidato/$_archivo',
      ).writeAsStringSync(_contenidoDeLaRebanada);
    }
    if (candidatoAlterado) {
      File(
        '$raizDelCandidato/$_archivo',
      ).writeAsStringSync('alguien escribió acá\n');
    }
    if (headSeMueveAntesDelCas) {
      _escribir('otro.txt', 'de otra persona\n');
      _git(['add', 'otro.txt']);
      _git(['commit', '-m', 'trabajo ajeno']);
      _cabezaEsperada = _git(['rev-parse', 'refs/heads/trabajo']);
      _mios.add(_cabezaEsperada);
    }
    if (laRamaCambiaAntesDelCas) {
      // Crear la rama nueva y ponerla NO toca el árbol de trabajo —queda en
      // el mismo commit—, así que lo único que cambia es cuál está puesta:
      // exactamente lo que `applyRevision` comprueba antes de mover nada.
      _git(['switch', '-c', 'otra']);
    }
    if (laCascadaExplota) {
      // Un sujeto que la tabla no declara: el observador falso se niega a
      // clasificar por su cuenta y lanza. Eso sube por `Cascada.correr`, que
      // solo convierte en `Broken` lo que lanza un PASO.
      return Cascada(
        _pasos,
        observador: ObservadorDeAlcanceFalso(observados: {}),
      );
    }
    return Cascada(
      _pasos,
      observador: ObservadorDeAlcanceFalso(
        observados: {
          _archivo: ObservedSubject(subject: _archivo, ofStack: true, files: 1),
        },
      ),
    );
  }

  List<Verifier> get _pasos => switch (estado) {
    EstadoDeCorrida.verde => [Paso.verde('doble')],
    EstadoDeCorrida.rojo => [Paso.rojo('doble')],
    EstadoDeCorrida.noConcluyente => [Paso.ciego('doble')],
    EstadoDeCorrida.errorInterno => [
      Paso('doble', lanza: StateError('el instrumento se rompió')),
    ],
  };

  /// Las rutas sucias que no son de la rebanada. **Se miden, no se asumen**:
  /// la previsualización las imprime con su cuenta, y un cero sin haber mirado
  /// es una afirmación sobre lo que queda afuera.
  Future<List<String>> _cambiosAjenos() async => [
    for (final l in _gitCrudo(['status', '--porcelain']).split('\n'))
      if (l.length > 3 && l.substring(3) != _archivo) l.substring(3),
  ];

  Future<ShipOutcome> correr({
    bool dryRun = false,
    bool yes = false,
    bool allowIncomplete = false,
    String runId = 'r-1',
    Future<bool> Function(String previsualizacion)? confirmar,
    bool sinIntencion = false,
  }) async {
    _escribir(_archivo, _contenidoDeLaRebanada);
    _objetosAntes = _objetos();
    final cabezaAlEmpezar = _git(['rev-parse', 'refs/heads/trabajo']);
    _cabezaEsperada = cabezaAlEmpezar;

    try {
      return await correrShip(
        entrada: EntradaDeShip(
          intent: sinIntencion ? null : 'publicar el cambio',
          archivos: const [_archivo],
          rutaDeLaRebanada: null,
          branch: null,
          base: 'main',
          dryRun: dryRun,
          yes: yes,
          allowIncomplete: allowIncomplete,
        ),
        runId: runId,
        repo: repo,
        ambiente: ambiente,
        construirCascada: _cascada,
        controles: {for (final p in _pasos) p.id: p},
        credenciales: sinCredencial
            ? const FuenteDeCredencialFalsa(credenciales: {})
            : const FuenteDeCredencialFalsa(
                credenciales: {_clave: Credential('un-secreto', label: _clave)},
              ),
        claveDeCredencial: _clave,
        forja: forja,
        registro: registro,
        ramaActual: 'trabajo',
        cambiosAjenos: _cambiosAjenos,
        confirmar: confirmar,
        mostrar: mostrado.add,
      );
    } finally {
      await _anotarLoQueQuedo(cabezaAlEmpezar, runId);
    }
  }

  /// **En el `finally`**: un camino que termina en excepción deja hechos
  /// igual, y son justamente los que una de estas pruebas mide.
  Future<void> _anotarLoQueQuedo(String cabezaAlEmpezar, String runId) async {
    objetosPersistentes = _objetos().difference(_objetosAntes);
    final cabezaAhora = _git(['rev-parse', 'refs/heads/trabajo']);
    ramaSeMovio = cabezaAhora != _cabezaEsperada;
    commits = [
      for (final c in _git([
        'rev-list',
        '$cabezaAlEmpezar..refs/heads/trabajo',
      ]).split('\n'))
        if (c.trim().isNotEmpty && !_mios.contains(c.trim())) c.trim(),
    ];
    // El almacén temporal del candidato es el padre de su raíz: así lo arma
    // `vcs`, y así lo deriva su propia suite.
    final raizDelCandidato = ambiente.raizDelCandidato;
    temporalesQueQuedaron = [
      if (raizDelCandidato != null &&
          Directory(raizDelCandidato).parent.existsSync())
        Directory(raizDelCandidato).parent.path,
    ];
    final corridas = Directory('${registro.raiz}/runs');
    proyeccionesEscritas = [
      if (corridas.existsSync())
        for (final e in corridas.listSync(recursive: true))
          if (e is File) e.path,
    ];
    documento = await registro.leer(runId);
  }

  /// Lo que el contenido de la rebanada dice en esta corrida.
  String get _contenidoDeLaRebanada =>
      conSecreto ? '$_lineaConSecreto\n' : 'después\n';

  /// Las alteraciones que el candidato DEVOLVIÓ. El nombre dice exactamente
  /// eso: qué llegó a `derivarSuperficie` se observa por el artefacto que la
  /// corrida publicó, que es su único producto visible.
  List<AlteracionDelCandidato> get alteracionesQueDevolvioElCandidato =>
      repo.candidato?.alteracionesInformadas.values.toList() ?? const [];

  /// La superficie que la corrida publicó, tal como viajó en el artefacto.
  /// **Es el argumento de `derivarSuperficie` visto por su producto**, no una
  /// sonda: si la llamada recibiera una lista vacía, acá no habría nada.
  SuperficieDeVerificacion get superficiePublicada =>
      forja.recibidas.single.draft.artefacto.superficie;

  List<PullRequestRequest> get pullRequests => forja.recibidas;

  PullRequestSlice? get rebanadaQueSePidio => repo.rebanadaQueSePidio;
}

void main() {
  test('--dry-run no deja NADA: ni objetos, ni commit, ni PR', () async {
    final mundo = MundoDePrueba();
    final r = await mundo.correr(dryRun: true);
    expect(r, isA<NoIntentado>());
    expect((r as NoIntentado).causa, CausaDeNoIntento.previewOnly);
    expect(mundo.objetosPersistentes, isEmpty);
    expect(mundo.commits, isEmpty);
    expect(mundo.pullRequests, isEmpty);
    expect(mundo.temporalesQueQuedaron, isEmpty);
  });

  test('un ensayo SIN --yes es previewOnly, y no pide confirmar nada', () async {
    // La precedencia de la fábrica, vista desde la orquestación. Antes se
    // alcanzaba solo porque el llamador declaraba `seConfirmo` verdadero en un
    // ensayo: un hecho falso viajando hacia la fábrica que existe para
    // derivarlos. Ahora el hecho viaja sin adornos y la causa la decide el
    // orden.
    final mundo = MundoDePrueba();
    final r = await mundo.correr(dryRun: true, yes: false);
    expect((r as NoIntentado).causa, CausaDeNoIntento.previewOnly);
    // Y el consejo: a un ensayo no se le dice que vuelva a correrlo con
    // `--yes`, porque no pidió escribir nada.
    expect(accionDe(r), isNull);
  });

  test('--dry-run IMPRIME la previsualización: es su único producto', () async {
    // El modo cuyo único producto es el preview no imprimía nada, y nadie
    // aguas arriba podía taparlo: la tarea 10 solo recibe el `ShipOutcome`,
    // que no lleva ni artefacto ni superficie.
    final mundo = MundoDePrueba();
    await mundo.correr(dryRun: true);
    expect(mundo.mostrado, hasLength(1));
    expect(mundo.mostrado.single, contains('trabajo → main'));
  });

  test('sin nada que autorizar no se construye ni se muestra nada', () async {
    // El ahorro que el código ya tenía y que separar las tres cosas no puede
    // regalar: con un secreto o con la compuerta cerrada el desenlace ya está
    // decidido, así que armar el texto sería trabajo para tirar.
    final conSecreto = MundoDePrueba(conSecreto: true);
    await conSecreto.correr(dryRun: true);
    expect(conSecreto.mostrado, isEmpty);

    final compuertaCerrada = MundoDePrueba(estado: EstadoDeCorrida.rojo);
    await compuertaCerrada.correr(dryRun: true);
    expect(compuertaCerrada.mostrado, isEmpty);
  });

  test('sin --yes se comporta como una previsualización', () async {
    final mundo = MundoDePrueba();
    final r = await mundo.correr(yes: false);
    expect((r as NoIntentado).causa, CausaDeNoIntento.confirmationMissing);
    expect(mundo.commits, isEmpty);
  });

  test('un secreto se ve SIN --yes, y gana sobre la confirmación', () async {
    // Es la precedencia que el diseño fija y que hasta esta rebanada no se
    // podía alcanzar, porque el escaneo vivía en el camino de escritura.
    final mundo = MundoDePrueba(conSecreto: true);
    final r = await mundo.correr(yes: false);
    expect((r as NoIntentado).causa, CausaDeNoIntento.secretDetected);
    expect(mundo.commits, isEmpty);
  });

  test('rojo sin --allow-incomplete no publica, y con él sí', () async {
    expect(
      ((await MundoDePrueba(estado: EstadoDeCorrida.rojo).correr(yes: true))
              as NoIntentado)
          .causa,
      CausaDeNoIntento.verificationGate,
    );
    expect(
      await MundoDePrueba(
        estado: EstadoDeCorrida.rojo,
      ).correr(yes: true, allowIncomplete: true),
      isA<Publicado>(),
    );
  });

  test('el arnés roto NUNCA publica, ni con --allow-incomplete', () async {
    final mundo = MundoDePrueba(estado: EstadoDeCorrida.errorInterno);
    final r = await mundo.correr(yes: true, allowIncomplete: true);
    expect(r, isA<NoIntentado>());
    expect(mundo.commits, isEmpty);
    expect(mundo.pullRequests, isEmpty);
  });

  test('el CAS rechazado da NoAplicado por baseMovida, y la rama no se '
      'movió', () async {
    final mundo = MundoDePrueba(headSeMueveAntesDelCas: true);
    final r = await mundo.correr(yes: true);
    expect(r, isA<NoAplicado>());
    expect((r as NoAplicado).causa, CausaDeNoAplicacion.baseMovida);
    expect(mundo.ramaSeMovio, isFalse);
    // **Y el documento quedó sellado.** Sin esta aserción, devolver el
    // desenlace sin persistirlo pasaba: el documento se quedaría en
    // `prepared`, afirmando una corrida en curso que ya terminó.
    expect(mundo.documento!.estado, EstadoDelDocumento.notApplied);
    expect(mundo.documento!.desenlace, isA<NoAplicado>());
  });

  test('cambiarse de rama da NoAplicado por ramaCambiada, y el desenlace NO '
      'dice que la rama avanzó', () async {
    // **La otra causa, y la que el desenlace estaba tapando.** Acá no se
    // intenta ningún compare-and-swap: la promoción comprueba primero que la
    // rama puesta sea la de antes. El `HEAD` observado es el de la OTRA rama,
    // así que el consejo de «la rama avanzó a …, volvé a correr» reconstruiría
    // el candidato sobre esa otra y commitearía ahí.
    final mundo = MundoDePrueba(laRamaCambiaAntesDelCas: true);
    final r = await mundo.correr(yes: true);
    expect(r, isA<NoAplicado>());
    expect((r as NoAplicado).causa, CausaDeNoAplicacion.ramaCambiada);
    expect(mundo.ramaSeMovio, isFalse);
    expect(mundo.commits, isEmpty);
    expect(mundo.pullRequests, isEmpty);
    expect(mundo.documento!.estado, EstadoDelDocumento.notApplied);
    // Y lo que sale por la salida y por la acción siguiente dice la verdad de
    // ESTA causa: la rama de la corrida no avanzó a ningún lado.
    expect(accionDe(r), isNot(contains('avanzó')));
    expect(accionDe(r), contains('--branch'));
  });

  test(
    'el camino feliz publica y deja el documento en su estado final',
    () async {
      final mundo = MundoDePrueba();
      final r = await mundo.correr(yes: true);
      expect(r, isA<Publicado>());
      expect(mundo.documento!.estado, EstadoDelDocumento.publicationComplete);
    },
  );

  test('la limpieza corre AUNQUE el camino termine en excepción', () async {
    // **Apretado al tipo.** `anything` acepta cualquier excepción, incluida
    // una de `asegurarGitignore`, que no es el camino que esta prueba dice
    // cubrir: el observador de alcance se niega a clasificar un sujeto que no
    // le declararon y eso sube por la cascada.
    final mundo = MundoDePrueba(laCascadaExplota: true);
    await expectLater(mundo.correr(yes: true), throwsArgumentError);
    expect(mundo.temporalesQueQuedaron, isEmpty);
  });

  test('un fallo al liberar NO tapa el fallo que ya venía subiendo', () async {
    // Una excepción lanzada desde un `finally` reemplaza a la que estaba en
    // vuelo: sin la guarda, quien rompió la cascada veía el fallo del borrado
    // de un temporal y no el suyo.
    final mundo = MundoDePrueba(laCascadaExplota: true, alLiberarFalla: true);
    await expectLater(mundo.correr(yes: true), throwsArgumentError);
    expect(mundo.repo.candidato!.liberado, isTrue);
  });

  test('sin nada en vuelo, el fallo al liberar SÍ sube', () async {
    // El otro lado: si la guarda se tragara siempre el fallo de la limpieza,
    // un temporal que no se puede borrar desaparecería en silencio.
    final mundo = MundoDePrueba(alLiberarFalla: true);
    await expectLater(
      mundo.correr(yes: true),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'la rebanada se identifica como `<runId>/1`, no como el runId',
    () async {
      // Hoy hay UNA rebanada por corrida, pero el modelo final admite varias.
      // Igualar las dos identidades fusiona dos cosas que van a divergir.
      final mundo = MundoDePrueba();
      await mundo.correr(yes: true, runId: 'r-9');
      expect(mundo.rebanadaQueSePidio!.id, 'r-9/1');
    },
  );

  test('el paso 14 escribe las proyecciones, y son LOCALES', () async {
    // El JSON de la revisión es local y está ignorado por git: el revisor
    // remoto no puede abrirlo, y por eso el cuerpo del PR es autosuficiente.
    // Si alguna vez tuviera que estar remoto, se publica por un mecanismo
    // explícito, nunca por una ruta local.
    final mundo = MundoDePrueba();
    await mundo.correr(yes: true, runId: 'r-14');
    // **Por su nombre, y no solo por el barrido.** El barrido pasa por el
    // documento que `RegistroDeCorridas.escribir` ya dejó: si se borra la
    // llamada que proyecta la revisión, sigue devolviendo algo. Lo que el
    // barrido sí fija es el `.gitignore`, más abajo.
    expect(
      mundo.proyeccionesEscritas,
      contains(endsWith('r-14.revision.json')),
    );
    for (final ruta in mundo.proyeccionesEscritas) {
      expect(
        await corridasIgnoradas(mundo.repo, ruta),
        isTrue,
        reason: '$ruta no está ignorada: terminaría commiteada en el PR',
      );
    }
  });

  group('el camino de `confirmar`', () {
    // Hasta esta ronda la suite pasaba `confirmar: null` siempre, así que por
    // corto-circuito ni la previsualización ni los cambios ajenos se
    // ejecutaban: borrar el colaborador `cambiosAjenos` de la firma no ponía
    // roja ninguna prueba.

    test(
      'un «no» deja la corrida sin confirmar, y sin escribir nada',
      () async {
        final mundo = MundoDePrueba(conCambioAjeno: true);
        String? loQueLeYO;
        final r = await mundo.correr(
          confirmar: (texto) async {
            loQueLeYO = texto;
            return false;
          },
        );
        expect((r as NoIntentado).causa, CausaDeNoIntento.confirmationMissing);
        expect(mundo.commits, isEmpty);
        expect(mundo.pullRequests, isEmpty);
        // Y lo que se le mostró llevaba los cambios ajenos REALES: sin ese
        // colaborador, quien confirma no sabe qué queda afuera.
        expect(loQueLeYO, contains(_ajeno));
        expect(loQueLeYO, contains('cambios ajenos a la rebanada (1)'));
      },
    );

    test('un «sí» autoriza la escritura y la corrida publica', () async {
      final mundo = MundoDePrueba();
      final r = await mundo.correr(confirmar: (_) async => true);
      expect(r, isA<Publicado>());
      expect(mundo.commits, isNotEmpty);
      expect(mundo.pullRequests, hasLength(1));
    });
  });

  group('las cuatro salidas por excepción, que NO son desenlace', () {
    // Son el contrato que la tarea 10 tiene que consumir para traducirlas a
    // un código de proceso. No hay `ShipOutcome` que las diga: una corrida que
    // no llegó a existir no tiene desenlace, y fabricarle una quinta causa
    // volvería inalcanzable la fila «gate con errorInterno».

    test('sin intención se lanza UsoInvalido, y dice qué pasar', () async {
      final mundo = MundoDePrueba();
      await expectLater(
        mundo.correr(yes: true, sinIntencion: true),
        throwsA(
          isA<UsoInvalido>().having(
            (e) => e.queHacer,
            'queHacer',
            contains('--intent'),
          ),
        ),
      );
      // Y cero escrituras: ni siquiera se preparó un candidato.
      expect(mundo.commits, isEmpty);
      expect(mundo.objetosPersistentes, isEmpty);
    });

    test('el preflight rechazado lleva el fallo ENTERO', () async {
      // No una copia del mensaje: la causa, el detalle y el qué hacer, para
      // que quien lo atrape no tenga que volver a derivar nada.
      final mundo = MundoDePrueba(sinCredencial: true);
      await expectLater(
        mundo.correr(yes: true),
        throwsA(
          isA<PreflightRechazado>().having(
            (e) => e.fallo.causa,
            'fallo.causa',
            CausaDePreflight.credencialAusente,
          ),
        ),
      );
      expect(mundo.commits, isEmpty);
      expect(mundo.objetosPersistentes, isEmpty);
    });

    test(
      'un documento de corrida que git NO ignora detiene la corrida',
      () async {
        // Una ruta seguida no la ignora ninguna regla, así que el documento
        // terminaría commiteado dentro del pull request: exactamente lo
        // contrario de lo que el mecanismo promete.
        final mundo = MundoDePrueba(documentoVersionado: true);
        await expectLater(
          mundo.correr(yes: true),
          throwsA(
            isA<CorridasNoIgnoradas>().having(
              (e) => e.ruta,
              'ruta',
              endsWith('.shipflow/runs/r-1.json'),
            ),
          ),
        );
        expect(mundo.commits, isEmpty);
        expect(mundo.pullRequests, isEmpty);
      },
    );

    test(
      'un .gitignore ajeno no se pisa: sube desde asegurarGitignore',
      () async {
        final mundo = MundoDePrueba(gitignoreAjeno: true);
        await expectLater(
          mundo.correr(yes: true),
          throwsA(
            isA<GitignoreAjeno>().having(
              (e) => e.ruta,
              'ruta',
              endsWith('.shipflow/.gitignore'),
            ),
          ),
        );
        expect(mundo.commits, isEmpty);
        expect(mundo.pullRequests, isEmpty);
      },
    );
  });

  test('la superficie recibe las alteraciones REALES del candidato', () async {
    // El residuo que la rebanada de la superficie dejó parqueado: hasta hoy
    // se la llamaba con la lista vacía, y vacía significa «comprobado e
    // intacto», no «no se comprobó».
    final mundo = MundoDePrueba(candidatoAlterado: true);
    final r = await mundo.correr(yes: true);
    expect(r, isA<NoIntentado>());
    expect(mundo.alteracionesQueDevolvioElCandidato, isNotEmpty);
  });

  test(
    'la alteración viaja al artefacto que se publica, no solo al estado',
    () async {
      // La aserción de arriba mira lo que el candidato DEVOLVIÓ, y con
      // `alteraciones: const []` en la llamada a `derivarSuperficie` seguiría
      // verde: lo que la redime es el desenlace. Acá se mira el argumento por
      // su producto — la superficie que viajó en el artefacto publicado—, que
      // es lo único que un revisor remoto llega a leer.
      final mundo = MundoDePrueba(candidatoAlterado: true);
      expect(
        await mundo.correr(yes: true, allowIncomplete: true),
        isA<Publicado>(),
      );
      expect(
        mundo.superficiePublicada.requiereCriterio
            .where((e) => e.motivo == MotivoDeCriterio.candidatoAlterado)
            .map((e) => e.sujeto),
        contains(_archivo),
      );
      // Y con la alteración a la vista, nada queda dado por cubierto: no se
      // sabe cuál de los dos árboles vio cada control.
      expect(mundo.superficiePublicada.cubierto, isEmpty);
    },
  );

  test('la PRIMERA lectura de integridad cuenta: se acumula por ruta', () async {
    // La alteración ocurre mientras se deriva el entorno y se deshace antes
    // de la cascada, así que la SEGUNDA lectura no ve nada. Sin la primera, la
    // corrida publicaría un cambio cuyo árbol dejó de coincidir con el que
    // dice representar en la ventana donde la derivación ya lo había leído.
    final mundo = MundoDePrueba(alteracionSoloAntesDeLaCascada: true);
    final r = await mundo.correr(yes: true);
    expect(r, isA<NoIntentado>());
    expect((r as NoIntentado).causa, CausaDeNoIntento.verificationGate);
    expect(r.verificacion, EstadoDeCorrida.noConcluyente);
    expect(mundo.commits, isEmpty);
    expect(mundo.pullRequests, isEmpty);
  });
}
