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

  /// Las entradas del índice para estas rutas, **tal como están ahora**.
  ///
  /// Es la foto que permite dejar el índice como estaba si la rebanada se
  /// rechaza. La primera versión de esto usaba `git reset -- <rutas>`, que no
  /// restaura el índice anterior sino **HEAD**: si alguien tenía preparada una
  /// versión distinta de un archivo, se perdía. Lo encontró un review, y es la
  /// misma confusión de siempre —un comando que *se parece* a lo que quiero no
  /// es lo que quiero— cometida en el código que existía para reparar.
  ///
  /// **Un índice con conflictos sin resolver aborta.** Ahí una ruta tiene tres
  /// entradas, una por lado del merge, y `--cacheinfo` solo sabe escribir la
  /// de stage 0: prometer que se puede restaurar sería mentira. Además `git`
  /// mismo se niega a hacer un commit parcial durante un merge, así que la
  /// rebanada no iba a poder aplicarse igual.
  Future<Map<String, String>> _indiceDe(List<String> rutas) async {
    final salida = await _exigir(['ls-files', '--stage', '-z', '--', ...rutas]);
    final entradas = <String, String>{};
    for (final linea in salida.split('\u0000').where((s) => s.isNotEmpty)) {
      final tab = linea.indexOf('\t');
      if (tab < 0) {
        throw GitFallo('$programa ls-files --stage', 0,
            'no entiendo «$linea» en el índice');
      }
      // `<modo> <sha> <stage>` y después la ruta. La ruta puede tener espacios
      // y hasta tabuladores, así que se corta por el PRIMER tabulador.
      final campos = linea.substring(0, tab).split(' ');
      final ruta = linea.substring(tab + 1);
      if (campos.length != 3) {
        throw GitFallo('$programa ls-files --stage', 0,
            'no entiendo «$linea» en el índice');
      }
      if (campos[2] != '0') {
        throw RebanadaNoAplicable(
            '«$ruta» está en un merge sin resolver.',
            'Resolvé el merge y volvé a intentar. Con conflictos abiertos no '
                'se puede prometer que el índice quede como estaba.');
      }
      entradas[ruta] = '${campos[0]},${campos[1]},$ruta';
    }
    return entradas;
  }

  /// Deja el índice **exactamente** como lo dejó [_indiceDe], y lo comprueba.
  ///
  /// Se tocan solo las rutas de la rebanada: lo que alguien hubiera dejado
  /// preparado en otra parte no es nuestro. Una ruta que no estaba en el
  /// índice se saca con `--force-remove`, que no toca el árbol.
  ///
  /// **Si no puede restaurar, lo dice, y dice también qué se estaba
  /// rechazando.** La versión anterior se tragaba el fallo del `reset` en
  /// silencio — un reparador que no puede fallar es la misma clase de
  /// instrumento roto que este arnés existe para cazar. Pero un fallo de
  /// limpieza tampoco puede borrar el motivo del rechazo: van los dos.
  Future<void> _restaurarIndice(
      List<String> rutas, Map<String, String> antes, Object porQue) async {
    final args = <String>['update-index'];
    final quitar = <String>[];
    for (final ruta in rutas) {
      final entrada = antes[ruta];
      if (entrada != null) {
        args.addAll(['--cacheinfo', entrada]);
      } else {
        quitar.add(ruta);
      }
    }
    if (quitar.isNotEmpty) args.addAll(['--force-remove', '--', ...quitar]);

    final r = await _git(args);
    final ahora = r.exitCode == 0 ? await _indiceDe(rutas) : null;
    if (ahora == null || !_mismoIndice(antes, ahora)) {
      throw PromesaIncumplida(
          'dejar el índice como estaba al rechazar la rebanada (${porQue.runtimeType}: $porQue)',
          'un índice que no pude devolver a su lugar: '
              '${r.exitCode == 0 ? "quedó distinto" : "${r.stdout}${r.stderr}".trim()}');
    }
  }

  static bool _mismoIndice(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

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
    final indiceAntes = await _indiceDe(rutas);
    try {
      return await _aplicarSobreElIndice(slice, rutas);
    } catch (porQue) {
      await _restaurarIndice(rutas, indiceAntes, porQue);
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
