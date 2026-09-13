/// El candidato: **qué bytes exactos se verifican, y que sean los que se
/// commitean**.
///
/// Vive en el mismo library que [RepositorioGit] —por eso es un `part`— porque
/// necesita sus costuras contra `git`, que son privadas a propósito: son la
/// única puerta por la que este paquete habla con la herramienta, y abrirlas
/// convertiría cualquier archivo futuro en un segundo lugar donde se arman
/// invocaciones.
part of 'repositorio.dart';

/// El commit se hizo y **el índice del usuario no quedó al día**.
///
/// Existe con nombre propio porque el llamador tiene que poder distinguirla de
/// un fallo del commit: acá el cambio está en la rama y no se deshace. Viaja
/// dentro de [LocalInconsistent], que es lo que la vuelve inolvidable.
class IndiceDesincronizado implements Exception {
  final String revision;
  final List<String> rutas;
  final String salida;

  const IndiceDesincronizado(this.revision, this.rutas, this.salida);

  @override
  String toString() => 'IndiceDesincronizado($revision): $salida';
}

/// La rebanada trae un secreto, así que no se commitea.
///
/// **Es una [RebanadaNoAplicable]**, para que quien ya la atrapaba la siga
/// atrapando; y lleva los hallazgos como dato, para que quien tenga que
/// ordenar una precedencia entre causas no tenga que leer un mensaje.
class SecretoEnLaRebanada extends RebanadaNoAplicable {
  final List<Secreto> hallazgos;

  SecretoEnLaRebanada(this.hallazgos)
    : super(_razon(hallazgos), hallazgos.first.queHacer);

  static String _razon(List<Secreto> h) => h.length == 1
      ? 'hay ${h.first.queEs} en ${h.first.archivo}:${h.first.linea}.'
      : 'hay ${h.length} secretos en ${h.first.archivo}, el primero '
            '${h.first.queEs} en la línea ${h.first.linea}.';
}

/// Una entrada de `ls-tree -r -z`, ya partida.
///
/// **Se parsea por bytes delimitados por NUL.** `ls-tree -z` no es consumible
/// línea por línea: un nombre con salto de línea partiría un registro en dos, y
/// el candidato dejaría de representar el árbol que dice representar.
class _EntradaDeArbol {
  final String modo;
  final String tipo;
  final String sha;
  final List<int> rutaCruda;

  const _EntradaDeArbol(this.modo, this.tipo, this.sha, this.rutaCruda);
}

class _CandidatoGit implements PreparedCandidate {
  final RepositorioGit _repo;
  final PullRequestSlice _slice;
  final List<String> _rutas;
  final String _rama;
  final Directory _temporal;
  final Directory _objetos;
  final File _indice;

  /// Un índice **aparte** del de preparación, para el control de integridad.
  ///
  /// No se puede reusar el otro: `read-tree` lo sobreescribiría, y ese índice
  /// es el que fijó qué contenido se está verificando.
  final File _indiceDeIntegridad;

  @override
  final CandidateIdentity identity;

  @override
  final String root;

  @override
  final List<String> changedPaths;

  @override
  final List<RutaNoMaterializada> noMaterializadas;

  bool _dispuesto = false;
  bool _promovido = false;

  /// La revisión creada, si `createRevision` ya corrió. **Memoizada**: crearla
  /// dos veces daría dos objetos distintos por la fecha del committer, y el
  /// segundo no sería el que alguien persistió.
  String? _revision;

  _CandidatoGit._({
    required RepositorioGit repo,
    required PullRequestSlice slice,
    required List<String> rutas,
    required String rama,
    required Directory temporal,
    required Directory objetos,
    required File indice,
    required File indiceDeIntegridad,
    required this.identity,
    required this.root,
    required List<String> changedPaths,
    required List<RutaNoMaterializada> noMaterializadas,
  }) : _repo = repo,
       _slice = slice,
       _rutas = rutas,
       _rama = rama,
       _temporal = temporal,
       _objetos = objetos,
       _indice = indice,
       _indiceDeIntegridad = indiceDeIntegridad,
       changedPaths = List.unmodifiable(changedPaths),
       noMaterializadas = List.unmodifiable(noMaterializadas);

  /// El entorno que manda `git` a escribir a un almacén que no es el del
  /// usuario.
  ///
  /// **Se usa siempre, no solo con `--dry-run`.** Está medido que preparar
  /// contra el almacén real deja objetos inalcanzables antes de que nadie haya
  /// confirmado nada, y hay tres caminos que prometen cero efectos: el ensayo,
  /// la ausencia de terminal, y el usuario que dice que no.
  Map<String, String> get _entorno => {
    'GIT_OBJECT_DIRECTORY': _objetos.path,
    'GIT_ALTERNATE_OBJECT_DIRECTORIES': _almacenReal,
    'GIT_INDEX_FILE': _indice.path,
  };

  late final String _almacenReal;

  static Future<_CandidatoGit> preparar(
    RepositorioGit repo,
    PullRequestSlice slice,
  ) async {
    final rutas = await repo._rutasDeLaRebanada(slice);
    await repo._exigirSinConflictos();

    // **La rama tiene que existir y estar puesta.** El candidato se aplica con
    // un compare-and-swap sobre una referencia concreta; con `HEAD` suelto no
    // hay ninguna que mover, y adivinar cuál sería enterrar trabajo ajeno.
    final rama = await repo.ramaActual;
    if (rama.isEmpty) {
      throw const RebanadaNoAplicable(
        'HEAD está suelto, sin ninguna rama.',
        'Poné una rama antes de preparar el candidato: `git switch -c '
            'lo-que-sea`. El cambio se aplica sobre una referencia, y sin '
            'rama no hay ninguna a la que condicionarlo.',
      );
    }

    final cabeza = await repo._git([
      'rev-parse',
      '--verify',
      '--quiet',
      'HEAD',
    ]);
    if (cabeza.exitCode != 0) {
      throw const RebanadaNoAplicable(
        'el repositorio todavía no tiene ningún commit.',
        'El candidato se construye sobre una base y se compara contra ella. '
            'Hacé el primer commit y volvé a intentar.',
      );
    }
    final base = (cabeza.stdout as String).trim();

    final temporal = await Directory.systemTemp.createTemp(
      'shipflow-candidato-',
    );
    final objetos = Directory('${temporal.path}/objetos');
    final indice = File('${temporal.path}/indice');
    final indiceDeIntegridad = File('${temporal.path}/indice-integridad');
    final arbol = Directory('${temporal.path}/arbol');
    await objetos.create();
    await arbol.create();

    try {
      final candidato = _CandidatoGit._(
        repo: repo,
        slice: slice,
        rutas: rutas,
        rama: rama,
        temporal: temporal,
        objetos: objetos,
        indice: indice,
        indiceDeIntegridad: indiceDeIntegridad,
        identity: CandidateIdentity(
          contentRevision: 'pendiente',
          baseRevision: base,
        ),
        root: arbol.path,
        changedPaths: const [],
        noMaterializadas: const [],
      ).._almacenReal = await repo._rutaDeGit('objects');

      return await candidato._fijarYMaterializar(base, arbol);
    } catch (_) {
      await _borrar(temporal);
      rethrow;
    }
  }

  /// Fija el contenido y lo vuelca a disco. Devuelve el candidato definitivo.
  ///
  /// Se construye uno nuevo en vez de mutar el anterior porque [identity] es
  /// final: un candidato cuya identidad se puede reasignar es un candidato que
  /// puede dejar de nombrar lo que se verificó.
  Future<_CandidatoGit> _fijarYMaterializar(
    String base,
    Directory arbol,
  ) async {
    // Los filtros corren UNA vez, acá. Un digest capturado antes de la cascada
    // no sería comparable después: está medido que un filtro no determinista
    // da objetos distintos en dos stagings del mismo archivo sin tocar.
    await _repo._exigir(['read-tree', 'HEAD'], entorno: _entorno);
    await _repo._exigir(['add', '--', ..._rutas], entorno: _entorno);
    final contenido = await _repo._exigir(['write-tree'], entorno: _entorno);

    final cambiadas = _partirNul(
      await _repo._exigirBytes([
        'diff',
        '--name-only',
        '-z',
        base,
        contenido,
      ], entorno: _entorno),
    ).map(_comoRuta).toList()..sort();

    // **La cláusula de [apply] se traslada entera, no se pierde.** Vale en los
    // dos sentidos: ni un archivo de más ni uno declarado que no cambió.
    final pedidas = _rutas.toSet();
    final entran = cambiadas.toSet();
    final demas = entran.difference(pedidas).toList()..sort();
    final faltan = pedidas.difference(entran).toList()..sort();
    if (demas.isNotEmpty) {
      throw PromesaIncumplida(
        'un candidato con exactamente ${_rutas.join(", ")}',
        'uno que además cambia ${demas.join(", ")}',
      );
    }
    if (faltan.isNotEmpty) {
      throw RebanadaNoAplicable(
        'la rebanada declara ${faltan.join(", ")} y ahí no hay ningún '
            'cambio contra la base.',
        'Puede ser que el plan haya declarado algo que no tocó —la cláusula '
            'dice EXACTAMENTE, y eso vale en los dos sentidos— o que esta '
            'rebanada YA se haya aplicado. Mirá `git log` antes de tocarla.',
      );
    }

    final noMaterializadas = await _materializar(contenido, arbol);

    return _CandidatoGit._(
      repo: _repo,
      slice: _slice,
      rutas: _rutas,
      rama: _rama,
      temporal: _temporal,
      objetos: _objetos,
      indice: _indice,
      indiceDeIntegridad: _indiceDeIntegridad,
      identity: CandidateIdentity(
        contentRevision: contenido,
        baseRevision: base,
      ),
      root: arbol.path,
      changedPaths: cambiadas,
      noMaterializadas: noMaterializadas,
    ).._almacenReal = _almacenReal;
  }

  /// Vuelca el árbol a disco **sin pasar por ninguna conversión**.
  ///
  /// **Nunca con `checkout` ni `checkout-index`.** Están medidos los dos casos
  /// en que rompen la igualdad: con un filtro `smudge` y con `text eol=crlf`,
  /// lo que aparece en disco **no** es el objeto. `cat-file blob` sin `--path`
  /// no aplica ningún atributo, y eso es lo que hace que la igualdad con el
  /// objeto commiteado sea literal.
  Future<List<RutaNoMaterializada>> _materializar(
    String contenido,
    Directory arbol,
  ) async {
    final declaradas = <RutaNoMaterializada>[];

    for (final entrada in _leerArbol(
      await _repo._exigirBytes([
        'ls-tree',
        '-r',
        '-z',
        contenido,
      ], entorno: _entorno),
    )) {
      final ruta = _comoRuta(entrada.rutaCruda);

      // Un submódulo no es contenido de este árbol: es un puntero a otro
      // repositorio. Se declara.
      if (entrada.modo == '160000') {
        declaradas.add(
          RutaNoMaterializada(
            ruta: ruta,
            motivo: MotivoDeNoMaterializacion.referenciaAOtroRepositorio,
            detalle:
                'Es un submódulo. Esta rebanada no los materializa, así '
                'que ningún control corrió sobre su contenido.',
          ),
        );
        continue;
      }

      final destino = File('${arbol.path}/$ruta');
      await destino.parent.create(recursive: true);
      final bytes = await _repo._exigirBytes([
        'cat-file',
        entrada.tipo,
        entrada.sha,
      ], entorno: _entorno);

      if (entrada.modo == '120000') {
        // El contenido del objeto ES el destino del enlace. **Se decodifica
        // estricto, igual que la ruta**: con reemplazo, un destino con bytes
        // que no son UTF-8 se convertía en otro destino, y se creaba un enlace
        // que no es el que el árbol representa. Un error de esa clase produce
        // un candidato que parece materializado y apunta a otro lado.
        final String apunta;
        try {
          apunta = const Utf8Decoder(allowMalformed: false).convert(bytes);
        } on FormatException {
          declaradas.add(
            RutaNoMaterializada(
              ruta: ruta,
              motivo: MotivoDeNoMaterializacion.enlaceQueNoQuedaAdentro,
              detalle:
                  'El destino del enlace no es UTF-8, así que no se puede '
                  'nombrar sin transformarlo.',
            ),
          );
          continue;
        }
        // **Una sola conducta: no se recrea.** Y el motivo dice lo que de
        // verdad se comprobó —que el destino, tal como está escrito, no queda
        // contenido en el candidato—, no que necesariamente escape: `sub/../a`
        // se queda adentro y también se rechaza, porque averiguarlo exigiría
        // reimplementar la resolución de enlaces del sistema.
        if (apunta.startsWith('/') || apunta.split('/').any((s) => s == '..')) {
          declaradas.add(
            RutaNoMaterializada(
              ruta: ruta,
              motivo: MotivoDeNoMaterializacion.enlaceQueNoQuedaAdentro,
              detalle: apunta.startsWith('/')
                  ? 'Es un enlace absoluto («$apunta»): apunta fuera del '
                        'candidato. Recrearlo dejaría que un control leyera algo '
                        'que no se fijó.'
                  : 'El destino («$apunta») contiene `..`, así que tal como '
                        'está escrito no queda contenido en el candidato.',
            ),
          );
          continue;
        }
        await Link(destino.path).create(apunta);
        continue;
      }

      await destino.writeAsBytes(bytes);

      // **El modo no viaja en el objeto.** Está medido: cambiar el bit
      // ejecutable conserva el objeto del archivo y cambia el commit. Sale del
      // árbol, que es justamente por lo que la identidad es un árbol.
      if (entrada.modo == '100755') {
        final r = await Process.run(
          _repo.programaChmod,
          ['755', destino.path],
          environment: entornoSaneado(_repo._padre),
          includeParentEnvironment: false,
        );
        if (r.exitCode != 0) {
          throw PromesaIncumplida(
            'materializar $ruta con su bit ejecutable',
            'un archivo sin el bit: '
                '${"${r.stdout}${r.stderr}".trim()}',
          );
        }
      }
    }

    return declaradas;
  }

  @override
  Future<List<AlteracionDelCandidato>> alteraciones() async {
    if (_dispuesto) {
      throw StateError('El candidato ya se liberó: no hay árbol que comparar.');
    }
    // **No se compara byte a byte a mano: se le pide a `git`.** Con un índice
    // propio, leído del árbol fijado, refrescado contra el disco y comparado.
    // Los tres comandos están medidos, y cada bandera tiene su motivo:
    //
    //  - sin `--refresh`, el índice recién leído no tiene información de `stat`
    //    y `diff-index` reporta el árbol entero como modificado: cien
    //    diferencias falsas;
    //  - **con `-q`**, porque `--refresh` sale con 1 cuando algún archivo
    //    necesita actualización —es decir, exactamente cuando hay algo que
    //    reportar—, y `_exigir` convertiría ese 1 en `GitFallo` antes de que el
    //    `diff-index` alcance a describirlo;
    //  - **`--raw` y no `--name-status`**, porque aquel pliega un cambio de
    //    modo en una `M` indistinguible de un cambio de contenido.
    //
    // **El almacén temporal solo se nombra mientras existe.** `_promover` lo
    // borra, y un `GIT_OBJECT_DIRECTORY` que apunta a un directorio que ya no
    // está hace que `git` conteste «not a git repository» — acusando al
    // repositorio, que está perfecto. Después de promover, el árbol resuelve
    // desde el almacén real y no hace falta nombrar ninguno.
    final entorno = {
      if (!_promovido) ..._entorno,
      'GIT_INDEX_FILE': _indiceDeIntegridad.path,
      'GIT_WORK_TREE': root,
    };
    await _repo._exigir([
      'read-tree',
      identity.contentRevision,
    ], entorno: entorno);
    await _repo._exigir(['update-index', '-q', '--refresh'], entorno: entorno);
    final crudo = await _repo._exigirBytes([
      'diff-index',
      '--raw',
      '-z',
      identity.contentRevision,
    ], entorno: entorno);
    final declaradas = {for (final n in noMaterializadas) n.ruta};
    final alteraciones = leerDiffRaw(crudo, declaradas: declaradas);

    // **Y las rutas NUEVAS, que `diff-index` no ve.** Solo informa entradas que
    // el árbol conoce, así que un archivo sin seguimiento le es invisible: un
    // archivo de fuente creado entre la derivación y este control dejaba la corrida
    // concluyendo sobre bytes que el candidato nunca fijó. Reproducido.
    //
    // **Sin `--exclude-standard`, a propósito.** Esa bandera haría de las
    // exclusiones del repositorio una SEGUNDA autoridad sobre qué es artefacto,
    // callando rutas que la política sí considera fuente. Quién decide eso ya
    // está decidido: es [ArtifactPolicy], y acá se le pregunta a ella.
    //
    // El candidato se materializa desde el árbol, así que al empezar no hay
    // nada sin seguimiento: todo lo que aparezca acá apareció DESPUÉS, y la
    // única pregunta es si la política lo declara artefacto.
    final nuevas = _partirNul(
      await _repo._exigirBytes([
        'ls-files',
        '--others',
        '-z',
      ], entorno: entorno),
    ).map(_comoRuta);

    for (final ruta in nuevas) {
      if (declaradas.contains(ruta)) continue;
      if (!_repo.politica.isEditable(ruta)) continue;
      alteraciones.add(
        AlteracionDelCandidato(ruta: ruta, tipo: TipoDeAlteracion.agregada),
      );
    }
    alteraciones.sort((a, b) => a.ruta.compareTo(b.ruta));
    return alteraciones;
  }

  @override
  Future<String> createRevision() async {
    if (_dispuesto) {
      throw StateError('El candidato ya se liberó: sus objetos no existen.');
    }
    if (_revision != null) return _revision!;

    // **Antes de escribir un solo objeto.** El puerto promete que una rebanada
    // con secretos no se commitea, y esa promesa no puede depender de que el
    // llamador se acuerde de preguntar: `apply` la cumple adentro, y este
    // camino tiene que cumplirla igual o `ChangeSink` pasa a tener dos
    // garantías distintas según por dónde se entre.
    await _exigirSinSecretos();

    await _promover();

    // **Crear un commit no mueve la rama.** Por eso puede ir antes de la
    // condición: si el compare-and-swap se rechaza después, este objeto queda
    // inalcanzable y `git gc` lo recoge. No es daño, y a cambio la revisión ya
    // existe y se puede persistir antes de tocar ninguna referencia.
    // **La identidad viaja capturada, y `useConfigOnly` la exige.** Sin la
    // captura, el entorno saneado pierde una identidad que viva en XDG; sin
    // `useConfigOnly`, `git` no falla al no encontrarla: inventa un autor con
    // el usuario del sistema y el hostname, y el commit queda en el historial
    // firmado por alguien que no es. Es la diferencia entre un fallo y un dato
    // falso.
    return _revision = await _repo._exigir([
      '-c',
      'user.useConfigOnly=true',
      'commit-tree',
      identity.contentRevision,
      '-p',
      identity.baseRevision,
      '-m',
      _slice.intent,
    ], entorno: await _repo._identidadComoEntorno());
  }

  @override
  Future<CommitOutcome> applyRevision() async {
    if (_dispuesto) {
      throw StateError('El candidato ya se liberó: sus objetos no existen.');
    }
    final revision = _revision;
    if (revision == null) {
      throw StateError(
        'No hay revisión que aplicar: llamá primero a `createRevision`, y '
        'persistila antes de aplicar. Esa secuencia es lo que permite '
        'recuperarse de una muerte entre las dos.',
      );
    }

    // **Dónde estamos ahora.** Si el usuario cambió de rama entre la
    // preparación y ahora, mover la rama preparada dejaría un commit en una
    // rama que no está puesta y un índice sincronizado contra otra cosa.
    final ramaAhora = await _repo.ramaActual;
    if (ramaAhora != _rama) {
      return NotApplied(
        revision: revision,
        causa: CausaDeNoAplicacion.ramaCambiada,
        baseEsperada: identity.baseRevision,
        headObservado: await _repo._exigir(['rev-parse', 'HEAD']),
        ramaObservada: ramaAhora,
      );
    }

    // `update-ref` de tres argumentos es un compare-and-swap real: falla
    // cerrado si la referencia no está donde se dice, y el trabajo ajeno
    // sobrevive. Está medido con `HEAD` movido por otro proceso.
    final cas = await _repo._git([
      'update-ref',
      'refs/heads/$_rama',
      revision,
      identity.baseRevision,
    ]);
    if (cas.exitCode != 0) {
      return NotApplied(
        revision: revision,
        causa: CausaDeNoAplicacion.baseMovida,
        baseEsperada: identity.baseRevision,
        headObservado: await _repo._exigir(['rev-parse', 'HEAD']),
      );
    }

    // Y se comprueba dónde quedó, que es lo que el puerto promete: `git` puede
    // salir con cero y dejar la referencia en otro lado.
    final quedo = await _repo._exigir(['rev-parse', 'refs/heads/$_rama']);
    if (quedo != revision) {
      throw PromesaIncumplida(
        'dejar «$_rama» en $revision',
        'la rama en $quedo',
      );
    }

    // El índice del usuario, al día con el nuevo `HEAD` y **solo en estas
    // rutas**. Sin esto `git status` reporta lo recién commiteado como
    // borrado. `commit-tree` no lo toca —no es `git commit`— así que acá la
    // sincronización no es cosmética: sin ella el árbol de trabajo queda
    // mintiendo.
    final sincronizado = await _repo._git([
      'reset',
      '--quiet',
      '--',
      ..._rutas,
    ]);
    if (sincronizado.exitCode != 0) {
      return LocalInconsistent(
        revision: revision,
        detalle: IndiceDesincronizado(
          revision,
          _rutas,
          '${sincronizado.stdout}${sincronizado.stderr}'.trim(),
        ).toString(),
      );
    }

    return Committed(revision);
  }

  /// **El mismo guardia que [RepositorioGit.apply], sobre el par de revisiones
  /// del candidato.**
  ///
  /// El diff se deriva de `baseRevision` y `contentRevision` —un objeto, no dos
  /// lecturas del árbol— así que acá no hay ventana entre lo que se inspecciona
  /// y lo que se commitea. Lo que **no** cubre es el árbol entero: el detector
  /// revisa las líneas agregadas de un diff, y lo que `git` declara binario
  /// queda afuera por límite declarado.
  Future<void> _exigirSinSecretos() async {
    for (final ruta in _rutas) {
      final diff = await _repo._exigir([
        'diff',
        '--unified=0',
        '--no-textconv',
        '--no-ext-diff',
        identity.baseRevision,
        identity.contentRevision,
        '--',
        ruta,
      ], entorno: _entorno);
      final hallazgos = _repo.detector.revisar(diff, archivo: ruta);
      if (hallazgos.isNotEmpty) throw SecretoEnLaRebanada(hallazgos);
    }
  }

  /// Copia al repositorio real **todos** los objetos que el candidato creó.
  ///
  /// **Recursiva y preservando el tipo.** Promover solo los objetos de archivo
  /// estaba mal y está medido: los árboles —incluidos los subárboles— también
  /// nacen en el almacén temporal, y con solo los primeros promovidos
  /// `commit-tree` falla con «is not a valid object».
  ///
  /// `hash-object` con `-t` y `--stdin`, sin `--path`, **no aplica ningún
  /// atributo**: ningún filtro corre por segunda vez, así que el identificador
  /// que vuelve tiene que ser el mismo. Que se compruebe es lo que convierte
  /// «no debería refiltrar» en un hecho.
  Future<void> _promover() async {
    if (_promovido) return;

    final empaquetados = Directory('${_objetos.path}/pack');
    if (empaquetados.existsSync() &&
        empaquetados.listSync().whereType<File>().isNotEmpty) {
      throw const PromesaIncumplida(
        'promover objetos sueltos, uno por uno',
        'un almacén temporal con objetos empaquetados, que esta rebanada no '
            'sabe promover',
      );
    }

    for (final objeto
        in _objetos
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => !f.path.contains('/pack/'))) {
      final partes = objeto.uri.pathSegments;
      final sha = '${partes[partes.length - 2]}${partes.last}';
      // **No se fija la longitud del identificador.** Fijarla en 40 dejaba
      // fuera todo repositorio creado con `--object-format=sha256`, donde el
      // identificador tiene 64: el candidato se preparaba bien, no se promovía
      // nada, y la comprobación de identidad fallaba con un mensaje que no
      // nombraba la causa. La forma de un objeto suelto es la misma —dos
      // caracteres de directorio y el resto de nombre— y quien decide si
      // existe es `cat-file`, no una expresión nuestra.
      if (!RegExp(r'^[0-9a-f]+$').hasMatch(sha)) continue;

      final tipo = await _repo._exigir([
        'cat-file',
        '-t',
        sha,
      ], entorno: _entorno);
      final contenido = await _repo._exigirBytes([
        'cat-file',
        tipo,
        sha,
      ], entorno: _entorno);
      // Sin `_entorno`: el destino es el almacén del usuario.
      final promovido = await _repo._exigirConEntrada([
        'hash-object',
        '-t',
        tipo,
        '-w',
        '--stdin',
      ], contenido);
      if (promovido != sha) {
        throw PromesaIncumplida(
          'promover $sha sin transformarlo',
          'el objeto $promovido, que no es el mismo',
        );
      }
    }

    _promovido = true;

    // Se sueltan los temporales **antes** de comprobar, para que la comprobación
    // no pueda pasar por los alternates: si el contenido no resuelve desde el
    // repositorio real, acá se cae.
    await _borrar(_objetos);
    if (_indice.existsSync()) _indice.deleteSync();

    final tipo = await _repo._git(['cat-file', '-t', identity.contentRevision]);
    if (tipo.exitCode != 0 || (tipo.stdout as String).trim() != 'tree') {
      throw PromesaIncumplida(
        'que ${identity.contentRevision} resuelva en el repositorio real',
        'un identificador que ahí no existe',
      );
    }
  }

  @override
  Future<void> dispose() async {
    _dispuesto = true;
    await _borrar(_temporal);
  }

  static Future<void> _borrar(Directory d) async {
    if (d.existsSync()) await d.delete(recursive: true);
  }

  static List<List<int>> _partirNul(List<int> bytes) {
    final piezas = <List<int>>[];
    var desde = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0) {
        if (i > desde) piezas.add(bytes.sublist(desde, i));
        desde = i + 1;
      }
    }
    if (desde < bytes.length) piezas.add(bytes.sublist(desde));
    return piezas;
  }

  /// `<modo> <tipo> <sha>\t<ruta>` por registro, y los registros separados por
  /// NUL.
  static List<_EntradaDeArbol> _leerArbol(List<int> bytes) {
    final entradas = <_EntradaDeArbol>[];
    for (final registro in _partirNul(bytes)) {
      final tab = registro.indexOf(9);
      if (tab < 0) {
        throw const PromesaIncumplida(
          'leer una entrada de árbol',
          'un registro de `ls-tree -z` sin tabulador',
        );
      }
      final meta = utf8.decode(registro.sublist(0, tab)).split(' ');
      entradas.add(
        _EntradaDeArbol(meta[0], meta[1], meta[2], registro.sublist(tab + 1)),
      );
    }
    return entradas;
  }

  /// **Una ruta que no es UTF-8 se declara, no se adivina.**
  ///
  /// El lenguaje nombra archivos con cadenas y no tiene el escape que deja
  /// llevar y traer bytes arbitrarios. Decodificar con reemplazo produciría una ruta
  /// **parecida** a la real, que es peor que no tenerla: el candidato diría
  /// haber materializado algo que no existe con ese nombre.
  static String _comoRuta(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      throw RebanadaNoAplicable(
        'el árbol contiene una ruta que no es UTF-8 (bytes: $hex).',
        'Renombrá ese archivo a un nombre UTF-8. Esta rebanada prefiere '
            'negarse a nombrarlo mal: una ruta decodificada con reemplazo se '
            'parece a la real y no lo es.',
      );
    }
  }
}
