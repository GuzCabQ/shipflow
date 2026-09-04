/// El repositorio, contra `git` de verdad.
///
/// **No hay doble de `git`.** Es determinista, está instalado y es rápido: un
/// fake solo serviría para probar su ausencia, y para eso alcanza con cambiar
/// el nombre del ejecutable.
///
/// Sí hay **envoltorios de `git`**, y son otra cosa: no reemplazan a `git`,
/// le sacan una salvaguarda para que la promesa que se comprueba después
/// tenga cómo romperse. Un control que nunca se vio en rojo no está instalado.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

/// El puerto de `core`, con una respuesta declarada.
///
/// **No es el fake de `plugin_fake`, y es a propósito.** Depender de él
/// obligaría a `vcs` a ver un paquete que no es `core`, y `deps-hacia-core` lo
/// prohíbe con razón: `vcs` no puede conocer ningún stack, ni siquiera uno
/// falso. Esto no pretende ser un sustituto del puerto —para eso está la suite
/// de contrato, que corre contra la real y la falsa— sino un testigo declarado
/// de lo que `vcs` le pregunta.
class _PoliticaDeclarada implements ArtifactPolicy {
  final Set<String> generados;
  final Set<String> deBuild;
  const _PoliticaDeclarada(
      {this.generados = const {}, this.deBuild = const {}});

  @override
  bool isGenerated(String path) => generados.contains(path);

  @override
  bool isEditable(String path) =>
      path.trim().isNotEmpty && !isGenerated(path) && !deBuild.contains(path);
}

void main() {
  const politica = _PoliticaDeclarada(
      generados: {'generado.gen'}, deBuild: {'build/salida.txt'});

  test('el doble respeta las cláusulas del puerto que dice implementar', () {
    // Un doble que no cumple el contrato hace pasar la suite contra un
    // comportamiento que la implementación real nunca produce.
    expect(politica.isEditable('generado.gen'), isFalse,
        reason: 'cláusula 1: lo generado nunca es editable');
    expect(politica.isEditable('   '), isFalse,
        reason: 'cláusula 2: una ruta vacía no es editable');
    expect(politica.isEditable('a.txt'), isTrue);
  });

  late Directory raiz;
  late RepositorioGit repo;

  String correr(String cmd, List<String> args) =>
      (Process.runSync(cmd, args, workingDirectory: raiz.path).stdout as String)
          .trim();

  /// Sin recortar. Un nombre de archivo puede empezar con un espacio, y el
  /// helper de arriba se lo comía — el mismo error que se está corrigiendo,
  /// cometido en el instrumento que iba a comprobarlo.
  String correrCrudo(String cmd, List<String> args) =>
      Process.runSync(cmd, args, workingDirectory: raiz.path).stdout as String;

  void git(List<String> args) =>
      Process.runSync('git', args, workingDirectory: raiz.path);

  void escribir(String nombre, String contenido) =>
      File('${raiz.path}/$nombre').writeAsStringSync(contenido);

  /// Un `git` con una salvaguarda menos, para que el estado final pueda
  /// quedar mal aunque la herramienta salga con cero.
  String envoltorio(String nombre, String cuerpo) {
    final ruta = '${raiz.path}/$nombre';
    File(ruta).writeAsStringSync(cuerpo);
    Process.runSync('chmod', ['700', ruta]);
    return ruta;
  }

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('vcs_');
    repo = RepositorioGit(directorio: raiz.path, politica: politica);
    git(['init', '--initial-branch=main', '.']);
    git(['config', 'user.email', 'p@p']);
    git(['config', 'user.name', 'prueba']);
    escribir('a.txt', 'uno\n');
    escribir('b.txt', 'dos\n');
    git(['add', '-A']);
    git(['commit', '-m', 'base']);
  });

  tearDown(() => raiz.deleteSync(recursive: true));

  PullRequestSlice rebanada(List<String> files,
          {String intent = 'porque sí'}) =>
      PullRequestSlice(id: 'r1', intent: intent, files: files);

  group('la rama', () {
    test('se crea si no existe', () async {
      await repo.useBranch('shipflow/algo');
      expect(await repo.ramaActual, 'shipflow/algo');
    });

    test('pedirla dos veces NO falla', () async {
      // `--resume` la vuelve a pedir. Que la segunda vez falle rompería la
      // reanudación que ADR-014 exige.
      await repo.useBranch('shipflow/algo');
      escribir('a.txt', 'cambio\n');
      await repo.apply(rebanada(['a.txt']));
      await repo.useBranch('shipflow/algo');
      expect(await repo.ramaActual, 'shipflow/algo');
    });

    test('sin nombre no hay rama', () {
      expect(() => repo.useBranch('  '), throwsA(isA<RebanadaNoAplicable>()));
    });

    test('una ETIQUETA homónima no es la rama', () async {
      // El fallo que encontró un review. `rev-parse --verify` resolvía la
      // etiqueta, el adapter creía que la rama ya existía, y `switch` moría
      // con «a branch is expected, got tag». Una reanudación legítima quedaba
      // rota por un nombre que ni siquiera era una rama.
      git(['tag', 'release']);
      await repo.useBranch('release');
      expect(await repo.ramaActual, 'release');
      expect(correr('git', ['rev-parse', '--verify', 'refs/tags/release']),
          isNotEmpty,
          reason: 'la etiqueta sigue ahí: no la pisamos');
    });

    test('un SHA homónimo tampoco', () async {
      // Mismo agujero por otra puerta: el nombre resuelve, y no es una rama.
      //
      // Decía «SHA homónimo» y usaba `rama-<sha>`, que no es homónimo de nada
      // y jamás se habría resuelto como el commit: el test pasaba sin ejercer
      // su escenario. Lo encontró un review. La rama tiene que llamarse
      // EXACTAMENTE como el SHA abreviado.
      final sha = correr('git', ['rev-parse', '--short', 'HEAD']);
      expect(
          correr('git', ['rev-parse', '--verify', '--quiet', sha]), isNotEmpty,
          reason: 'la premisa: ese nombre YA resuelve a una revisión');
      await repo.useBranch(sha);
      expect(await repo.ramaActual, sha);
    });

    for (final (nombre, por) in const [
      ('HEAD', 'git lo reserva'),
      ('-x', 'parece una opción'),
      ('a..b', 'es sintaxis de rango'),
      ('x.lock', 'colisiona con el candado de refs'),
      ('con espacio', 'no es un nombre de ref'),
    ]) {
      test('«$nombre» se rechaza diciendo qué hacer — $por', () {
        expect(
            () => repo.useBranch(nombre),
            throwsA(isA<RebanadaNoAplicable>()
                .having((e) => e.queHacer, 'qué hacer', isNotEmpty)));
      });
    }

    test('«@{-1}» se rechaza aunque git lo valide', () async {
      // `check-ref-format --branch` no solo valida: EXPANDE. `@{-1}` sale con
      // código cero y devuelve otra rama. Un nombre que se convierte en otro
      // no es el nombre que nos pidieron, así que se compara la salida con la
      // entrada y no solo el código.
      await repo.useBranch('shipflow/previa');
      git(['switch', 'main']);
      expect(correr('git', ['check-ref-format', '--branch', '@{-1}']),
          'shipflow/previa',
          reason: 'la premisa: git expande, no rechaza');
      expect(
          () => repo.useBranch('@{-1}'), throwsA(isA<RebanadaNoAplicable>()));
    });

    test('si git deja HEAD suelto, la promesa se rompe fuerte', () async {
      // La postcondición. `switch` puede salir con cero sin dejarnos en la
      // rama pedida, y el puerto promete la rama, no la invocación.
      final falso = envoltorio('git-desprende', r'''#!/bin/sh
if [ "$2" = "switch" ]; then exec git "$1" switch --detach HEAD; fi
exec git "$@"
''');
      final torcido = RepositorioGit(
          directorio: raiz.path, politica: politica, programa: falso);
      await expectLater(
          torcido.useBranch('shipflow/x'),
          throwsA(isA<PromesaIncumplida>()
              .having((e) => e.quedo, 'quedó', contains('suelto'))));
    });
  });

  group('el commit', () {
    test('deja la revisión y la rama, y el árbol limpio', () async {
      await repo.useBranch('shipflow/x');
      escribir('a.txt', 'cambio\n');
      final rev = await repo.apply(rebanada(['a.txt']));
      expect(rev, hasLength(40));
      expect(await repo.sucio, isFalse);
      expect(correr('git', ['log', '-1', '--format=%s']), 'porque sí');
    });

    test('commitea EXACTAMENTE los archivos de la rebanada', () async {
      // La cláusula 1. Está medido que `git commit -- <rutas>` ignora el
      // índice: sin eso, algo que alguien dejó staged entraría al PR y el
      // artefacto de revisión lo declararía cubierto.
      await repo.useBranch('shipflow/x');
      escribir('a.txt', 'cambio A\n');
      escribir('b.txt', 'cambio B\n');
      git(['add', '--', 'b.txt']);

      await repo.apply(rebanada(['a.txt']));

      expect(
          correr('git', ['show', '--name-only', '--format=', 'HEAD']), 'a.txt');
      expect(
          correr('git', ['status', '--porcelain', 'b.txt']), contains('b.txt'),
          reason: 'lo que no estaba en la rebanada sigue sin commitear');
    });

    test('un archivo nuevo entra igual', () async {
      await repo.useBranch('shipflow/x');
      escribir('c.txt', 'nuevo\n');
      await repo.apply(rebanada(['c.txt']));
      expect(
          correr('git', ['show', '--name-only', '--format=', 'HEAD']), 'c.txt');
    });

    test('un BORRADO es un cambio, y entra', () async {
      // Si la única forma de nombrar un archivo fuera que exista en el árbol,
      // ninguna rebanada podría borrar nada.
      await repo.useBranch('shipflow/x');
      File('${raiz.path}/b.txt').deleteSync();
      await repo.apply(rebanada(['b.txt']));
      expect(
          correr('git', ['show', '--name-only', '--format=', 'HEAD']), 'b.txt');
      expect(correr('git', ['ls-files', 'b.txt']), isEmpty);
    });

    test('una rebanada SIN archivos no se commitea', () {
      // Un commit vacío afirma un cambio que no existe.
      expect(() => repo.apply(rebanada(const [])),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('una rebanada sin intención tampoco', () {
      // El `intent` es el mensaje del commit: sin él nadie puede revisar por
      // qué se hizo.
      expect(() => repo.apply(rebanada(['a.txt'], intent: '   ')),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('un archivo declarado que NO cambió rechaza la rebanada', () async {
      // «Exactamente» vale en los dos sentidos. Se comprobaba uno solo: que no
      // entrara nada de más. Un archivo declarado sin cambios pasaba en verde,
      // y eso es un plan que dijo que iba a tocar algo y no lo tocó.
      await repo.useBranch('shipflow/x');
      escribir('a.txt', 'cambio A\n');
      final antes = correr('git', ['rev-parse', 'HEAD']);
      await expectLater(
          repo.apply(rebanada(['a.txt', 'b.txt'])),
          throwsA(isA<RebanadaNoAplicable>()
              .having((e) => e.reason, 'razón', contains('b.txt'))));
      expect(correr('git', ['rev-parse', 'HEAD']), antes);
      expect(correr('git', ['diff', '--cached', '--name-only']), isEmpty,
          reason: 'el índice queda como estaba');
    });

    test('un archivo con acento se commitea, y no da falso incumplimiento',
        () async {
      // `git show --name-only` CITA lo que no es ASCII: `á.txt` salía como
      // `"\\303\\241.txt"` y la comparación fallaba contra un archivo
      // perfectamente válido. La salida de una herramienta no es el dato.
      await repo.useBranch('shipflow/x');
      escribir('á.txt', 'con acento\n');
      await repo.apply(rebanada(['á.txt']));
      expect(
          correr('git', ['show', '--name-only', '--format=', '-z', 'HEAD'])
              .split('\u0000')
              .where((s) => s.isNotEmpty),
          ['á.txt']);
    });

    test('un archivo con espacios y otro con salto de línea, también',
        () async {
      // El nombre prometía un salto de línea y el test solo hacía espacios.
      // Un caso que se anuncia y no se ejerce es peor que uno que falta: se
      // lee como cubierto. Lo encontró un review.
      await repo.useBranch('shipflow/x');
      escribir('con espacio.txt', 'x\n');
      escribir('con\nsalto.txt', 'y\n');
      await repo.apply(rebanada(['con espacio.txt', 'con\nsalto.txt']));
      expect(
          correr('git', ['show', '--name-only', '--format=', '-z', 'HEAD'])
              .split('\u0000')
              .where((s) => s.isNotEmpty)
              .toSet(),
          {'con espacio.txt', 'con\nsalto.txt'});
    });

    test('un DIRECTORIO borrado del disco no se cuela como borrado', () async {
      // `ls-files --error-unmatch -- dir` coincide por PREFIJO: con el
      // directorio ya borrado, el guardia lo daba por un archivo rastreado y
      // git commiteaba sus dos archivos. Es «coincide» confundido con «es»,
      // otra vez, del lado del borrado.
      await repo.useBranch('shipflow/x');
      Directory('${raiz.path}/dir').createSync();
      escribir('dir/x.txt', 'x\n');
      escribir('dir/y.txt', 'y\n');
      git(['add', '-A']);
      git(['commit', '-m', 'con directorio']);
      Directory('${raiz.path}/dir').deleteSync(recursive: true);

      final antes = correr('git', ['rev-parse', 'HEAD']);
      await expectLater(
          repo.apply(rebanada(['dir'])), throwsA(isA<RebanadaNoAplicable>()));
      expect(correr('git', ['rev-parse', 'HEAD']), antes);
    });

    test('el borrado de UN archivo rastreado sí entra', () async {
      // Control negativo del caso anterior: la corrección no puede volverse
      // «ningún borrado vale».
      await repo.useBranch('shipflow/x');
      File('${raiz.path}/b.txt').deleteSync();
      await repo.apply(rebanada(['b.txt']));
      expect(correr('git', ['ls-files', 'b.txt']), isEmpty);
    });

    test('un archivo que no existe NO se commitea en silencio', () async {
      // Antes moría con `GitFallo`, que es la herramienta quejándose. Ahora lo
      // rechaza el adapter y dice qué hacer: la ruta no nombra nada y git
      // tampoco la tenía, así que ni siquiera puede ser un borrado.
      await repo.useBranch('shipflow/x');
      expect(() => repo.apply(rebanada(['no/existe.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
    });
  });

  group('una ruta de la rebanada no es un pathspec', () {
    // El segundo fallo del review, reproducido con git de verdad: `--` evita
    // que la ruta se lea como una OPCIÓN, y no hace nada contra que se lea
    // como un PATRÓN. `files: ['*.txt']` commiteaba a.txt y b.txt.
    setUp(() async {
      await repo.useBranch('shipflow/x');
      escribir('a.txt', 'cambio A\n');
      escribir('b.txt', 'cambio B\n');
    });

    for (final (entrada, por) in const [
      ('*.txt', 'comodín'),
      (':(glob)*.txt', 'pathspec mágico'),
      (':!b.txt', 'pathspec negado'),
      ('.', 'el directorio entero'),
      ('sub', 'un directorio'),
      ('./a.txt', 'forma no canónica'),
      ('sub/../a.txt', 'forma no canónica con salto'),
      ('sub//x.txt', 'barra repetida'),
      ('..', 'sale del repositorio'),
    ]) {
      test('«$entrada» se rechaza — $por', () async {
        Directory('${raiz.path}/sub').createSync();
        escribir('sub/x.txt', 'x\n');
        await expectLater(
            repo.apply(rebanada([entrada])),
            throwsA(isA<RebanadaNoAplicable>()
                .having((e) => e.queHacer, 'qué hacer', isNotEmpty)));
        expect(correr('git', ['log', '-1', '--format=%s']), 'base',
            reason: 'no commiteó nada');
      });
    }

    test('una ruta absoluta se rechaza POR ABSOLUTA', () async {
      // El mensaje importa: «escribila relativa a la raíz» es lo accionable.
      // Sin comprobarlo, la guardia se podía borrar y el caso caía igual en el
      // rechazo genérico de forma no canónica — verde, y sin la guardia. Lo
      // encontró una mutación, no un test.
      await expectLater(
          repo.apply(rebanada(['${raiz.path}/a.txt'])),
          throwsA(isA<RebanadaNoAplicable>()
              .having((e) => e.reason, 'razón', contains('absoluta'))));
    });

    test('un archivo NO RASTREADO en el árbol no cuenta como de más', () async {
      // `commit --dry-run` lista los no rastreados aunque se le pase una ruta:
      // sin `--untracked-files=no` cualquier archivo suelto en el árbol daría
      // un falso incumplimiento.
      escribir('suelto.txt', 'nadie lo pidió\n');
      await repo.apply(rebanada(['a.txt']));
      expect(
          correr('git', ['show', '--name-only', '--format=', 'HEAD']), 'a.txt');
      expect(correr('git', ['status', '--porcelain', 'suelto.txt']),
          contains('suelto.txt'));
    });

    test('el mismo archivo dos veces se rechaza', () async {
      await expectLater(repo.apply(rebanada(['a.txt', 'a.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('CONTROL NEGATIVO: un archivo que se llama «*.txt» SÍ se commitea',
        () async {
      // La corrección no puede volverse «prohibido lo que parezca un patrón».
      // Con pathspecs literales el nombre raro es un nombre y nada más — y
      // antes de la corrección este caso era imposible.
      escribir('*.txt', 'raro\n');
      await repo.apply(rebanada(['*.txt']));
      expect(
          correr('git', ['show', '--name-only', '--format=', 'HEAD']), '*.txt');
    });

    test('si igual fuera a entrar algo de más, NO se commitea', () async {
      // El control que cubre el caso que nadie enumeró. El envoltorio le hace
      // a la consulta lo único que la puede engañar: contestar de más.
      //
      // Y lo que se comprueba no es solo que lance: es que **`HEAD` no se
      // haya movido**. Una postcondición que solo informa convierte un fallo
      // visible en un estado parcial.
      final falso = envoltorio('git-contesta-de-mas', r'''#!/bin/sh
if [ "$2" = "diff" ] && [ "$3" = "--cached" ] && [ "$4" = "--name-only" ]; then
  git "$@"
  printf 'intruso.txt'
  exit 0
fi
exec git "$@"
''');
      final antes = correr('git', ['rev-parse', 'HEAD']);
      final torcido = RepositorioGit(
          directorio: raiz.path, politica: politica, programa: falso);
      await expectLater(
          torcido.apply(rebanada(['a.txt'], intent: 'sabotaje')),
          throwsA(isA<PromesaIncumplida>()
              .having((e) => e.quedo, 'quedó', contains('intruso.txt'))));
      expect(correr('git', ['rev-parse', 'HEAD']), antes,
          reason: 'no puede quedar el commit que se acaba de declarar mal');
      expect(correr('git', ['diff', '--cached', '--name-only']), isEmpty,
          reason: 'ni el índice preparado para que alguien lo commitee a mano');
    });
  });

  group('lo que no es fuente no se commitea', () {
    setUp(() async => repo.useBranch('shipflow/x'));

    test('un archivo GENERADO se rechaza, y no se quita en silencio', () async {
      // El pseudocódigo dice «excluye generados del stage» y nunca dijo si en
      // silencio. Quitar un archivo que la rebanada declara rompería la
      // cláusula 1 —exactamente los archivos de la rebanada, en los dos
      // sentidos— así que se rechaza y se dice qué hacer.
      escribir('generado.gen', 'lo hizo la toolchain\n');
      final antes = correr('git', ['rev-parse', 'HEAD']);
      await expectLater(
          repo.apply(rebanada(['generado.gen'])),
          throwsA(isA<RebanadaNoAplicable>()
              .having((e) => e.reason, 'razón', contains('no es fuente'))
              .having((e) => e.queHacer, 'qué hacer', isNotEmpty)));
      expect(correr('git', ['rev-parse', 'HEAD']), antes);
    });

    test('un artefacto de BUILD también', () async {
      // `isEditable` y no `isGenerated`: `build/` no es generado y tampoco se
      // versiona. Preguntar por lo generado dejaba pasar la mitad de `N1-03`.
      Directory('${raiz.path}/build').createSync();
      escribir('build/salida.txt', 'x\n');
      await expectLater(repo.apply(rebanada(['build/salida.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('pero BORRAR un generado ya versionado sí se puede', () async {
      // La política dice qué no se escribe. Si un repositorio ya tenía un
      // generado commiteado, sacarlo es justamente lo que la política quiere,
      // y prohibirlo dejaba al arnés sin manera de limpiarlo. Lo señaló un
      // review; `D-094` se enmendó con esto.
      escribir('generado.gen', 'estaba versionado de antes\n');
      git(['add', '-A']);
      git(['commit', '-m', 'el generado, que ya estaba']);
      File('${raiz.path}/generado.gen').deleteSync();

      await repo.apply(rebanada(['generado.gen'], intent: 'lo saco'));
      expect(correr('git', ['ls-files', 'generado.gen']), isEmpty);
    });

    test('CONTROL NEGATIVO: la fuente pasa', () async {
      // La corrección no puede volverse «prohibido lo que se parezca».
      escribir('a.txt', 'cambio\n');
      await repo.apply(rebanada(['a.txt']));
      expect(
          correr('git', ['show', '--name-only', '--format=', 'HEAD']), 'a.txt');
    });

    test('se le pregunta al puerto, no a una lista de acá', () async {
      // `vcs` no sabe qué hace que algo sea generado: los sufijos viven en el
      // plugin del stack, que este paquete ni siquiera puede ver. Con otra
      // política, otro veredicto sobre el MISMO nombre.
      const alReves = _PoliticaDeclarada(generados: {'a.txt'});
      final otro = RepositorioGit(directorio: raiz.path, politica: alReves);
      escribir('a.txt', 'cambio\n');
      escribir('generado.gen', 'x\n');
      await expectLater(
          otro.apply(rebanada(['a.txt'])), throwsA(isA<RebanadaNoAplicable>()));
      await otro.apply(rebanada(['generado.gen']));
      expect(correr('git', ['show', '--name-only', '--format=', 'HEAD']),
          'generado.gen');
    });
  });

  group('los secretos se cortan ANTES del commit', () {
    setUp(() async => repo.useBranch('shipflow/x'));

    // Un caso por patrón, y la lista sale de la tabla del detector: un patrón
    // nuevo sin caso deja la suite en rojo en vez de entrar sin que nadie lo
    // haya visto fallar. Es la misma disciplina que el inventario de sabotajes.
    const muestras = <String, String>{
      'una clave privada': '-----BEGIN RSA PRIVATE KEY-----',
      'una clave de acceso de AWS': 'AKIAIOSFODNN7EXAMPLE',
      'un token de GitHub': 'ghp_0123456789abcdefghijklmnopqrstuvwxyzAB',
      'un token de Slack': 'xoxb-1234567890-abcdefghij',
      'una clave de API de Google': 'AIzaSyA0123456789abcdefghijklmnopqrstuv',
      'una clave secreta de Stripe': 'sk_live_0123456789abcdefghij',
      'una credencial asignada en el código':
          'const apiKey = "s7Kd93jfBq82Lm4zPq";',
    };

    test('la tabla de muestras cubre TODOS los patrones', () {
      // Sin esto, agregar un patrón sin muestra pasa desapercibido: el bucle de
      // abajo recorre las muestras, no los patrones.
      expect(muestras.keys.toSet(), DetectorDeSecretos.loQueReconoce.toSet());
    });

    for (final nombre in muestras.keys) {
      test('«$nombre» corta el commit', () async {
        escribir('ajustes.conf', 'final x = 1;\n${muestras[nombre]}\n');
        final antes = correr('git', ['rev-parse', 'HEAD']);
        await expectLater(
            repo.apply(rebanada(['ajustes.conf'])),
            throwsA(isA<RebanadaNoAplicable>()
                .having((e) => e.reason, 'razón', contains(nombre))
                .having((e) => e.queHacer, 'qué hacer', isNotEmpty)));
        expect(correr('git', ['rev-parse', 'HEAD']), antes,
            reason: 'un secreto commiteado no se des-commitea');
        expect(correr('git', ['diff', '--cached', '--name-only']), isEmpty,
            reason: 'ni queda preparado para que alguien lo commitee a mano');
      });
    }

    test('el mensaje NO lleva el secreto', () async {
      // INV-5 le exige eso a las credenciales del arnés. Un detector que para
      // avisarte de una filtración te la escribe en un log la filtra otra vez.
      const secreto = 'AKIAIOSFODNN7EXAMPLE';
      escribir('ajustes.conf', 'const k = "$secreto";\n');
      try {
        await repo.apply(rebanada(['ajustes.conf']));
        fail('tenía que rechazar');
      } on RebanadaNoAplicable catch (e) {
        expect([e.reason, e.queHacer, e.toString()].join(' '),
            isNot(contains(secreto)));
        expect(e.reason, contains('ajustes.conf'),
            reason: 'sí dice dónde, que es lo accionable');
      }
    });

    test('lo que se QUITA no cuenta: no lo introduce esta rebanada', () async {
      // La pregunta es «¿este cambio introduce un secreto?». Bloquear por una
      // línea que se está borrando impediría justamente arreglar la fuga.
      escribir('ajustes.conf', 'const k = "AKIAIOSFODNN7EXAMPLE";\n');
      git(['add', '-A']);
      git(['commit', '-m', 'la fuga, que ya estaba']);
      escribir('ajustes.conf', 'const k = String.fromEnvironment("K");\n');
      await repo.apply(rebanada(['ajustes.conf'], intent: 'saco la fuga'));
      expect(correr('git', ['log', '-1', '--format=%s']), 'saco la fuga');
    });

    test('un marcador de posición no es un secreto', () async {
      // El patrón que mira el NOMBRE es el que más falsos positivos puede dar,
      // y bloquea: un falso positivo acá cuesta caro.
      escribir(
          'ajustes.conf',
          'const apiKey = "YOUR_API_KEY_HERE";\n'
              'const password = "xxxxxxxxxxxxxxxx";\n'
              'const token = String.fromEnvironment("TOKEN");\n'
              // Y un valor CORTO: cuatro caracteres no son una credencial, y sin
              // el umbral el patrón que mira el nombre marcaría cualquier
              // asignación. Lo encontró una mutación, no un test.
              'const apiKey = "ab12";\n');
      await repo.apply(rebanada(['ajustes.conf']));
      expect(correr('git', ['show', '--name-only', '--format=', 'HEAD']),
          'ajustes.conf');
    });

    test('un BINARIO no bloquea, y es un límite declarado', () async {
      // Buscar una forma de texto dentro de bytes que no son texto no responde
      // nada. Queda como límite del detector, escrito y no disimulado.
      File('${raiz.path}/imagen.bin')
          .writeAsBytesSync([0, 1, 2, 255, 254, 0, 3]);
      // La premisa, comprobada y no asumida: git no emite NINGUNA línea de
      // contenido para un binario, así que no hay nada que saltar. Había una
      // rama que lo saltaba y una mutación la encontró muerta.
      git(['add', '--', 'imagen.bin']);
      final diff = correr('git', ['diff', '--cached', '--unified=0']);
      expect(diff, contains('Binary files'));
      expect(diff.split('\n').where((l) => l.startsWith('+')), isEmpty);

      await repo.apply(rebanada(['imagen.bin']));
      expect(correr('git', ['show', '--name-only', '--format=', 'HEAD']),
          'imagen.bin');
    });
  });

  group('las tres formas de colar un secreto que encontró un review', () {
    setUp(() async => repo.useBranch('shipflow/x'));

    test('contenido que empieza con ++, que git representa como +++', () async {
      // El detector descartaba toda línea `+++` dando por hecho que solo el
      // encabezado tiene esa forma. Un contenido `++ AKIA…` la tiene también.
      escribir('ajustes.conf', '++ AKIAIOSFODNN7EXAMPLE\n');
      git(['add', '--', 'ajustes.conf']);
      expect(correr('git', ['diff', '--cached', '--unified=0']),
          contains('+++ AKIAIOSFODNN7EXAMPLE'),
          reason: 'la premisa, con git de verdad');
      git(['reset', '--quiet']);

      final antes = correr('git', ['rev-parse', 'HEAD']);
      await expectLater(repo.apply(rebanada(['ajustes.conf'])),
          throwsA(isA<RebanadaNoAplicable>()));
      expect(correr('git', ['rev-parse', 'HEAD']), antes);
    });

    test('un `textconv` que oculta el contenido del diff', () async {
      // Una inspección de seguridad no puede leer una REPRESENTACIÓN que el
      // propio repositorio inspeccionado configura. Con un `textconv` que no
      // imprime nada, el detector recibía un diff vacío.
      final oculto = envoltorio('oculta-todo', '#!/bin/sh\nexit 0\n');
      git(['config', 'diff.oculto.textconv', oculto]);
      escribir('.gitattributes', '*.conf diff=oculto\n');
      escribir('ajustes.conf', 'const k = "AKIAIOSFODNN7EXAMPLE";\n');
      git(['add', '--', 'ajustes.conf']);
      expect(correr('git', ['diff', '--cached', '--unified=0']),
          isNot(contains('AKIA')),
          reason: 'la premisa: con textconv, el secreto no se ve');
      git(['reset', '--quiet']);

      final antes = correr('git', ['rev-parse', 'HEAD']);
      await expectLater(repo.apply(rebanada(['ajustes.conf'])),
          throwsA(isA<RebanadaNoAplicable>()));
      expect(correr('git', ['rev-parse', 'HEAD']), antes);
    });

    test('un driver de diff EXTERNO, que es otra evasión distinta', () async {
      // El review recomendó `--no-ext-diff` junto con `--no-textconv`. Medido,
      // son dos agujeros independientes: con `diff.<driver>.command` el
      // contenido también desaparece, y `--no-textconv` NO lo tapa. Sin este
      // caso, la bandera se podía borrar sin que nada se pusiera rojo.
      final mudo = envoltorio('diff-mudo', '#!/bin/sh\nexit 0\n');
      git(['config', 'diff.mudo.command', mudo]);
      escribir('.gitattributes', '*.conf diff=mudo\n');
      escribir('ajustes.conf', 'const k = "AKIAIOSFODNN7EXAMPLE";\n');
      git(['add', '--', 'ajustes.conf']);
      expect(correr('git', ['diff', '--cached', '--unified=0']),
          isNot(contains('AKIA')),
          reason: 'la premisa: el driver externo lo oculta');
      expect(
          correr('git', ['diff', '--cached', '--unified=0', '--no-textconv']),
          isNot(contains('AKIA')),
          reason: 'y --no-textconv NO alcanza: son dos agujeros distintos');
      git(['reset', '--quiet']);

      final antes = correr('git', ['rev-parse', 'HEAD']);
      await expectLater(repo.apply(rebanada(['ajustes.conf'])),
          throwsA(isA<RebanadaNoAplicable>()));
      expect(correr('git', ['rev-parse', 'HEAD']), antes);
    });

    test('NINGÚN gancho del usuario corre, ni los que `--no-verify` deja pasar',
        () async {
      // `--no-verify` frena `pre-commit` y `commit-msg`, y nada más. Un review
      // lo midió: `prepare-commit-msg` reescribía el archivo en el ÁRBOL y
      // `apply` devolvía éxito dejando el repositorio con la clave. El objeto
      // commiteado seguía siendo el inspeccionado —el índice aislado aguantó—
      // pero el costo declarado era falso.
      final hooks = Directory('${raiz.path}/.git/hooks')
        ..createSync(recursive: true);
      for (final gancho in ['pre-commit', 'prepare-commit-msg', 'commit-msg']) {
        File('${hooks.path}/$gancho').writeAsStringSync('#!/bin/sh\n'
            'printf \'const k = "AKIAIOSFODNN7EXAMPLE";\\n\' > ajustes.conf\n'
            'git add -- ajustes.conf\n'
            'exit 0\n');
        Process.runSync('chmod', ['700', '${hooks.path}/$gancho']);
      }
      File('${hooks.path}/post-commit').writeAsStringSync(
          '#!/bin/sh\n: > .git/corrio-post-commit\nexit 0\n');
      Process.runSync('chmod', ['700', '${hooks.path}/post-commit']);

      escribir('ajustes.conf', 'inocente\n');
      await repo.apply(rebanada(['ajustes.conf']));

      expect(correr('git', ['show', 'HEAD:ajustes.conf']), 'inocente',
          reason: 'se commitea el objeto que se escaneó, no otro');
      expect(File('${raiz.path}/ajustes.conf').readAsStringSync(), 'inocente\n',
          reason: 'y el árbol tampoco queda con la clave');
      expect(File('${raiz.path}/.git/corrio-post-commit').existsSync(), isFalse,
          reason: 'post-commit tampoco: el costo declarado dice NINGUNO');
    });

    test('ni un gancho dejado en NUESTRO directorio de ganchos', () async {
      // `core.hooksPath` apunta a un directorio nuestro que se recrea vacío en
      // cada corrida. Si no se recreara, algo dejado ahí correría igual — y
      // «ningún gancho del usuario corre» dejaría de ser cierto por la puerta
      // que abrimos nosotros.
      final nuestro = Directory('${raiz.path}/.git/index.shipflow.sin-ganchos')
        ..createSync(recursive: true);
      File('${nuestro.path}/pre-commit').writeAsStringSync('#!/bin/sh\n'
          'printf \'const k = "AKIAIOSFODNN7EXAMPLE";\\n\' > ajustes.conf\n'
          'git add -- ajustes.conf\n'
          'exit 0\n');
      Process.runSync('chmod', ['700', '${nuestro.path}/pre-commit']);

      escribir('ajustes.conf', 'inocente\n');
      await repo.apply(rebanada(['ajustes.conf']));
      expect(
          File('${raiz.path}/ajustes.conf').readAsStringSync(), 'inocente\n');
    });

    test('un gancho `pre-commit` que cambia el contenido DESPUÉS', () async {
      // El peor de los tres: no es concurrencia futura, es la propia operación
      // invocando al gancho adentro suyo. El escaneo veía «inocente» y el
      // commit se llevaba la clave.
      final hooks = Directory('${raiz.path}/.git/hooks')
        ..createSync(recursive: true);
      File('${hooks.path}/pre-commit').writeAsStringSync('#!/bin/sh\n'
          'printf \'const k = "AKIAIOSFODNN7EXAMPLE";\\n\' > ajustes.conf\n'
          'git add -- ajustes.conf\n'
          'exit 0\n');
      Process.runSync('chmod', ['700', '${hooks.path}/pre-commit']);

      escribir('ajustes.conf', 'inocente\n');
      await repo.apply(rebanada(['ajustes.conf']));
      expect(correr('git', ['show', 'HEAD:ajustes.conf']), 'inocente',
          reason: 'se commitea el objeto que se escaneó, no otro');
    });
  });

  group('cuando el commit sale bien y lo de después no', () {
    setUp(() async => repo.useBranch('shipflow/x'));

    test('si el índice real no se puede sincronizar, NO es un éxito', () async {
      // Son dos efectos distintos: la revisión existe y el índice quedó
      // desincronizado. El `reset` usaba la llamada que NO lanza, así que
      // `apply` devolvía la revisión como si todo hubiera salido bien.
      final falso = envoltorio('git-reset-roto', r'''#!/bin/sh
if [ "$2" = "reset" ]; then exit 91; fi
exec git "$@"
''');
      escribir('a.txt', 'cambio\n');
      final torcido = RepositorioGit(
          directorio: raiz.path, politica: politica, programa: falso);
      await expectLater(
          torcido.apply(rebanada(['a.txt'])),
          throwsA(isA<PromesaIncumplida>()
              .having((e) => e.quedo, 'nombra la revisión', contains('creada'))
              .having((e) => e.quedo, 'y qué quedó sin hacer',
                  contains('sin sincronizar'))));
      expect(correr('git', ['log', '-1', '--format=%s']), 'porque sí',
          reason: 'el commit se hizo, y no se deshace: eso salió bien');
    });

    test('un archivo cuyo nombre empieza con espacio no se corrompe', () async {
      // Las salidas separadas por NUL son bytes. `_exigir` las recortaba, y
      // « a.txt» se convertía en «a.txt»: el mismo archivo escrito de dos
      // maneras por culpa nuestra, y una PromesaIncumplida absurda.
      escribir(' a.txt', 'con espacio adelante\n');
      await repo.apply(rebanada([' a.txt']));
      expect(
          correrCrudo('git', ['show', '--name-only', '--format=', '-z', 'HEAD'])
              .split('\u0000')
              .where((s) => s.isNotEmpty),
          [' a.txt']);
    });
  });

  group('el detector, a solas', () {
    const detector = DetectorDeSecretos();

    test('un diff vacío no encuentra nada, y tampoco lanza', () {
      expect(detector.revisar('', archivo: 'x.txt'), isEmpty);
    });

    test('dice el archivo y la LÍNEA', () {
      final h = detector.revisar(
          'diff --git a/x.txt b/x.txt\n'
          '--- a/x.txt\n+++ b/x.txt\n'
          '@@ -0,0 +12,2 @@\n'
          '+inocente\n'
          '+AKIAIOSFODNN7EXAMPLE\n',
          archivo: 'x.txt');
      expect(h, hasLength(1));
      expect(h.single.archivo, 'x.txt');
      expect(h.single.linea, 13);
    });

    test('un encabezado de hunk que no se entiende LANZA', () {
      // «No encontré nada» y «no pude mirar» no se pueden confundir. Devolver
      // cero acá diría que el archivo está limpio sin haberlo leído.
      expect(
          () => detector.revisar(
              'diff --git a/x.txt b/x.txt\n'
              '@@ esto no es un encabezado @@\n'
              '+AKIAIOSFODNN7EXAMPLE\n',
              archivo: 'x.txt'),
          throwsA(isA<DiffIlegible>()));
    });

    test('una línea que encaja en DOS patrones es UN hallazgo', () {
      // `const apiKey = "AKIA…"` encaja por la forma del valor y por el nombre
      // al que se asigna. Contarla dos veces infla el «hay N secretos» del
      // mensaje, que es lo único cuantitativo que se le dice a quien lo lee.
      // Lo encontró una mutación: cambiar el `break` por `continue` no ponía
      // nada en rojo.
      final h = detector.revisar(
          'diff --git a/x.txt b/x.txt\n'
          '@@ -0,0 +1 @@\n'
          '+const apiKey = "AKIAZZZZ111122223333";\n',
          archivo: 'x.txt');
      expect(h, hasLength(1));
    });

    test('el encabezado +++ no se confunde con una línea agregada', () {
      // Lo que distingue el encabezado no es su forma: es que está ANTES del
      // primer `@@`.
      expect(
          detector.revisar(
              'diff --git a/x b/x\n'
              '+++ b/AKIAIOSFODNN7EXAMPLE\n'
              '@@ -0,0 +1 @@\n'
              '+limpio\n',
              archivo: 'x.txt'),
          isEmpty);
    });

    test('pero una línea de CONTENIDO que empieza con ++ sí se mira', () {
      // El agujero exacto que encontró un review: un contenido `++ AKIA…` se
      // representa como `+++ AKIA…`, y descartarlo por su forma lo dejaba
      // pasar. Está medido con git de verdad.
      final h = detector.revisar(
          '@@ -0,0 +1 @@\n'
          '+++ AKIAIOSFODNN7EXAMPLE\n',
          archivo: 'x.txt');
      expect(h, hasLength(1));
      expect(h.single.linea, 1);
    });
  });

  group('el índice del usuario no se toca', () {
    // El índice es del usuario. Antes esto se conseguía fotografiándolo y
    // reponiéndolo tras cada fallo; ahora `apply` trabaja sobre un índice
    // APARTE y no hay nada que reponer. Los casos siguen: lo que cambió es
    // que pasan por construcción y no por reparación.
    // El índice es del usuario. Una rebanada rechazada no hizo nada, así que
    // no puede haber cambiado nada — y la primera versión de la limpieza usaba
    // `git reset -- <rutas>`, que restaura desde HEAD y no desde el índice
    // anterior. Está medido: con una versión distinta preparada, la perdía.

    setUp(() async => repo.useBranch('shipflow/x'));

    test('una versión preparada distinta de HEAD sobrevive al rechazo',
        () async {
      escribir('a.txt', 'LA QUE PREPARÓ EL USUARIO\n');
      git(['add', '--', 'a.txt']);
      escribir('a.txt', 'la que hay en el árbol\n');
      final preparada = correr('git', ['show', ':a.txt']);
      expect(preparada, contains('PREPARÓ'), reason: 'la premisa');

      // b.txt no tiene cambios: la rebanada se rechaza por «ni uno menos».
      await expectLater(repo.apply(rebanada(['a.txt', 'b.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));

      expect(correr('git', ['show', ':a.txt']), preparada,
          reason: 'el índice del usuario no es nuestro para pisarlo');
      expect(correr('git', ['status', '--porcelain', '--', 'b.txt']), isEmpty);
    });

    test('una ruta que NO estaba preparada no queda preparada', () async {
      escribir('nueva.txt', 'nueva\n');
      await expectLater(repo.apply(rebanada(['nueva.txt', 'b.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
      expect(correr('git', ['diff', '--cached', '--name-only']), isEmpty,
          reason: 'el add la había preparado; el rechazo la saca');
      expect(File('${raiz.path}/nueva.txt').existsSync(), isTrue,
          reason: 'sin tocar el árbol');
    });

    test('un `add` que falla A MEDIAS tampoco deja rastro', () async {
      // Está medido: `git add -- a.txt ignorado.txt` sale con 1 **y deja
      // a.txt preparado igual**. La limpieza estaba solo en la rama del
      // rechazo por contenido, así que este camino se escapaba entero.
      escribir('.gitignore', 'ignorado.txt\n');
      git(['add', '-A']);
      git(['commit', '-m', 'ignore']);
      escribir('a.txt', 'cambio\n');
      escribir('ignorado.txt', 'x\n');

      await expectLater(repo.apply(rebanada(['a.txt', 'ignorado.txt'])),
          throwsA(isA<GitFallo>()));
      expect(correr('git', ['diff', '--cached', '--name-only']), isEmpty,
          reason: 'a.txt no puede quedar preparado por un add que falló');
    });

    test('un merge sin resolver aborta antes de tocar nada', () async {
      // Ahí una ruta tiene tres entradas en el índice y `--cacheinfo` solo
      // sabe escribir la de stage 0: prometer que se restaura sería mentira.
      git(['switch', '-c', 'otra']);
      escribir('a.txt', 'de la otra rama\n');
      git(['commit', '-am', 'otra']);
      git(['switch', 'shipflow/x']);
      escribir('a.txt', 'de esta rama\n');
      git(['commit', '-am', 'esta']);
      git(['merge', 'otra']);
      expect(correr('git', ['ls-files', '--stage', '--', 'a.txt']),
          contains(' 1	'),
          reason: 'la premisa: hay conflicto');

      await expectLater(
          repo.apply(rebanada(['a.txt'])),
          throwsA(isA<RebanadaNoAplicable>()
              .having((e) => e.reason, 'razón', contains('merge'))));
    });

    test('una entrada `intent-to-add` sigue siendo intent-to-add', () async {
      // El caso que rompió la versión anterior. `git add --intent-to-add` deja
      // una entrada que en `ls-files --stage` se ve IDÉNTICA a una normal con
      // el blob vacío: reponerla desde esa lectura la convertía en un archivo
      // vacío preparado de verdad, que el usuario nunca preparó. Por eso la
      // foto son los bytes del índice y no su lectura.
      escribir('nueva.txt', 'nueva\n');
      git(['add', '--intent-to-add', '--', 'nueva.txt']);
      escribir('a.txt', 'cambio\n');
      final antes = correr('git', ['status', '--porcelain']);
      // Lo que distingue `intent-to-add` de un archivo vacío preparado no es
      // cómo lo pinta `status` —`correr` recorta el espacio inicial de ` A`—
      // sino que NO hay contenido preparado. Esa es la premisa que importa.
      expect(antes, contains('A nueva.txt'), reason: 'la premisa: git la ve');
      expect(correr('git', ['diff', '--cached', '--name-only']), isEmpty,
          reason: 'la premisa: intent-to-add NO es contenido preparado');

      await expectLater(repo.apply(rebanada(['a.txt', 'b.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));

      expect(correr('git', ['status', '--porcelain']), antes);
      expect(correr('git', ['diff', '--cached', '--name-only']), isEmpty,
          reason:
              'no puede quedar preparado un archivo vacío que nadie preparó');
    });

    test('un `skip-worktree` tampoco se pierde', () async {
      // Otro estado que `ls-files --stage` no muestra. No se enumera cada
      // bandera del índice: se reponen los bytes, y por eso están todas.
      git(['update-index', '--skip-worktree', '--', 'b.txt']);
      final antes = correr('git', ['ls-files', '-v', '--', 'b.txt']);
      expect(antes, startsWith('S'), reason: 'la premisa: S = skip-worktree');

      escribir('a.txt', 'cambio\n');
      await expectLater(repo.apply(rebanada(['a.txt', 'nada.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
      expect(correr('git', ['ls-files', '-v', '--', 'b.txt']), antes);
    });
  });

  group('cuando git no está', () {
    test('la ausencia se nota, y dice qué se intentó', () async {
      // Una herramienta que no está no puede leerse como que no había nada que
      // hacer. Es la misma exigencia que ADR-011 le hace a un verificador.
      final sinGit = RepositorioGit(
          directorio: raiz.path, politica: politica, programa: 'no-existe-git');
      await expectLater(
        sinGit.useBranch('x'),
        throwsA(isA<GitFallo>().having(
            (e) => e.invocacion, 'invocación', contains('no-existe-git'))),
      );
    });
  });
}
