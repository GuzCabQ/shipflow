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

void main() {
  late Directory raiz;
  late RepositorioGit repo;

  String correr(String cmd, List<String> args) =>
      (Process.runSync(cmd, args, workingDirectory: raiz.path).stdout as String)
          .trim();

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
    repo = RepositorioGit(directorio: raiz.path);
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
      final torcido = RepositorioGit(directorio: raiz.path, programa: falso);
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
      // a la consulta previa lo único que la puede engañar: contestar de más.
      //
      // Y lo que se comprueba no es solo que lance: es que **`HEAD` no se
      // haya movido**. Antes esto estaba después del commit, y un review lo
      // cobró — una postcondición que solo informa convierte un fallo visible
      // en un estado parcial.
      final falso = envoltorio('git-contesta-de-mas', r'''#!/bin/sh
if [ "$2" = "commit" ] && [ "$3" = "--dry-run" ]; then
  git "$@"
  printf 'M  intruso.txt'
  exit 0
fi
exec git "$@"
''');
      final antes = correr('git', ['rev-parse', 'HEAD']);
      final torcido = RepositorioGit(directorio: raiz.path, programa: falso);
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

  group('rechazar no puede tocar lo que preparó otro', () {
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

    test('si NO puede restaurar, lo dice, y dice qué rechazaba', () async {
      // Un reparador que no puede fallar es la misma clase de instrumento roto
      // que este arnés existe para cazar. La versión anterior se tragaba el
      // fallo del `reset` en silencio.
      final falso = envoltorio('git-no-restaura', r'''#!/bin/sh
if [ "$2" = "update-index" ]; then exit 0; fi
exec git "$@"
''');
      escribir('a.txt', 'cambio\n');
      final torcido = RepositorioGit(directorio: raiz.path, programa: falso);
      await expectLater(
          torcido.apply(rebanada(['a.txt', 'b.txt'])),
          throwsA(isA<PromesaIncumplida>()
              .having((e) => e.sePidio, 'se pidió', contains('índice'))
              .having((e) => e.sePidio, 'el motivo original',
                  contains('RebanadaNoAplicable'))));
    });

    test('tampoco si lo que no puede es SACAR una entrada', () async {
      // El otro lado de la verificación, y lo encontró una mutación: sin
      // comparar el TAMAÑO, una entrada de más que la restauración no logró
      // quitar pasaba por buena — comparar solo el contenido recorre las
      // entradas de la foto, y esta no está en la foto.
      final falso = envoltorio('git-no-quita', r'''#!/bin/sh
if [ "$2" = "update-index" ]; then exit 0; fi
exec git "$@"
''');
      escribir('nueva.txt', 'nueva\n');
      final torcido = RepositorioGit(directorio: raiz.path, programa: falso);
      await expectLater(torcido.apply(rebanada(['nueva.txt', 'b.txt'])),
          throwsA(isA<PromesaIncumplida>()));
    });
  });

  group('cuando git no está', () {
    test('la ausencia se nota, y dice qué se intentó', () async {
      // Una herramienta que no está no puede leerse como que no había nada que
      // hacer. Es la misma exigencia que ADR-011 le hace a un verificador.
      final sinGit =
          RepositorioGit(directorio: raiz.path, programa: 'no-existe-git');
      await expectLater(
        sinGit.useBranch('x'),
        throwsA(isA<GitFallo>().having(
            (e) => e.invocacion, 'invocación', contains('no-existe-git'))),
      );
    });
  });
}
