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

class RepositorioGit implements ChangeSink {
  /// La raíz del repositorio sobre el que se trabaja.
  final String directorio;

  /// El ejecutable. **Es inyectable solo para poder probar que su ausencia se
  /// nota**: una herramienta que no está no puede leerse como que no había
  /// nada que hacer.
  final String programa;

  const RepositorioGit({required this.directorio, this.programa = 'git'});

  /// **Todo pasa por `--literal-pathspecs`.** Sin eso, `git` lee cada ruta
  /// como un patrón: `*.txt` commitea dos archivos y `:(glob)…` commitea lo
  /// que quiera. Va acá y no en las llamadas que reciben rutas para que un
  /// comando nuevo no pueda olvidarse; es inocuo en los que no las reciben.
  ///
  /// El efecto secundario es el que hacía falta: con pathspecs literales, un
  /// archivo que de verdad se llame `*.txt` se commitea, y hoy no se puede.
  Future<ProcessResult> _git(List<String> args) async {
    final completos = ['--literal-pathspecs', ...args];
    final ProcessResult r;
    try {
      r = await Process.run(programa, completos,
          workingDirectory: directorio,
          stdoutEncoding: utf8,
          stderrEncoding: utf8);
    } on ProcessException catch (e) {
      throw GitFallo('$programa ${completos.join(" ")}', -1,
          '${e.message} (${e.executable})');
    }
    return r;
  }

  /// Corre `git` y **exige que haya salido bien**. Un código distinto de cero
  /// que se ignora es un cambio que se cree hecho y no está.
  Future<String> _exigir(List<String> args) async {
    final r = await _git(args);
    if (r.exitCode != 0) {
      throw GitFallo('$programa --literal-pathspecs ${args.join(" ")}',
          r.exitCode, '${r.stdout}${r.stderr}'.trim());
    }
    return (r.stdout as String).trim();
  }

  @override
  Future<void> useBranch(String name) async {
    if (name.trim().isEmpty) {
      throw const RebanadaNoAplicable('El nombre de rama está vacío.',
          'Dale un nombre; una rama sin nombre no se puede retomar después.');
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
              'como `@{-1}`.');
    }

    // **La pregunta es si existe la RAMA, no si el nombre resuelve a algo.**
    // `rev-parse --verify` resolvía cualquier revisión: con una etiqueta
    // homónima decía «ya existe» y `switch` fallaba con «a branch is expected,
    // got tag». Una reanudación legítima quedaba rota por un nombre que ni
    // siquiera era una rama.
    final existe =
        await _git(['show-ref', '--verify', '--quiet', 'refs/heads/$name']);

    // **Idempotente**: la orquestación la pide al empezar y `--resume` la
    // vuelve a pedir. Que la segunda vez falle rompería la reanudación que
    // ADR-014 exige.
    await _exigir(existe.exitCode == 0
        ? ['switch', '--', name]
        : ['switch', '--create', name]);

    // Y **se comprueba dónde quedamos.** `git switch` tiene formas de salir
    // con cero sin dejarnos en la rama pedida —`--detach` es la evidente— y
    // el puerto promete la rama, no la invocación.
    final actual = await ramaActual;
    if (actual != name) {
      throw PromesaIncumplida('quedar en la rama «$name»',
          actual.isEmpty ? 'HEAD suelto, sin rama' : 'la rama «$actual»');
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
      throw no('está en blanco.',
          'Una entrada vacía no nombra nada. Sacala de la rebanada.');
    }
    if (entrada.startsWith('/')) {
      throw no('es una ruta absoluta.',
          'Nombrala relativa a la raíz del repositorio, como la nombra git.');
    }
    final partes = entrada.split('/');
    if (partes.any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw no('no está en la forma en que git nombra un archivo.',
          'Escribila sin `./`, sin `..` y sin barras repetidas ni al final.');
    }

    // Qué hay del otro lado. `followLinks: false` a propósito: `git` guarda un
    // enlace como enlace y no mira a dónde apunta, así que uno que apunte a un
    // directorio sigue siendo un archivo para esto.
    final tipo =
        FileSystemEntity.typeSync('$directorio/$entrada', followLinks: false);
    if (tipo == FileSystemEntityType.directory) {
      throw no(
          'es un directorio.',
          'La rebanada nombra archivos, no carpetas: un directorio arrastra '
              'todo lo que tenga adentro, incluido lo que nadie planeó. '
              'Nombrá los archivos uno por uno.');
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
            'arrastrando todo lo que tenía adentro.');
      }
    }
    return entrada;
  }

  /// Qué rutas entrarían al commit si se hiciera ahora. **Sin hacerlo.**
  ///
  /// `git commit --dry-run --porcelain` responde exactamente eso y no toca
  /// nada. La primera columna es lo que va al commit y la segunda lo que se
  /// queda en el árbol: está medido que un archivo que alguien dejó staged y
  /// que la rebanada no nombra sale con la primera en blanco. La cláusula 1
  /// sostenida por la propia herramienta, en vez de por una creencia sobre
  /// ella.
  ///
  /// **`-z` no es un detalle de formato.** Sin él git *cita* las rutas que no
  /// son ASCII: `á.txt` sale como la cadena `"\303\241.txt"`, y comparar eso
  /// contra la ruta declarada fallaba sobre un archivo perfectamente válido.
  /// Lo encontró un review, y es la misma clase de error que todo lo demás
  /// acá: la salida de una herramienta no es el dato, es una representación
  /// del dato.
  Future<Set<String>> _loQueEntraria(List<String> rutas) async {
    final r = await _git([
      'commit',
      '--dry-run',
      '--porcelain',
      '-z',
      '--untracked-files=no',
      '--',
      ...rutas,
    ]);
    // Sale 1 cuando no hay nada que commitear, y eso es una respuesta.
    if (r.exitCode != 0 && r.exitCode != 1) {
      throw GitFallo('$programa commit --dry-run', r.exitCode,
          '${r.stdout}${r.stderr}'.trim());
    }
    final campos = (r.stdout as String)
        .split('\u0000')
        .where((s) => s.isNotEmpty)
        .toList();
    final entran = <String>{};
    for (var i = 0; i < campos.length; i++) {
      final campo = campos[i];
      if (campo.length < 4) {
        throw GitFallo('$programa commit --dry-run', r.exitCode,
            'no entiendo «$campo» en el estado que devolvió');
      }
      final x = campo[0], y = campo[1];
      // Solo la primera columna: es lo que va al commit. Lo no rastreado no
      // aparece porque se lo pedimos a git con `--untracked-files=no`, y no
      // se filtra acá además — una segunda defensa que nunca puede fallar no
      // es defensa, es una línea que se lee como si protegiera algo.
      final entra = x != ' ';
      // Un renombrado trae la ruta de origen en un campo aparte y toca las
      // dos: hay que consumir el campo, y contarlo.
      if (x == 'R' || x == 'C' || y == 'R' || y == 'C') {
        i++;
        if (i < campos.length && entra) entran.add(campos[i]);
      }
      if (entra) entran.add(campo.substring(3));
    }
    return entran;
  }

  /// El índice, **entero y en bytes**, más lo que `git` ve.
  ///
  /// La primera versión guardaba `modo`, `objeto` y `ruta` leídos con
  /// `ls-files --stage` y los reponía con `update-index --cacheinfo`. Un review
  /// lo rompió con un caso legítimo: `git add --intent-to-add` deja una entrada
  /// que en `ls-files` se ve **idéntica** a una normal con el blob vacío, y
  /// reponerla con `--cacheinfo` la convierte en un archivo vacío de verdad. El
  /// usuario terminaba con algo preparado que nunca preparó.
  ///
  /// El índice tiene más estado del que `ls-files` muestra —`intent-to-add`,
  /// `skip-worktree`, `assume-unchanged`, las tres entradas de un conflicto—,
  /// así que **cualquier reconstrucción a partir de su lectura pierde algo**.
  /// Es la lección de todo este archivo otra vez: no reimplementar la
  /// semántica de la herramienta, usar su estado.
  ///
  /// Se guardan dos cosas: los bytes, que son lo que se repone, y la vista de
  /// `git status`, que es contra lo que se comprueba que reponerlos sirvió.
  Future<({List<int>? bytes, String vista})> _fotoDelIndice() async {
    final archivo = File(await _rutaDelIndice());
    return (
      bytes: archivo.existsSync() ? archivo.readAsBytesSync() : null,
      vista: await _exigir(['status', '--porcelain', '-z']),
    );
  }

  /// Dónde vive el archivo del índice. **Se le pregunta a `git`**: no siempre
  /// es `.git/index` —un worktree enlazado lo tiene en otro lado.
  Future<String> _rutaDelIndice() async {
    final relativa = await _exigir(['rev-parse', '--git-path', 'index']);
    return relativa.startsWith('/') ? relativa : '$directorio/$relativa';
  }

  /// Devuelve el índice a la foto, **y comprueba que haya servido**.
  ///
  /// Se escribe a un temporal y se renombra encima, porque `rename` es
  /// atómico: si el proceso muere a mitad no queda un índice cortado. Un
  /// repositorio recién creado no tiene índice todavía, y ahí «reponer» es
  /// borrarlo.
  ///
  /// **Todo está envuelto.** Antes, un fallo acá —de `git`, del disco, de la
  /// ruta— se propagaba solo y el motivo del rechazo se perdía: la promesa de
  /// informar las dos cosas se cumplía solo cuando la verificación llegaba a
  /// correr. Lo encontró un review. Ahora **cualquier** excepción de la
  /// reposición sale como [PromesaIncumplida] nombrando las dos.
  Future<void> _restaurarIndice(
      ({List<int>? bytes, String vista}) foto, Object porQue) async {
    Object? problema;
    try {
      final archivo = File(await _rutaDelIndice());
      if (foto.bytes == null) {
        if (archivo.existsSync()) archivo.deleteSync();
      } else {
        final temporal = File('${archivo.path}.shipflow-restaura');
        temporal.writeAsBytesSync(foto.bytes!, flush: true);
        temporal.renameSync(archivo.path);
      }
      // **Contra lo que ve `git`, no contra los bytes que acabo de escribir.**
      // Comparar el archivo contra sí mismo solo prueba que el disco no miente.
      final vista = await _exigir(['status', '--porcelain', '-z']);
      if (vista != foto.vista) {
        problema = 'git ve el repositorio distinto de como estaba';
      }
    } catch (e) {
      problema = e;
    }
    if (problema != null) {
      throw PromesaIncumplida(
          'dejar el índice como estaba al rechazar la rebanada '
              '(${porQue.runtimeType}: $porQue)',
          'un índice que no pude devolver a su lugar: $problema');
    }
  }

  /// Un merge sin resolver no admite rebanadas.
  ///
  /// **Ya no es por la reposición** —los bytes del índice traen las tres
  /// entradas del conflicto sin que haya que entenderlas—. Es porque `git`
  /// mismo se niega: *«cannot do a partial commit during a merge»*. Está acá
  /// para decirlo antes y decir qué hacer, que es lo que un `GitFallo` crudo no
  /// hace.
  Future<void> _exigirSinConflictos() async {
    if ((await _exigir(['ls-files', '--unmerged', '-z'])).isNotEmpty) {
      throw const RebanadaNoAplicable(
          'hay un merge sin resolver.',
          'Resolvé el merge y volvé a intentar: git no hace un commit parcial '
              'con conflictos abiertos, y una rebanada es siempre parcial.');
    }
  }

  @override
  Future<String> apply(PullRequestSlice slice) async {
    if (slice.files.isEmpty) {
      throw const RebanadaNoAplicable(
          'La rebanada no nombra ningún archivo.',
          'Un commit vacío afirma un cambio que no existe. Poné los archivos '
              'en la rebanada, o no la apliques.');
    }
    if (slice.intent.trim().isEmpty) {
      throw const RebanadaNoAplicable(
          'La rebanada no dice por qué existe.',
          'El `intent` es lo que ADR-014 llama intención, y es el mensaje del '
              'commit: sin él nadie puede revisar por qué se hizo.');
    }

    final rutas = <String>[];
    for (final entrada in slice.files) {
      final ruta = await _rutaDeArchivo(entrada);
      if (rutas.contains(ruta)) {
        throw RebanadaNoAplicable(
            '«$entrada» está dos veces en la rebanada.',
            'La rebanada declara un conjunto de archivos. Repetir uno no '
                'commitea nada distinto y vuelve ambiguo el alcance.');
      }
      rutas.add(ruta);
    }

    // **La foto del índice, antes de tocarlo.** Todo lo que sigue está dentro
    // de una frontera: si algo falla —el propio `add`, la consulta, el
    // commit— el índice vuelve a esto. Antes la limpieza estaba solo en la
    // rama del rechazo, así que un `add` que fallaba a medias dejaba staged
    // lo que había alcanzado a preparar. Está medido: `git add -- a.txt
    // ignorado.txt` sale con 1 **y deja `a.txt` preparado igual**.
    //
    // En el camino de éxito no se repone nada, y es lo correcto: está medido
    // que `git commit -- <ruta>` sincroniza el índice de esa ruta con el nuevo
    // `HEAD`. El adapter se comporta como `git`, no como una idea de `git`.
    await _exigirSinConflictos();
    final foto = await _fotoDelIndice();
    try {
      return await _aplicarSobreElIndice(slice, rutas);
    } catch (porQue) {
      await _restaurarIndice(foto, porQue);
      rethrow;
    }
  }

  /// El cuerpo de [apply], **con el índice ya fotografiado**. Todo lo de acá
  /// puede lanzar: quien llama devuelve el índice a su lugar.
  Future<String> _aplicarSobreElIndice(
      PullRequestSlice slice, List<String> rutas) async {
    await _exigir(['add', '--', ...rutas]);

    // **Se le pregunta a git qué va a commitear, ANTES de commitear.**
    //
    // Esto estaba después, comparando el commit ya hecho, y un review lo cobró
    // con el argumento correcto: una postcondición que solo puede informar
    // convierte un fallo visible en un estado parcial. La excepción decía la
    // verdad y `HEAD` se había movido igual. Acá no se comprueba el resultado
    // de la operación: se comprueba la operación antes de que exista, que es
    // lo único que deja el invariante en pie.
    //
    // **Queda un hueco declarado**: entre la pregunta y el commit, nada más
    // tiene que tocar el árbol. Eso es el lock de concurrencia, que el plan ya
    // tiene como decisión abierta `A-5` para la fase 4. No se disimula acá.
    final entraria = await _loQueEntraria(rutas);
    final pedidas = rutas.toSet();
    final demas = entraria.difference(pedidas).toList()..sort();
    final faltan = pedidas.difference(entraria).toList()..sort();
    if (demas.isNotEmpty || faltan.isNotEmpty) {
      if (demas.isNotEmpty) {
        // Nadie enumeró este caso: la rota es la cláusula, no la rebanada.
        throw PromesaIncumplida('commitear exactamente ${rutas.join(", ")}',
            'un commit que además tocaría ${demas.join(", ")}');
      }
      // Esto en cambio sí es la rebanada: declaró algo que no cambió.
      throw RebanadaNoAplicable(
          'la rebanada declara ${faltan.join(", ")} y no hay nada que '
              'commitear ahí.',
          'La cláusula dice EXACTAMENTE, y eso vale en los dos sentidos: un '
              'archivo declarado que no cambió es un plan que no pasó. Sacalo '
              'de la rebanada, o revisá por qué no se escribió.');
    }

    // **`-- <rutas>` es la cláusula 1 hecha comando.** Sin eso, `git commit`
    // se lleva lo que hubiera quedado en el índice de antes, y el artefacto de
    // revisión declararía cubiertos cambios que nadie planeó. Está medido: con
    // rutas explícitas, un archivo staged de antes queda afuera.
    await _exigir(['commit', '--message', slice.intent, '--', ...rutas]);

    return _exigir(['rev-parse', 'HEAD']);
  }

  /// La rama actual. **Vacía si `HEAD` está suelto**, que es un estado y no un
  /// error: quien la use tiene que poder distinguirlo.
  Future<String> get ramaActual => _exigir(['branch', '--show-current']);

  /// Si el árbol tiene cambios sin commitear.
  Future<bool> get sucio async =>
      (await _exigir(['status', '--porcelain'])).isNotEmpty;
}
