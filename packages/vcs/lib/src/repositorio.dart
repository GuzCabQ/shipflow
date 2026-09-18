/// El repositorio local. **Sabe de `git` y de nada más.**
///
/// No conoce el lenguaje del proyecto, ni el CLI agéntico, ni la forja. Lo
/// primero y lo segundo están sostenidos por reglas de arquitectura; lo tercero
/// por el corte entre `ChangeSink` y `PullRequestSink`.
///
/// **Corre `git` por proceso, con su propia costura.** La que usa el plugin
/// del stack no se puede reusar: `deps-hacia-core` prohíbe que este paquete lo
/// vea, y subir la costura a `core` sería meter procesos en el dominio, que no
/// habla de eso. La duplicación es de treinta líneas y es el precio del corte;
/// compartirla costaría más.
///
/// **Una cadena del dominio no es un argumento de `git`.** Un review lo cobró
/// dos veces en la misma rebanada: una ruta no es un *pathspec* y un nombre no
/// es una *revisión*. Las dos veces el adapter no fallaba por ignorar `git`,
/// sino por confiar en que su semántica coincidía con la del dominio. Acá cada
/// traducción está explícita, y cada promesa se comprueba **después** de que
/// `git` dijo que salió bien.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

import 'secretos.dart';

part 'candidato.dart';
part 'alteraciones.dart';

/// Se lanza cuando `git` no hizo lo que se le pidió.
///
/// **Lleva el comando y lo que dijo.** Un fallo de repositorio sin la salida
/// de la herramienta obliga a reproducirlo a mano para saber qué pasó.
class GitFallo implements Exception {
  final String invocacion;
  final int codigo;
  final String salida;

  const GitFallo(this.invocacion, this.codigo, this.salida);

  @override
  String toString() => 'GitFallo($invocacion → $codigo): $salida';
}

/// Se lanza cuando lo que se pide no se puede commitear.
class RebanadaNoAplicable implements Exception {
  final String reason;
  final String queHacer;
  const RebanadaNoAplicable(this.reason, this.queHacer);

  @override
  String toString() => 'RebanadaNoAplicable: $reason';
}

/// Se lanza cuando **`git` salió bien y el repositorio no quedó como se pidió**.
///
/// No es un fallo de la herramienta —su código de salida fue cero— sino una
/// cláusula del puerto incumplida. Existe porque las validaciones previas solo
/// cubren los casos que alguien enumeró, y esta clase de error ya se coló dos
/// veces por casos que nadie había enumerado. Comprobar el estado final en vez
/// de confiar en el argumento **deriva la cláusula en vez de mantenerla**: un
/// caso nuevo se cae acá aunque nadie lo haya previsto.
class PromesaIncumplida implements Exception {
  final String sePidio;
  final String quedo;
  const PromesaIncumplida(this.sePidio, this.quedo);

  @override
  String toString() => 'PromesaIncumplida: se pidió $sePidio; quedó $quedo';
}

/// El commit existe y el índice quedó sin sincronizar.
///
/// **La revisión va como campo y no solo en el mensaje.** Antes esto salía
/// como una `PromesaIncumplida` con dos `String`, y la revisión vivía
/// interpolada en el texto: quien recuperara la corrida tenía que parsear un
/// mensaje para saber qué comprobar. Un dato que solo existe dentro de una
/// oración no es un dato.
class IndiceDesincronizado implements Exception {
  /// El commit que sí se creó.
  final String revision;

  /// Qué quedó mal, en las palabras de `git`.
  final String detalle;

  const IndiceDesincronizado(this.revision, this.detalle);

  @override
  String toString() =>
      'IndiceDesincronizado: la revisión $revision se creó y el índice quedó '
      'sin sincronizar. $detalle';
}

class RepositorioGit implements ChangeSink {
  /// La raíz del repositorio sobre el que se trabaja.
  final String directorio;

  /// El ejecutable. **Es inyectable solo para poder probar que su ausencia se
  /// nota**: una herramienta que no está no puede leerse como que no había
  /// nada que hacer.
  final String programa;

  /// Qué es fuente y qué no, según el stack. **Obligatoria y sin valor por
  /// defecto.**
  ///
  /// `docs/04` §«solo PR» lo dice sin ambigüedad para la política: hace falta
  /// **incluso** en el caso que entra sin `WorkItem`, sin plan y sin agente.
  /// (Esa misma frase nombra también `ProjectTopology`, que acá **no** se
  /// recibe: su única función descrita —cortar commits por «unidad
  /// coherente»— no está definida en el corpus y la descomposición está
  /// asignada a `orchestration` y congelada. Es `D-095`.) Un valor por defecto
  /// —una política que dijera que todo es fuente— haría que un llamador
  /// distraído commiteara artefactos generados sin que nadie lo hubiera
  /// afirmado, que es el mismo agujero que `Witness.omitted` cerró del otro
  /// lado: un hecho que se asume no es un hecho declarado.
  ///
  /// **`vcs` no sabe qué la hace decir que sí.** Recibe el puerto de `core`;
  /// los sufijos y directorios que definen «generado» viven en el plugin del
  /// stack, que este paquete ni siquiera puede ver.
  final ArtifactPolicy politica;

  /// Qué reconoce como secreto. Inyectable **para poder probar que su
  /// ausencia se nota**, igual que [programa].
  final DetectorDeSecretos detector;

  /// Con qué se pone el bit ejecutable al materializar el candidato.
  ///
  /// **La biblioteca estándar no tiene manera de cambiar permisos**, así que
  /// hace falta un
  /// segundo programa externo. Es inyectable por el mismo motivo que
  /// [programa]: un modo que no se aplica y no se nota es un candidato que
  /// difiere del árbol que dice representar.
  final String programaChmod;

  /// El entorno del proceso padre. **Nulo significa el del proceso**; las
  /// pruebas le pasan el que quieren, que es la única forma de comprobar qué
  /// llega a `git` y qué no sin depender del shell de quien corre la suite.
  ///
  /// **Es [EntornoDelProceso] y no un mapa, y el tipo es el control.** El
  /// único lanzamiento exceptuado de `entornoSaneado` —`_identidadComoEntorno`,
  /// más abajo— recibe este entorno ENTERO; con un mapa, «entero» podía traer
  /// la credencial y nada lo impedía. Con este tipo, lo que sale de acá ya
  /// pasó por `paraHijos`.
  final EntornoDelProceso? _entornoDelPadre;

  const RepositorioGit({
    required this.directorio,
    required this.politica,
    this.programa = 'git',
    this.programaChmod = 'chmod',
    this.detector = const DetectorDeSecretos(),
    EntornoDelProceso? entornoDelPadre,
  }) : _entornoDelPadre = entornoDelPadre;

  Map<String, String> get _padre =>
      (_entornoDelPadre ?? EntornoDelProceso(Platform.environment)).paraHijos;

  /// **Todo pasa por `--literal-pathspecs`.** Sin eso, `git` lee cada ruta
  /// como un patrón: `*.txt` commitea dos archivos y `:(glob)…` commitea lo
  /// que quiera. Va acá y no en las llamadas que reciben rutas para que un
  /// comando nuevo no pueda olvidarse; es inocuo en los que no las reciben.
  ///
  /// El efecto secundario es el que hacía falta: con pathspecs literales, un
  /// archivo que de verdad se llame `*.txt` se commitea, y hoy no se puede.
  ///
  /// [entorno] son las variables **propias de esta invocación**
  /// —`GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, la identidad capturada—. Se
  /// suman a la lista blanca de [entornoSaneado] y a nada más: **el entorno del
  /// padre no se hereda**. Se heredaba, y con eso un `GIT_DIR` o un
  /// `GIT_INDEX_FILE` en el shell del usuario corrompía nuestras operaciones
  /// sin que nada lo notara.
  Future<ProcessResult> _git(
    List<String> args, {
    Map<String, String> entorno = const {},
  }) async {
    final completos = ['--literal-pathspecs', ...args];
    final ProcessResult r;
    try {
      r = await Process.run(
        programa,
        completos,
        workingDirectory: directorio,
        environment: entornoSaneado(_padre, propias: entorno),
        includeParentEnvironment: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on ProcessException catch (e) {
      throw GitFallo(
        '$programa ${completos.join(" ")}',
        -1,
        '${e.message} (${e.executable})',
      );
    }
    return r;
  }

  /// La identidad de `git`, **capturada con el entorno del padre**, antes de
  /// sanear.
  ///
  /// **Es LA excepción a `subprocesos-con-entorno-saneado`**, y está declarada
  /// en `arquitectura.json` con su motivo: `git config` tiene que ver
  /// `XDG_CONFIG_HOME` y `GIT_CONFIG_GLOBAL`, que la lista blanca no lleva a
  /// propósito, y enumerar por dónde `git` puede leer su configuración es la
  /// misma carrera que una lista negra. Está medido: con `PATH` y `HOME` solos,
  /// una identidad que vive en XDG se pierde y `git` fabrica el autor.
  ///
  /// Es un `git config --get` de solo lectura: no corre ganchos ni filtros, no
  /// escribe nada, y lo único que sale de acá son dos cadenas.
  ///
  /// **No se memoiza a propósito.** Los dos caminos que commitean la piden una
  /// vez cada uno, y un campo mutable para guardarla le costaría a esta clase
  /// su constructor `const` a cambio de ahorrar dos lecturas de configuración.
  ///
  /// Devuelve vacío si no hay identidad. Entonces la invocación que commitea
  /// corre con `user.useConfigOnly=true` y **se niega**, en vez de inventar un
  /// autor con el usuario del sistema y el hostname y escribirlo en el
  /// historial de alguien.
  Future<Map<String, String>> _identidadComoEntorno() async {
    Future<String> leer(String clave) async {
      final r = await Process.run(
        programa,
        ['config', '--get', clave],
        workingDirectory: directorio,
        // La excepción declarada: ver el doc de arriba.
        environment: _padre,
        includeParentEnvironment: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      // Un código distinto de cero acá significa «no está configurada», que es
      // un hecho y no un fallo: `useConfigOnly` lo convierte en el error que
      // corresponde, en el momento en que importa.
      return r.exitCode == 0 ? (r.stdout as String).trim() : '';
    }

    final nombre = await leer('user.name');
    final correo = await leer('user.email');
    if (nombre.isEmpty || correo.isEmpty) return const {};
    return {
      'GIT_AUTHOR_NAME': nombre,
      'GIT_AUTHOR_EMAIL': correo,
      'GIT_COMMITTER_NAME': nombre,
      'GIT_COMMITTER_EMAIL': correo,
    };
  }

  /// Solo para la suite: la captura de identidad es privada y esta es la
  /// única forma de comprobar QUÉ entorno recibe el único lanzamiento
  /// exceptuado de `entornoSaneado`.
  ///
  /// **Sin `@visibleForTesting`.** `meta` no es una dependencia declarada de
  /// `vcs` —solo llega transitiva por el lockfile del workspace— e importarla
  /// igual deja el análisis marcando «no es una dependencia», que con
  /// `--fatal-infos` es rojo. El nombre ya dice que es de prueba; eso alcanza.
  Future<Map<String, String>> identidadCapturadaParaLaPrueba() =>
      _identidadComoEntorno();

  /// Corre `git` y **exige que haya salido bien**. Un código distinto de cero
  /// que se ignora es un cambio que se cree hecho y no está.
  Future<String> _exigir(
    List<String> args, {
    Map<String, String> entorno = const {},
  }) async => (await _exigirCrudo(args, entorno: entorno)).trim();

  /// Igual, pero **sin recortar**.
  ///
  /// Las salidas separadas por NUL son bytes, no texto para leer: un archivo
  /// que se llame « a.txt» sale con su espacio, y recortarlo lo convierte en
  /// otro archivo. Un review lo encontró — la comparación decía que se pidió
  /// « a.txt» y que el índice además tocaba «a.txt», que es el mismo archivo
  /// escrito de dos maneras por culpa nuestra.
  Future<String> _exigirCrudo(
    List<String> args, {
    Map<String, String> entorno = const {},
  }) async {
    final r = await _git(args, entorno: entorno);
    if (r.exitCode != 0) {
      throw GitFallo(
        '$programa --literal-pathspecs ${args.join(" ")}',
        r.exitCode,
        '${r.stdout}${r.stderr}'.trim(),
      );
    }
    return r.stdout as String;
  }

  /// Igual que [_exigir], pero devuelve **bytes**.
  ///
  /// `cat-file blob` y `ls-tree -z` no son texto: el primero puede ser una
  /// imagen y el segundo lleva rutas que no tienen por qué ser UTF-8.
  /// Decodificarlos para volver a codificarlos los corrompe en silencio, que
  /// es exactamente la clase de transformación que el candidato existe para
  /// impedir.
  Future<List<int>> _exigirBytes(
    List<String> args, {
    Map<String, String> entorno = const {},
  }) async {
    final completos = ['--literal-pathspecs', ...args];
    final ProcessResult r;
    try {
      r = await Process.run(
        programa,
        completos,
        workingDirectory: directorio,
        environment: entornoSaneado(_padre, propias: entorno),
        includeParentEnvironment: false,
        stdoutEncoding: null,
        stderrEncoding: utf8,
      );
    } on ProcessException catch (e) {
      throw GitFallo(
        '$programa ${completos.join(" ")}',
        -1,
        '${e.message} (${e.executable})',
      );
    }
    if (r.exitCode != 0) {
      throw GitFallo(
        '$programa --literal-pathspecs ${args.join(" ")}',
        r.exitCode,
        (r.stderr as String).trim(),
      );
    }
    return r.stdout as List<int>;
  }

  /// Corre `git` **escribiéndole bytes por la entrada estándar**.
  ///
  /// `Process.run` no acepta entrada, y la promoción de objetos la necesita:
  /// `hash-object --stdin` es la única forma de escribir un objeto sin que
  /// `git` vuelva a leer un archivo del disco y le aplique los atributos otra
  /// vez.
  Future<String> _exigirConEntrada(
    List<String> args,
    List<int> entrada, {
    Map<String, String> entorno = const {},
  }) async {
    final completos = ['--literal-pathspecs', ...args];
    final Process p;
    try {
      p = await Process.start(
        programa,
        completos,
        workingDirectory: directorio,
        environment: entornoSaneado(_padre, propias: entorno),
        includeParentEnvironment: false,
      );
    } on ProcessException catch (e) {
      throw GitFallo(
        '$programa ${completos.join(" ")}',
        -1,
        '${e.message} (${e.executable})',
      );
    }
    p.stdin.add(entrada);
    await p.stdin.close();
    final salida = await utf8.decoder.bind(p.stdout).join();
    final error = await utf8.decoder.bind(p.stderr).join();
    final codigo = await p.exitCode;
    if (codigo != 0) {
      throw GitFallo(
        '$programa --literal-pathspecs ${args.join(" ")}',
        codigo,
        '$salida$error'.trim(),
      );
    }
    return salida.trim();
  }

  @override
  Future<void> useBranch(String name) async {
    if (name.trim().isEmpty) {
      throw const RebanadaNoAplicable(
        'El nombre de rama está vacío.',
        'Dale un nombre; una rama sin nombre no se puede retomar después.',
      );
    }

    // **Quien valida el nombre es `git`, no una expresión nuestra.** Sus
    // reglas incluyen cosas que nadie recuerda —`HEAD`, `.lock`, `..`, un
    // nombre que empieza con guion— y una lista escrita a mano se queda corta
    // el día que `git` agregue una.
    //
    // Se compara la SALIDA con la entrada porque `--branch` no solo valida:
    // también expande. `@{-1}` sale con código cero y devuelve *otra* rama, y
    // un nombre que se convierte en otro no es el nombre que nos pidieron.
    final formato = await _git(['check-ref-format', '--branch', name]);
    if (formato.exitCode != 0 ||
        (formato.stdout as String).trim() != name.trim()) {
      throw RebanadaNoAplicable(
        '«$name» no es un nombre de rama que git acepte literalmente.',
        'Usá letras, números, guiones y barras: `shipflow/lo-que-sea`. Ni '
            '`HEAD`, ni algo que empiece con guion, ni sintaxis de revisión '
            'como `@{-1}`.',
      );
    }

    // **La pregunta es si existe la RAMA, no si el nombre resuelve a algo.**
    // `rev-parse --verify` resolvía cualquier revisión: con una etiqueta
    // homónima decía «ya existe» y `switch` fallaba con «a branch is expected,
    // got tag». Una reanudación legítima quedaba rota por un nombre que ni
    // siquiera era una rama.
    final existe = await _git([
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$name',
    ]);

    // **Idempotente**: la orquestación la pide al empezar y `--resume` la
    // vuelve a pedir. Que la segunda vez falle rompería la reanudación que
    // ADR-014 exige.
    await _exigir(
      existe.exitCode == 0
          ? ['switch', '--', name]
          : ['switch', '--create', name],
    );

    // Y **se comprueba dónde quedamos.** `git switch` tiene formas de salir
    // con cero sin dejarnos en la rama pedida —`--detach` es la evidente— y
    // el puerto promete la rama, no la invocación.
    final actual = await ramaActual;
    if (actual != name) {
      throw PromesaIncumplida(
        'quedar en la rama «$name»',
        actual.isEmpty ? 'HEAD suelto, sin rama' : 'la rama «$actual»',
      );
    }
  }

  /// Traduce una entrada de la rebanada a una ruta que `git` va a tratar como
  /// **un archivo y no como un patrón**, o la rechaza diciendo qué hacer.
  ///
  /// **No normaliza: exige la forma canónica.** `./a.txt`, `a//b` y `a/../b`
  /// nombran archivos que existen, y `git` los acepta — pero los devuelve
  /// normalizados, así que compararlos después contra lo que se declaró
  /// obligaría a reimplementar la normalización de `git`. Pedir la forma en
  /// que `git` los nombra es más barato y no tiene casos raros.
  Future<String> _rutaDeArchivo(String entrada) async {
    RebanadaNoAplicable no(String razon, String queHacer) =>
        RebanadaNoAplicable('«$entrada»: $razon', queHacer);

    if (entrada.trim().isEmpty) {
      throw no(
        'está en blanco.',
        'Una entrada vacía no nombra nada. Sacala de la rebanada.',
      );
    }
    if (entrada.startsWith('/')) {
      throw no(
        'es una ruta absoluta.',
        'Nombrala relativa a la raíz del repositorio, como la nombra git.',
      );
    }
    final partes = entrada.split('/');
    if (partes.any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw no(
        'no está en la forma en que git nombra un archivo.',
        'Escribila sin `./`, sin `..` y sin barras repetidas ni al final.',
      );
    }

    // **Lo que no es fuente no se commitea, y no se quita en silencio.**
    //
    // `isEditable` es la pregunta correcta y no `isGenerated`: es la negación
    // de dos cosas —lo generado se regenera, lo de build no es fuente— y las
    // dos van afuera. Preguntar solo por lo generado dejaba pasar los
    // directorios de build, que no son generados y tampoco se versionan.
    //
    // **Se rechaza, no se excluye.** El pseudocódigo dice «excluye generados
    // del stage» y el corpus nunca dijo si eso es en silencio; quitar un
    // archivo que la rebanada declara rompería la cláusula 1, que exige
    // exactamente los archivos de la rebanada en los dos sentidos. Y `docs/03`
    // tiene el principio: se reporta como hallazgo, no se absorbe en silencio.
    // **El borrado de algo ya versionado sí se permite.** La política dice qué
    // no se escribe; si un repositorio ya tenía un generado commiteado, sacarlo
    // es exactamente lo que la política quiere y prohibirlo dejaba al arnés sin
    // manera de limpiarlo. Lo señaló un review, y `D-094` se enmienda con esto.
    final existeEnDisco =
        FileSystemEntity.typeSync('$directorio/$entrada', followLinks: false) !=
        FileSystemEntityType.notFound;
    if (existeEnDisco && !politica.isEditable(entrada)) {
      throw no(
        'no es fuente: el stack lo declara generado o artefacto de build.',
        'Lo generado se regenera, así que versionarlo duplica la verdad y la '
            'deja envejecer. Sacalo de la rebanada; si de verdad tiene que '
            'viajar, lo que hay que cambiar es la política del stack, no '
            'esta rebanada.',
      );
    }

    // Qué hay del otro lado. `followLinks: false` a propósito: `git` guarda un
    // enlace como enlace y no mira a dónde apunta, así que uno que apunte a un
    // directorio sigue siendo un archivo para esto.
    final tipo = FileSystemEntity.typeSync(
      '$directorio/$entrada',
      followLinks: false,
    );
    assert(existeEnDisco == (tipo != FileSystemEntityType.notFound));
    if (tipo == FileSystemEntityType.directory) {
      throw no(
        'es un directorio.',
        'La rebanada nombra archivos, no carpetas: un directorio arrastra '
            'todo lo que tenga adentro, incluido lo que nadie planeó. '
            'Nombrá los archivos uno por uno.',
      );
    }
    if (tipo == FileSystemEntityType.notFound) {
      // Puede ser un borrado, que es un cambio legítimo. Lo es solo si git ya
      // lo tenía; si no, es una ruta que no nombra nada.
      // **`--error-unmatch` no alcanzaba: acepta un PREFIJO.** Con `dir/`
      // borrado del disco, `ls-files -- dir` coincide con `dir/x.txt` y
      // `dir/y.txt`, y el guardia daba por buena una entrada que arrastraba
      // dos archivos. Es el mismo error que este archivo corrige en todas
      // partes —confundir «coincide» con «es»— reaparecido del lado del
      // borrado, y lo encontró un review. Se exige que lo que git tenga sea
      // UNO y sea exactamente esta ruta.
      final rastreado = await _git(['ls-files', '-z', '--', entrada]);
      final tiene = (rastreado.stdout as String)
          .split('\u0000')
          .where((s) => s.isNotEmpty)
          .toList();
      if (tiene.length != 1 || tiene.single != entrada) {
        throw no(
          tiene.isEmpty
              ? 'no existe en el árbol y git tampoco lo tiene.'
              : 'no existe en el árbol y para git no es un archivo sino '
                    '${tiene.length}.',
          'Si era un borrado, tiene que ser el de UN archivo que estaba '
          'commiteado. Un directorio, aunque haya desaparecido, sigue '
          'arrastrando todo lo que tenía adentro.',
        );
      }
    }
    return entrada;
  }

  /// **El índice aislado: el objeto que se escanea es el que se commitea.**
  ///
  /// Antes esto preparaba el índice real, preguntaba con `commit --dry-run` y
  /// después commiteaba con `commit -- <rutas>`, que **vuelve a leer el árbol
  /// de trabajo**. Un review lo rompió con un gancho `pre-commit` que reescribe
  /// el archivo y hace `git add`: el escaneo veía una cosa, el commit se
  /// llevaba otra, y el secreto quedaba en `HEAD`. No era la concurrencia
  /// futura — era la propia operación invocando al gancho adentro suyo.
  ///
  /// Acá se arma un índice aparte con `GIT_INDEX_FILE`, se lo inspecciona y se
  /// commitea **ese mismo índice**. Deja de haber dos consultas cercanas en el
  /// tiempo sobre representaciones distintas: hay un objeto.
  ///
  /// **Y el índice del usuario no se toca.** Eso vuelve innecesaria la
  /// maquinaria de fotografiarlo y reponerlo que pedía un review anterior: no
  /// hay daño que deshacer si no hay daño. En el camino de éxito sí se
  /// sincroniza, porque es lo que hace `git commit -- <ruta>` y este adapter
  /// se comporta como `git`.
  Future<T> _conIndiceAislado<T>(
    Future<T> Function(Map<String, String>, String) usar,
  ) async {
    final ruta = '${await _rutaDeGit('index')}.shipflow';
    final entorno = {'GIT_INDEX_FILE': ruta};
    final archivo = File(ruta);
    // **A dónde va a buscar ganchos `git`, y no los va a encontrar.**
    //
    // No se crea: está medido que con una ruta inexistente `git` commitea
    // igual y no dispara nada. Crearla era código muerto y una mutación lo
    // demostró — nada se ponía rojo al sacarlo. Lo que sí hace falta es
    // **borrarla si existe**: si alguien dejó un gancho justo ahí, correría, y
    // «ningún gancho del usuario corre» dejaría de ser cierto por la puerta que
    // abrimos nosotros. Esa guardia sí tiene su caso y sí se la vio fallar.
    final sinGanchos = Directory('$ruta.sin-ganchos');
    try {
      if (archivo.existsSync()) archivo.deleteSync();
      if (sinGanchos.existsSync()) sinGanchos.deleteSync(recursive: true);
      // Un repositorio sin commits todavía no tiene de dónde leer un árbol, y
      // ahí el índice vacío ES el punto de partida correcto.
      if ((await _git(['rev-parse', '--verify', '--quiet', 'HEAD'])).exitCode ==
          0) {
        await _exigir(['read-tree', 'HEAD'], entorno: entorno);
      }
      return await usar(entorno, sinGanchos.path);
    } finally {
      if (archivo.existsSync()) archivo.deleteSync();
      if (sinGanchos.existsSync()) sinGanchos.deleteSync(recursive: true);
    }
  }

  /// Una ruta interna de `git`. **Se le pregunta**: no siempre cuelga de
  /// `.git/` —un worktree enlazado la tiene en otro lado.
  Future<String> _rutaDeGit(String que) async {
    final relativa = await _exigir(['rev-parse', '--git-path', que]);
    return relativa.startsWith('/') ? relativa : '$directorio/$relativa';
  }

  /// Un merge sin resolver no admite rebanadas.
  ///
  /// `git` mismo se niega a hacer un commit parcial durante un merge. Está acá
  /// para decirlo antes y decir qué hacer, que es lo que un `GitFallo` crudo no
  /// hace.
  Future<void> _exigirSinConflictos() async {
    if ((await _exigir(['ls-files', '--unmerged', '-z'])).isNotEmpty) {
      throw const RebanadaNoAplicable(
        'hay un merge sin resolver.',
        'Resolvé el merge y volvé a intentar: git no hace un commit parcial '
            'con conflictos abiertos, y una rebanada es siempre parcial.',
      );
    }
  }

  /// Las rutas de la rebanada, validadas y en la forma en que `git` las nombra.
  ///
  /// **Es la misma puerta para [apply] y para [prepareCandidate].** Que el
  /// candidato aceptara una rebanada que el commit rechaza —o al revés— haría
  /// que el contenido verificado y el commiteado pudieran diferir por la vía
  /// más tonta: dos validaciones que se separan con el tiempo.
  Future<List<String>> _rutasDeLaRebanada(PullRequestSlice slice) async {
    if (slice.files.isEmpty) {
      throw const RebanadaNoAplicable(
        'La rebanada no nombra ningún archivo.',
        'Un commit vacío afirma un cambio que no existe. Poné los archivos '
            'en la rebanada, o no la apliques.',
      );
    }
    if (slice.intent.trim().isEmpty) {
      throw const RebanadaNoAplicable(
        'La rebanada no dice por qué existe.',
        'El `intent` es lo que ADR-014 llama intención, y es el mensaje del '
            'commit: sin él nadie puede revisar por qué se hizo.',
      );
    }

    final rutas = <String>[];
    for (final entrada in slice.files) {
      final ruta = await _rutaDeArchivo(entrada);
      if (rutas.contains(ruta)) {
        throw RebanadaNoAplicable(
          '«$entrada» está dos veces en la rebanada.',
          'La rebanada declara un conjunto de archivos. Repetir uno no '
              'commitea nada distinto y vuelve ambiguo el alcance.',
        );
      }
      rutas.add(ruta);
    }
    return rutas;
  }

  @override
  Future<PreparedCandidate> prepareCandidate(PullRequestSlice slice) =>
      _CandidatoGit.preparar(this, slice);

  @override
  Future<String> apply(PullRequestSlice slice) async {
    final rutas = await _rutasDeLaRebanada(slice);

    await _exigirSinConflictos();

    final revision = await _conIndiceAislado((entorno, sinGanchos) async {
      await _exigir(['add', '--', ...rutas], entorno: entorno);

      // **Lo que este índice va a commitear, que es este índice.** Ya no hay
      // que preguntarle a `commit --dry-run` qué haría: el índice ES el
      // contenido del commit. `-z` porque `git` cita las rutas que no son
      // ASCII y comparar la cita contra la ruta falla sobre archivos válidos.
      final entra = (await _exigirCrudo([
        'diff',
        '--cached',
        '--name-only',
        '-z',
        '--',
        ...rutas,
      ], entorno: entorno)).split('\u0000').where((s) => s.isNotEmpty).toSet();
      final pedidas = rutas.toSet();
      final demas = entra.difference(pedidas).toList()..sort();
      final faltan = pedidas.difference(entra).toList()..sort();
      if (demas.isNotEmpty) {
        throw PromesaIncumplida(
          'commitear exactamente ${rutas.join(", ")}',
          'un índice que además tocaría ${demas.join(", ")}',
        );
      }
      if (faltan.isNotEmpty) {
        // **Dos lecturas, y desde acá son indistinguibles.**
        //
        // «No hay nada que commitear» puede querer decir que el plan declaró
        // algo que no tocó, o que **esta rebanada ya se aplicó** —lo segundo es
        // lo que vería una reanudación tras morir entre el commit y el PR—. El
        // mensaje nombraba solo la primera, y en una reanudación mandaba a
        // arreglar una rebanada que no tiene nada malo.
        //
        // Distinguirlas de verdad exige marcar el commit con la identidad de
        // la rebanada, y eso es escribir metadata nuestra en el historial del
        // usuario para siempre: es una decisión de diseño, no un arreglo, y
        // pertenece a la política de reanudación que el corpus declara
        // faltante (`D-032`). Hasta entonces se dicen las dos.
        throw RebanadaNoAplicable(
          'la rebanada declara ${faltan.join(", ")} y no hay nada que '
              'commitear ahí.',
          'Puede ser que el plan haya declarado algo que no tocó —la '
              'cláusula dice EXACTAMENTE, y eso vale en los dos sentidos— o '
              'que esta rebanada YA se haya aplicado, que es lo que se ve al '
              'reintentarla. Mirá `git log` antes de tocar la rebanada: si '
              'el cambio ya está commiteado, no hay nada que arreglar.',
        );
      }

      await _exigirSinSecretos(rutas, entorno);

      // **Ningún gancho del usuario corre, y hace falta más que `--no-verify`.**
      //
      // `--no-verify` frena `pre-commit` y `commit-msg`, y nada más. Un review
      // lo midió: con `prepare-commit-msg` el gancho reescribía el archivo en
      // el árbol de trabajo y `apply` devolvía éxito dejando el repositorio con
      // la clave. El objeto commiteado seguía siendo el inspeccionado —el
      // índice aislado aguantó— pero el costo que `D-096` declaraba era falso.
      // `post-commit` también corría.
      //
      // Un `core.hooksPath` a un directorio vacío los frena a todos, y es UN
      // mecanismo en vez de dos: `--no-verify` al lado de esto sería una línea
      // que no puede fallar.
      // **`useConfigOnly` también acá.** Este camino commitea igual que el del
      // candidato, y sin esto `git` fabricaría el autor cuando la captura no
      // encontró identidad. Dos caminos que escriben en el historial no pueden
      // tener garantías distintas según por dónde se entre.
      await _exigir(
        [
          '-c',
          'core.hooksPath=$sinGanchos',
          '-c',
          'user.useConfigOnly=true',
          'commit',
          '--message',
          slice.intent,
        ],
        entorno: {...entorno, ...await _identidadComoEntorno()},
      );
      return _exigir(['rev-parse', 'HEAD']);
    });

    // **Sincronizar el índice real con el nuevo `HEAD`, solo en estas rutas.**
    // Está medido que es exactamente lo que deja `git commit -- <ruta>`. Sin
    // esto, `git status` reporta las rutas recién commiteadas como borradas.
    // **Y su fallo no se ignora.** Estaba con la llamada que NO lanza, así que
    // un `reset` que fallara dejaba el commit hecho, el índice desincronizado y
    // a `apply` devolviendo una revisión como si todo hubiera salido bien. Lo
    // encontró un review, y contradecía la regla que este mismo archivo se
    // impone unas líneas más arriba.
    //
    // La revisión ya existe y no se deshace: son dos efectos distintos y el
    // primero salió bien. Lo que no se puede es afirmar éxito total, así que el
    // estado parcial se nombra entero, con la revisión adentro.
    final sincronizado = await _git(['reset', '--quiet', '--', ...rutas]);
    if (sincronizado.exitCode != 0) {
      throw IndiceDesincronizado(
        revision,
        'en ${rutas.join(", ")}: '
        '${"${sincronizado.stdout}${sincronizado.stderr}".trim()}',
      );
    }
    return revision;
  }

  /// Escanea **una ruta por vez**, pasándole al detector la ruta que ya
  /// conoce.
  ///
  /// Sacarla del encabezado `diff --git a/x b/x` era otro parser de más: con
  /// una ruta que no es ASCII, `git` la **cita** —`"a/\303\241.conf"`— y el
  /// hallazgo quedaba señalando una cadena que no es un archivo. La ruta ya la
  /// tenemos; no hay que volver a deducirla de la salida de la herramienta.
  ///
  /// **`--no-textconv` y `--no-ext-diff` no son detalles.** Un repositorio
  /// puede declarar en `.gitattributes` un `textconv` que reemplace lo que
  /// `git diff` muestra, y está medido que con uno que no imprime nada el
  /// detector recibe un diff vacío y el secreto pasa. Una inspección de
  /// seguridad no puede leer una **representación** configurable por el propio
  /// repositorio que está inspeccionando.
  Future<void> _exigirSinSecretos(
    List<String> rutas,
    Map<String, String> entorno,
  ) async {
    for (final ruta in rutas) {
      final diff = await _exigir([
        'diff',
        '--cached',
        '--unified=0',
        '--no-textconv',
        '--no-ext-diff',
        '--',
        ruta,
      ], entorno: entorno);
      // **La misma causa tipada que el candidato.** Antes acá salía una
      // `RebanadaNoAplicable` genérica y allá otra: el mismo hecho —hay un
      // secreto— llegaba al llamador de dos formas distintas según por qué
      // camino de escritura hubiera entrado.
      final hallazgos = detector.revisar(diff, archivo: ruta);
      if (hallazgos.isNotEmpty) throw SecretoEnLaRebanada(hallazgos);
    }
  }

  /// La rama actual. **Vacía si `HEAD` está suelto**, que es un estado y no un
  /// error: quien la use tiene que poder distinguirlo.
  Future<String> get ramaActual => _exigir(['branch', '--show-current']);

  /// Si el árbol tiene cambios sin commitear.
  Future<bool> get sucio async =>
      (await _exigir(['status', '--porcelain'])).isNotEmpty;
}
