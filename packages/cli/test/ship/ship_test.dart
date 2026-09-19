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
/// `ObservadorDeAlcanceFalso` de `plugin_fake`, y `Paso` de `apoyo`. Un doble
/// nuevo al lado de uno que ya existe es una segunda definición del mismo
/// contrato, y divergen. El único que se escribe acá es el del entorno de
/// verificación, porque `plugin_fake` no declara ninguno y agregárselo es una
/// decisión de ese paquete, no de esta prueba.
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

/// Una línea que el detector de secretos reconoce por el NOMBRE al que se
/// asigna, no por la forma del valor: no se parece a la credencial de ningún
/// proveedor y aun así es exactamente lo que no se commitea.
const _lineaConSecreto = 'password = "no-deberia-estar-acá-nunca"';

/// Un entorno de verificación que siempre deriva, y registra sobre qué raíz lo
/// hicieron.
///
/// **No reimplementa nada**: el entorno real corre una toolchain sobre el
/// candidato, y lo que estas pruebas miden no es eso. Lo que sí aporta es el
/// hecho que el mundo necesita para ubicar el almacén temporal del candidato
/// sin que el puerto tenga que exponerlo.
class EntornoFalso implements VerificationEnvironment {
  String? raizDelCandidato;

  @override
  Future<ResultadoDeEntorno> derivar(
    String candidateRoot, {
    required List<String> archivos,
    required Duration presupuesto,
  }) async {
    raizDelCandidato = candidateRoot;
    return EntornoDerivado(
      paquetes: 1,
      raices: 1,
      toolchain: IdentidadDeToolchain(
        version: const QuotedText('doble 0.0.0', source: 'prueba'),
      ),
    );
  }
}

/// El repositorio REAL, que además anota qué rebanada se le pidió y devuelve
/// un candidato que anota lo suyo.
///
/// **Extiende en vez de doblar.** Todo lo que hace `git` lo sigue haciendo
/// `git`: acá no hay ninguna respuesta programada, solo un registro de lo que
/// pasó por el medio.
class RepoQueAnota extends RepositorioGit {
  RepoQueAnota({required super.directorio, required super.politica});

  PullRequestSlice? rebanadaQueSePidio;
  CandidatoQueAnota? candidato;

  @override
  Future<PreparedCandidate> prepareCandidate(PullRequestSlice slice) async {
    rebanadaQueSePidio = slice;
    return candidato = CandidatoQueAnota(await super.prepareCandidate(slice));
  }
}

/// El candidato REAL, con el registro de lo que informó y de si lo liberaron.
class CandidatoQueAnota implements PreparedCandidate {
  final PreparedCandidate _real;

  /// Cada alteración que este candidato informó, por ruta. **Es lo que la
  /// superficie recibió**: la orquestación le pasa lo que salió de acá.
  final Map<String, AlteracionDelCandidato> alteracionesInformadas = {};

  bool liberado = false;

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

  /// La cascada lanza en vez de devolver un desenlace. No es un paso roto —eso
  /// la cascada lo convierte en `Broken`—: es el observador de alcance
  /// fallando, que sí sube.
  final bool laCascadaExplota;

  /// Alguien escribe en el árbol del candidato entre la derivación y la
  /// cascada.
  final bool candidatoAlterado;

  late final Directory _raiz;
  late final RepoQueAnota repo;
  late final RegistroDeCorridas registro;

  final EntornoFalso ambiente = EntornoFalso();
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
    this.laCascadaExplota = false,
    this.candidatoAlterado = false,
  }) {
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
    );
    registro = RegistroDeCorridas(raiz: '${_raiz.path}/.shipflow');
  }

  String _git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: _raiz.path);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
    }
    return (r.stdout as String).trim();
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
    for (final l in _git(['status', '--porcelain']).split('\n'))
      if (l.trim().isNotEmpty && l.substring(3) != _archivo) l.substring(3),
  ];

  Future<ShipOutcome> correr({
    bool dryRun = false,
    bool yes = false,
    bool allowIncomplete = false,
    String runId = 'r-1',
    Future<bool> Function(String previsualizacion)? confirmar,
  }) async {
    _escribir(_archivo, conSecreto ? '$_lineaConSecreto\n' : 'después\n');
    _objetosAntes = _objetos();
    final cabezaAlEmpezar = _git(['rev-parse', 'refs/heads/trabajo']);
    _cabezaEsperada = cabezaAlEmpezar;

    try {
      return await correrShip(
        entrada: EntradaDeShip(
          intent: 'publicar el cambio',
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
        credenciales: const FuenteDeCredencialFalsa(
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

  /// Las alteraciones que la superficie recibió: las que el candidato informó.
  List<AlteracionDelCandidato> get superficieRecibio =>
      repo.candidato?.alteracionesInformadas.values.toList() ?? const [];

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

  test('el CAS rechazado da NoAplicado y la rama no se movió', () async {
    final mundo = MundoDePrueba(headSeMueveAntesDelCas: true);
    final r = await mundo.correr(yes: true);
    expect(r, isA<NoAplicado>());
    expect(mundo.ramaSeMovio, isFalse);
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
    final mundo = MundoDePrueba(laCascadaExplota: true);
    await expectLater(mundo.correr(yes: true), throwsA(anything));
    expect(mundo.temporalesQueQuedaron, isEmpty);
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
    await mundo.correr(yes: true);
    expect(mundo.proyeccionesEscritas, isNotEmpty);
    for (final ruta in mundo.proyeccionesEscritas) {
      expect(
        await corridasIgnoradas(mundo.repo, ruta),
        isTrue,
        reason: '$ruta no está ignorada: terminaría commiteada en el PR',
      );
    }
  });

  test('la superficie recibe las alteraciones REALES del candidato', () async {
    // El residuo que la rebanada de la superficie dejó parqueado: hasta hoy
    // se la llamaba con la lista vacía, y vacía significa «comprobado e
    // intacto», no «no se comprobó».
    final mundo = MundoDePrueba(candidatoAlterado: true);
    final r = await mundo.correr(yes: true);
    expect(r, isA<NoIntentado>());
    expect(mundo.superficieRecibio, isNotEmpty);
  });
}
