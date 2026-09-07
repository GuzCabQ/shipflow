/// El candidato, contra `git` de verdad.
///
/// **Cada prueba de acá protege una premisa que se midió antes de escribir el
/// diseño.** Una sonda ejecutable —`verificacion/sonda-candidato/sonda.py` en
/// el corpus— comprobó el ciclo entero sobre un repositorio fabricado, y varias
/// de las conclusiones contradijeron lo que el diseño afirmaba. Una premisa
/// medida que no queda amarrada a un control vuelve a ser una suposición en
/// cuanto cambie `git`, así que cada fila de la matriz que dice «medido» tiene
/// acá su prueba, y algunas están escritas para ponerse **rojas si la premisa
/// deja de valer**, no solo si el código se rompe.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

class _TodoEsFuente implements ArtifactPolicy {
  const _TodoEsFuente();
  @override
  bool isGenerated(String path) => false;
  @override
  bool isEditable(String path) => path.trim().isNotEmpty;
}

void main() {
  late Directory raiz;
  late RepositorioGit repo;

  String git(List<String> args, {Directory? en}) {
    final r = Process.runSync('git', args, workingDirectory: (en ?? raiz).path);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
    }
    return (r.stdout as String).trim();
  }

  void escribir(String nombre, String contenido) {
    final f = File('${raiz.path}/$nombre');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  /// Cuántos objetos sueltos tiene el almacén **real**.
  int objetosDelRepo() {
    final d = Directory('${raiz.path}/.git/objects');
    return d
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.contains('/info/'))
        .length;
  }

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('candidato_');
    repo =
        RepositorioGit(directorio: raiz.path, politica: const _TodoEsFuente());
    git(['init', '--initial-branch=main', '.']);
    git(['config', 'user.email', 'p@p']);
    git(['config', 'user.name', 'prueba']);
    escribir('a.txt', 'uno\n');
    escribir('sub/hondo.txt', 'anidado\n');
    git(['add', '-A']);
    git(['commit', '-m', 'base']);
  });

  tearDown(() => raiz.deleteSync(recursive: true));

  PullRequestSlice rebanada(List<String> files,
          {String intent = 'porque sí'}) =>
      PullRequestSlice(id: 'r1', intent: intent, files: files);

  /// Prepara y **siempre** libera, incluso si la prueba falla.
  Future<T> conCandidato<T>(PullRequestSlice slice,
      Future<T> Function(PreparedCandidate) usar) async {
    final c = await repo.prepareCandidate(slice);
    try {
      return await usar(c);
    } finally {
      await c.dispose();
    }
  }

  group('la preparación no deja efectos', () {
    test('cero objetos nuevos en el repositorio antes de autorizar', () async {
      // La v7 aislaba el almacén solo con `--dry-run`. Está medido que preparar
      // contra el almacén real deja objetos inalcanzables **antes** de que
      // nadie haya confirmado nada, y hay tres caminos que prometen cero
      // efectos: el ensayo, la ausencia de terminal, y el usuario que dice que
      // no. Por eso el almacén temporal se usa siempre.
      escribir('a.txt', 'modificado\n');
      final antes = objetosDelRepo();
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(objetosDelRepo(), antes,
            reason: 'preparar no puede escribir en el almacén del usuario');
        return null;
      });
      expect(objetosDelRepo(), antes);
    });

    test('dispose borra el workspace materializado', () async {
      escribir('a.txt', 'modificado\n');
      final c = await repo.prepareCandidate(rebanada(['a.txt']));
      expect(Directory(c.root).existsSync(), isTrue);
      await c.dispose();
      expect(Directory(c.root).existsSync(), isFalse);
    });

    test('dispose es idempotente: se puede llamar dos veces', () async {
      // Tiene que poder llamarse desde un manejador de señal, donde nadie sabe
      // si ya corrió.
      escribir('a.txt', 'modificado\n');
      final c = await repo.prepareCandidate(rebanada(['a.txt']));
      await c.dispose();
      await c.dispose();
    });

    test('el índice del usuario no se toca', () async {
      escribir('a.txt', 'modificado\n');
      escribir('otro.txt', 'ajeno\n');
      git(['add', 'otro.txt']);
      final antes = git(['diff', '--cached', '--name-only']);
      await conCandidato(rebanada(['a.txt']), (c) async => null);
      expect(git(['diff', '--cached', '--name-only']), antes);
    });
  });

  group('la identidad es un árbol', () {
    test('el contenido preparado es el árbol que se commitea', () async {
      escribir('a.txt', 'modificado\n');
      final revision = await conCandidato(rebanada(['a.txt']), (c) async {
        final d = await c.commit();
        expect(d, isA<Committed>());
        expect((d as Committed).revision, isNotEmpty);
        expect(git(['rev-parse', '${d.revision}^{tree}']),
            c.identity.contentRevision,
            reason: 'el árbol del commit ES el candidato, no una copia');
        return d.revision;
      });
      expect(git(['rev-parse', 'HEAD']), revision);
    });

    test('el bit ejecutable cambia la identidad aunque el objeto no cambie',
        () async {
      // Medido: cambiar el bit conserva el objeto del archivo y cambia el
      // commit. Es la razón por la que la identidad es un árbol y no un digest
      // por ruta.
      escribir('ejec.sh', '#!/bin/sh\necho hola\n');
      git(['add', 'ejec.sh']);
      git(['commit', '-m', 'script']);
      final objetoAntes = git(['rev-parse', 'HEAD:ejec.sh']);

      Process.runSync('chmod', ['755', '${raiz.path}/ejec.sh']);
      await conCandidato(rebanada(['ejec.sh']), (c) async {
        expect(c.changedPaths, ['ejec.sh'],
            reason: 'el árbol detecta el cambio de modo');
        // **Se pregunta DESPUÉS de aplicar, y no es un rodeo.** Mientras el
        // candidato está preparado, su árbol vive en un almacén que el `git`
        // del usuario no ve: preguntarle desde afuera falla, que es justo la
        // propiedad de aislamiento que otra prueba de este archivo fija.
        await c.commit();
        return null;
      });
      expect(git(['rev-parse', 'HEAD:ejec.sh']), objetoAntes,
          reason: 'el objeto del archivo es el mismo: el modo no viaja ahí');
      expect(git(['ls-files', '-s', 'ejec.sh']), startsWith('100755'));
    });

    test('un borrado no necesita ningún objeto resultante', () async {
      // Un digest obligatorio por ruta sería un tipo mal formado: acá no hay
      // ninguno que poner.
      File('${raiz.path}/a.txt').deleteSync();
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(c.changedPaths, ['a.txt']);
        final d = await c.commit();
        expect(d, isA<Committed>());
        expect(
            Process.runSync('git', ['cat-file', '-e', 'HEAD:a.txt'],
                    workingDirectory: raiz.path)
                .exitCode,
            isNot(0),
            reason: 'el borrado quedó commiteado');
        return null;
      });
    });
  });

  group('los bytes que se verifican son los que se commitean', () {
    /// Un repositorio con las dos conversiones que rompen la igualdad.
    void conFiltros() {
      git(['config', 'filter.marca.clean', 'sed s/SUCIO/LIMPIO/']);
      git(['config', 'filter.marca.smudge', 'sed s/LIMPIO/SUCIO/']);
      escribir('.gitattributes',
          'conmarca.txt filter=marca\ncrlf.txt text eol=crlf\n');
      escribir('conmarca.txt', 'valor LIMPIO\n');
      escribir('crlf.txt', 'l1\nl2\n');
      git(['add', '-A']);
      git(['commit', '-m', 'filtros']);
    }

    test('con filtro smudge y con eol=crlf, lo materializado ES el objeto',
        () async {
      // **La prueba que impide volver a `checkout-index`.** Está medido que
      // `checkout-index` aplica la conversión inversa y rompe la igualdad en
      // estos dos casos exactos. La materialización por plumbing no.
      conFiltros();
      escribir('conmarca.txt', 'valor SUCIO otra vez\n');
      escribir('crlf.txt', 'l1\nl2\nl3\n');

      await conCandidato(rebanada(['conmarca.txt', 'crlf.txt']), (c) async {
        // Se aplica primero para que los objetos existan en el almacén real y
        // se puedan leer con el `git` del usuario; el workspace materializado
        // sigue en pie hasta el `dispose`.
        expect(await c.commit(), isA<Committed>());
        for (final nombre in ['conmarca.txt', 'crlf.txt']) {
          final r = Process.runSync('git', ['cat-file', 'blob', 'HEAD:$nombre'],
              workingDirectory: raiz.path, stdoutEncoding: null);
          expect(r.exitCode, 0,
              reason: 'el objeto de $nombre tiene que existir');
          final delObjeto = r.stdout as List<int>;
          expect(delObjeto, isNotEmpty);
          final enDisco = File('${c.root}/$nombre').readAsBytesSync();
          expect(enDisco, delObjeto,
              reason: 'igualdad literal en $nombre: sin esto el artefacto '
                  'afirma sobre bytes que nadie verificó');
        }
        return null;
      });
    });

    test('el filtro clean corre UNA vez: promover no lo vuelve a correr',
        () async {
      // `hash-object -t <tipo> -w --stdin` sin `--path` no aplica atributos.
      // Que el identificador que vuelve sea el mismo es lo que lo convierte en
      // un hecho comprobado y no en una expectativa.
      conFiltros();
      escribir('conmarca.txt', 'otro SUCIO\n');
      await conCandidato(rebanada(['conmarca.txt']), (c) async {
        final esperado = c.identity.contentRevision;
        await c.commit();
        expect(git(['rev-parse', 'HEAD^{tree}']), esperado);
        expect(git(['cat-file', 'blob', 'HEAD:conmarca.txt']), 'otro LIMPIO',
            reason: 'el filtro corrió una sola vez, en la preparación');
        return null;
      });
    });

    test(
        'el árbol de trabajo puede cambiar entre verificar y commitear, y el '
        'commit se lleva el candidato', () async {
      // **Acá muere el TOCTOU.** No hay `git add` en el momento del commit: el
      // objeto ya está fijado. Sabotaje del estado intermedio n.º 2: si alguien
      // reintroduce un `add` acá, esta prueba se pone roja.
      escribir('a.txt', 'lo que se verificó\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        escribir('a.txt', 'lo que alguien escribió después\n');
        final d = await c.commit() as Committed;
        expect(git(['cat-file', 'blob', '${d.revision}:a.txt']),
            'lo que se verificó');
        return null;
      });
    });
  });

  group('la rebanada sigue siendo exacta', () {
    test('un archivo declarado sin cambios no arma candidato', () async {
      expect(() => repo.prepareCandidate(rebanada(['a.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('los cambios ajenos sobreviven y no entran', () async {
      escribir('a.txt', 'declarado\n');
      escribir('ajeno.txt', 'no declarado\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(c.changedPaths, ['a.txt']);
        await c.commit();
        return null;
      });
      expect(
          File('${raiz.path}/ajeno.txt').readAsStringSync(), 'no declarado\n',
          reason: 'lo que no es de la rebanada queda intacto en el árbol');
      expect(
          Process.runSync('git', ['cat-file', '-e', 'HEAD:ajeno.txt'],
                  workingDirectory: raiz.path)
              .exitCode,
          isNot(0),
          reason: 'y no se commitea');
    });

    test('un alta entra como alta', () async {
      escribir('nuevo.txt', 'alta\n');
      await conCandidato(rebanada(['nuevo.txt']), (c) async {
        expect(c.changedPaths, ['nuevo.txt']);
        await c.commit();
        return null;
      });
      expect(git(['cat-file', 'blob', 'HEAD:nuevo.txt']), 'alta');
    });

    test('lo ya stageado por el usuario no cambia el resultado', () async {
      escribir('a.txt', 'staged\n');
      git(['add', 'a.txt']);
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(c.changedPaths, ['a.txt']);
        return null;
      });
    });

    test('una ruta repetida se rechaza', () {
      escribir('a.txt', 'x\n');
      expect(() => repo.prepareCandidate(rebanada(['a.txt', 'a.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('una rebanada vacía se rechaza', () {
      expect(() => repo.prepareCandidate(rebanada([])),
          throwsA(isA<RebanadaNoAplicable>()));
    });
  });

  group('lo que el árbol contiene y no se materializa, se declara', () {
    test('un enlace interno se recrea como enlace', () async {
      Link('${raiz.path}/enlace').createSync('sub/hondo.txt');
      git(['add', 'enlace']);
      git(['commit', '-m', 'enlace']);
      escribir('a.txt', 'x\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(Link('${c.root}/enlace').existsSync(), isTrue,
            reason: 'se crea el enlace, no un archivo con el destino adentro');
        expect(Link('${c.root}/enlace').targetSync(), 'sub/hondo.txt');
        expect(c.noMaterializadas, isEmpty);
        return null;
      });
    });

    test('un enlace absoluto o con .. NO se recrea, y queda declarado',
        () async {
      Link('${raiz.path}/afuera').createSync('/etc/passwd');
      Link('${raiz.path}/escapa').createSync('../../fuera');
      git(['add', 'afuera', 'escapa']);
      git(['commit', '-m', 'enlaces']);
      escribir('a.txt', 'x\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(
            FileSystemEntity.typeSync('${c.root}/afuera', followLinks: false),
            FileSystemEntityType.notFound);
        expect(
            FileSystemEntity.typeSync('${c.root}/escapa', followLinks: false),
            FileSystemEntityType.notFound);
        expect(
            c.noMaterializadas.map((n) => n.ruta).toSet(), {'afuera', 'escapa'},
            reason: 'una sola conducta: no se recrea, y no se calla');
        expect(c.noMaterializadas.every((n) => n.modo == '120000'), isTrue);
        return null;
      });
    });

    test('un submódulo se declara, no se materializa', () async {
      // Se fabrica el gitlink sin submódulo real. El identificador tiene que
      // ser VÁLIDO: `update-index` rechaza el nulo con «cache entry has null
      // sha1» — lo encontró la propia sonda, sobre su propio fixture.
      final valido = git(['rev-parse', 'HEAD']);
      git(['update-index', '--add', '--cacheinfo', '160000,$valido,submod']);
      git(['commit', '-m', 'gitlink']);
      escribir('a.txt', 'x\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(c.noMaterializadas.map((n) => n.ruta).toList(), ['submod']);
        expect(c.noMaterializadas.single.modo, '160000');
        expect(Directory('${c.root}/submod').existsSync(), isFalse);
        return null;
      });
    });

    test('un nombre con salto de línea sobrevive al parsing', () async {
      // `ls-tree -z` no es consumible línea por línea: un salto partiría el
      // registro en dos y el candidato dejaría de representar el árbol.
      escribir('con\nsalto.txt', 'nombre raro\n');
      git(['add', '-A']);
      git(['commit', '-m', 'raro']);
      escribir('a.txt', 'x\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(File('${c.root}/con\nsalto.txt').readAsStringSync(),
            'nombre raro\n');
        return null;
      });
    });

    test('el bit ejecutable se materializa', () async {
      escribir('ejec.sh', '#!/bin/sh\necho hola\n');
      Process.runSync('chmod', ['755', '${raiz.path}/ejec.sh']);
      git(['add', '-A']);
      git(['commit', '-m', 'script']);
      escribir('a.txt', 'x\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(git(['ls-files', '-s', 'ejec.sh']), startsWith('100755'));
        final modo = Process.runSync('stat', ['-f', '%Lp', '${c.root}/ejec.sh'])
            .stdout as String;
        expect(modo.trim(), '755');
        return null;
      });
    });

    test('sin chmod, el modo que no se aplica se NOTA', () async {
      // El mismo motivo por el que `programa` es inyectable: una herramienta
      // que no está no puede leerse como que no había nada que hacer.
      escribir('ejec.sh', '#!/bin/sh\n');
      Process.runSync('chmod', ['755', '${raiz.path}/ejec.sh']);
      git(['add', '-A']);
      git(['commit', '-m', 'script']);
      escribir('a.txt', 'x\n');
      final sinChmod = RepositorioGit(
          directorio: raiz.path,
          politica: const _TodoEsFuente(),
          programaChmod: '${raiz.path}/no-existe-chmod');
      expect(() => sinChmod.prepareCandidate(rebanada(['a.txt'])),
          throwsA(anyOf(isA<PromesaIncumplida>(), isA<ProcessException>())));
    });
  });

  group('la promoción', () {
    test('es recursiva: con un subárbol anidado, el commit funciona', () async {
      // La v8 promovía solo los objetos de archivo. Medido: con solo esos y el
      // temporal borrado, `commit-tree` falla con «is not a valid object».
      // Acá el cambio está **dentro** de un subdirectorio, así que hay al menos
      // dos árboles que promover.
      escribir('sub/hondo.txt', 'anidado v2\n');
      await conCandidato(rebanada(['sub/hondo.txt']), (c) async {
        final esperado = c.identity.contentRevision;
        final d = await c.commit();
        expect(d, isA<Committed>());
        expect(git(['rev-parse', 'HEAD^{tree}']), esperado);
        expect(git(['cat-file', 'blob', 'HEAD:sub/hondo.txt']), 'anidado v2');
        return null;
      });
    });

    test('el contenido resuelve desde el repositorio real, sin alternates',
        () async {
      escribir('sub/hondo.txt', 'anidado v2\n');
      final c = await repo.prepareCandidate(rebanada(['sub/hondo.txt']));
      final contenido = c.identity.contentRevision;
      await c.commit();
      await c.dispose();
      // Sin `GIT_ALTERNATE_OBJECT_DIRECTORIES`, y con el temporal borrado.
      expect(git(['cat-file', '-t', contenido]), 'tree');
    });
  });

  group('el compare-and-swap', () {
    test('con HEAD movido: NO aplica, y el trabajo ajeno sobrevive', () async {
      escribir('a.txt', 'lo mío\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        escribir('ajeno.txt', 'commit ajeno\n');
        git(['add', 'ajeno.txt']);
        git(['commit', '-m', 'ajeno']);
        final movido = git(['rev-parse', 'HEAD']);

        final d = await c.commit();
        expect(d, isA<NotApplied>());
        final na = d as NotApplied;
        expect(na.baseEsperada, c.identity.baseRevision);
        expect(na.headObservado, movido);
        expect(git(['rev-parse', 'HEAD']), movido,
            reason: 'la rama quedó intacta');
        expect(git(['rev-parse', 'refs/heads/main']), movido);
        expect(na.revision, isNotEmpty,
            reason: 'el objeto commit existe y queda inalcanzable: no es daño');
        expect(git(['cat-file', '-t', na.revision]), 'commit');
        return null;
      });
    });

    test('si el usuario cambió de rama, no se aplica nada', () async {
      escribir('a.txt', 'lo mío\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        final antes = git(['rev-parse', 'refs/heads/main']);
        git(['switch', '--create', 'otra']);
        final d = await c.commit();
        expect(d, isA<NotApplied>());
        expect(git(['rev-parse', 'refs/heads/main']), antes,
            reason: 'no se mueve una rama que no está puesta');
        return null;
      });
    });

    test('tras aplicar, el índice queda al día', () async {
      // Sin esto `git status` reporta lo recién commiteado como borrado.
      // `commit-tree` no toca el índice: no es `git commit`.
      escribir('a.txt', 'modificado\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        await c.commit();
        return null;
      });
      expect(git(['status', '--porcelain', '--', 'a.txt']), isEmpty);
    });
  });

  group('los estados que no se pueden preparar', () {
    test('HEAD suelto', () async {
      final base = git(['rev-parse', 'HEAD']);
      git(['checkout', '--detach', base]);
      escribir('a.txt', 'x\n');
      expect(() => repo.prepareCandidate(rebanada(['a.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('un repositorio sin ningún commit', () async {
      final vacio = Directory.systemTemp.createTempSync('vacio_');
      addTearDown(() => vacio.deleteSync(recursive: true));
      Process.runSync('git', ['init', '--initial-branch=main', '.'],
          workingDirectory: vacio.path);
      File('${vacio.path}/a.txt').writeAsStringSync('x\n');
      final r = RepositorioGit(
          directorio: vacio.path, politica: const _TodoEsFuente());
      expect(() => r.prepareCandidate(rebanada(['a.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('un merge sin resolver', () async {
      git(['switch', '--create', 'rama-b']);
      escribir('a.txt', 'de la rama b\n');
      git(['commit', '-am', 'b']);
      git(['switch', 'main']);
      escribir('a.txt', 'de main\n');
      git(['commit', '-am', 'main']);
      Process.runSync('git', ['merge', 'rama-b'], workingDirectory: raiz.path);
      expect(() => repo.prepareCandidate(rebanada(['a.txt'])),
          throwsA(isA<RebanadaNoAplicable>()));
    });

    test('commit sobre un candidato ya liberado no escribe nada', () async {
      escribir('a.txt', 'x\n');
      final c = await repo.prepareCandidate(rebanada(['a.txt']));
      final antes = git(['rev-parse', 'HEAD']);
      await c.dispose();
      await expectLater(c.commit(), throwsA(isA<StateError>()));
      expect(git(['rev-parse', 'HEAD']), antes);
    });
  });

  group('el worktree', () {
    test('el almacén se resuelve aunque .git sea un archivo', () async {
      // En un worktree enlazado `.git` no es un directorio. Se resuelve con
      // `rev-parse --git-path`, igual que el índice aislado.
      final wt = Directory('${raiz.path}/../wt-${raiz.uri.pathSegments.last}');
      git(['worktree', 'add', '-b', 'rama2', wt.path]);
      addTearDown(() {
        if (wt.existsSync()) wt.deleteSync(recursive: true);
      });
      expect(File('${wt.path}/.git').existsSync(), isTrue,
          reason: 'la premisa: acá .git es un ARCHIVO');

      final desdeWt =
          RepositorioGit(directorio: wt.path, politica: const _TodoEsFuente());
      File('${wt.path}/a.txt').writeAsStringSync('desde el worktree\n');
      final c = await desdeWt.prepareCandidate(rebanada(['a.txt']));
      try {
        expect(
            File('${c.root}/a.txt').readAsStringSync(), 'desde el worktree\n');
        expect(await c.commit(), isA<Committed>());
      } finally {
        await c.dispose();
      }
    });
  });

  group('la premisa de git, no la nuestra', () {
    test('check-attr NO informa core.autocrlf: no hay preflight barato',
        () async {
      // Si un `git` futuro lo anunciara, esta prueba se pone roja y habilita
      // saltarse la materialización cuando no hay ninguna conversión. Hoy no
      // se puede saber sin materializar, y por eso se materializa siempre.
      git(['config', 'core.autocrlf', 'true']);
      final salida = git([
        'check-attr',
        'text',
        'eol',
        'working-tree-encoding',
        '--',
        'a.txt'
      ]);
      expect(salida, contains('unspecified'));
      expect(salida.split('\n').every((l) => l.endsWith('unspecified')), isTrue,
          reason: 'las tres claves sin especificar, con autocrlf activo');
    });

    test('checkout-index rompe la igualdad que el plumbing conserva', () async {
      // **El sabotaje de la materialización.** Si alguien reintroduce
      // `checkout-index`, la prueba de igualdad se pone roja; esta prueba fija
      // *por qué*: la conversión inversa existe y es observable.
      git(['config', 'filter.marca.clean', 'sed s/SUCIO/LIMPIO/']);
      git(['config', 'filter.marca.smudge', 'sed s/LIMPIO/SUCIO/']);
      escribir('.gitattributes', 'conmarca.txt filter=marca\n');
      escribir('conmarca.txt', 'valor LIMPIO\n');
      git(['add', '-A']);
      git(['commit', '-m', 'filtro']);

      final salida = Directory('${raiz.path}/salida');
      salida.createSync();
      Process.runSync(
          'git', ['checkout-index', '-a', '--prefix=${salida.path}/'],
          workingDirectory: raiz.path);
      final delObjeto = git(['cat-file', 'blob', 'HEAD:conmarca.txt']);
      final tras =
          File('${salida.path}/conmarca.txt').readAsStringSync().trim();
      expect(tras, isNot(delObjeto),
          reason: 'si esto deja de ser cierto, `checkout-index` volvió a ser '
              'una opción y hay que revisar la decisión, no el código');
      expect(utf8.encode(tras), isNotEmpty);
    });
  });
}
