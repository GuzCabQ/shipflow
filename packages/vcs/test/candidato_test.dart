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

/// Una política que **sí declara artefactos**, para poder distinguir «apareció
/// algo que el entorno genera» de «apareció código».
///
/// Sin ella no se puede probar la diferencia: con una política que llama fuente
/// a todo, ambos casos se ven igual — y con una que no llama fuente a nada,
/// también. La política es la autoridad, así que la prueba necesita una que
/// diga las dos cosas.
class _ConArtefactos implements ArtifactPolicy {
  const _ConArtefactos();
  @override
  bool isGenerated(String path) => path.endsWith('.g.txt');
  @override
  bool isEditable(String path) =>
      path.trim().isNotEmpty &&
      !isGenerated(path) &&
      !path.startsWith('generado/') &&
      !path.contains('/generado/');
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

  /// Qué objetos tiene el almacén **real**, por identificador.
  ///
  /// **Se le pregunta a git, no se mira el layout del directorio.** Esto empezó
  /// contando archivos sueltos y CI lo puso rojo sin que nadie escribiera nada:
  /// git empaqueta y limpia por su cuenta, así que la cantidad de sueltos no es
  /// estable. Se cambió por un conjunto de rutas, y una revisión encontró que
  /// eso trajo un hueco peor — medido: un objeto nuevo que termina empaquetado
  /// da **cero archivos sueltos nuevos y tres OIDs nuevos**. La prueba se
  /// llamaba «cero objetos nuevos» y habría pasado con el repositorio ganando
  /// tres.
  ///
  /// `--batch-all-objects` enumera sueltos Y empaquetados, y un OID no cambia
  /// cuando se empaqueta: el conjunto es estable bajo lo que git hace solo, y
  /// exacto sobre lo que se quiere medir.
  Set<String> objetosDelRepo() => git([
    'cat-file',
    '--batch-all-objects',
    '--batch-check=%(objectname)',
  ]).split('\n').where((l) => l.trim().isNotEmpty).toSet();

  /// Qué objetos sueltos tiene el almacén **temporal** del candidato, por
  /// ruta relativa dentro de `objetos`.
  ///
  /// **Se deriva de `c.root`**, que es la única ruta que el puerto expone:
  /// `objetos` es carpeta hermana de `arbol` bajo el mismo directorio
  /// temporal —está anotado donde se crean, en `_CandidatoGit.preparar`—, así
  /// que restar `/arbol` y sumar `/objetos` llega ahí sin que
  /// `PreparedCandidate` tenga que declarar su almacén. Es la misma
  /// derivación que usa [ensuciarElArbolDelCandidato], y es lo que permite
  /// comprobar que un paso NO escribe sin inventar un espía que el puerto no
  /// tiene con qué sostener.
  Set<String> objetosDelAlmacenTemporal(PreparedCandidate c) {
    final objetos = Directory('${Directory(c.root).parent.path}/objetos');
    if (!objetos.existsSync()) return {};
    return objetos
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.substring(objetos.path.length))
        .toSet();
  }

  /// Corrompe, por fuera del candidato, el objeto que el árbol fijado usa
  /// para [archivo] — sin pasar por ninguna costura del candidato.
  ///
  /// **Es un evento que ningún camino del comando puede producir, y por eso
  /// esto NO mide ninguna ventana.** El par `baseRevision`/`contentRevision`
  /// que diffea `exigirSinSecretos` es fijo desde que `prepareCandidate`
  /// devuelve, y lo que `createRevision` commitea es ese mismo árbol: pedirle
  /// el escaneo dos veces al mismo candidato da siempre el mismo resultado, y
  /// entre las dos llamadas no hay ninguna ventana que cerrar. Para que la
  /// segunda lectura vea algo que la primera no vio hace falta reescribir a
  /// mano los bytes del objeto suelto del almacén temporal, que es lo que
  /// este ayudante hace.
  ///
  /// Lo que habilita, entonces, es medir que `createRevision` **escanea por
  /// su cuenta** en vez de confiar en que alguien haya pedido el escaneo
  /// antes: hace falta un dato que diverja entre las dos lecturas, y
  /// fabricarlo desde afuera es la única forma.
  ///
  /// **Un objeto suelto no lleva ninguna verificación de que su contenido
  /// coincida con su nombre.** `git` la aplica en `fsck`, no al leer con
  /// `cat-file` o `diff`: por eso alcanza con reemplazar los bytes del
  /// archivo en disco, sin tocar el árbol que lo referencia.
  void ensuciarElArbolDelCandidato(
    PreparedCandidate c,
    String archivo,
    String contenidoConSecreto,
  ) {
    final objetos = Directory('${Directory(c.root).parent.path}/objetos');
    final almacenReal = () {
      final relativo = git(['rev-parse', '--git-path', 'objects']);
      return relativo.startsWith('/') ? relativo : '${raiz.path}/$relativo';
    }();
    final entorno = {
      ...Platform.environment,
      'GIT_OBJECT_DIRECTORY': objetos.path,
      'GIT_ALTERNATE_OBJECT_DIRECTORIES': almacenReal,
    };
    final listado = Process.runSync(
      'git',
      ['ls-tree', c.identity.contentRevision, '--', archivo],
      workingDirectory: raiz.path,
      environment: entorno,
    );
    if (listado.exitCode != 0) {
      throw StateError('ls-tree ${listado.exitCode}: ${listado.stderr}');
    }
    final sha = (listado.stdout as String).trim().split(RegExp(r'\s+'))[2];
    final objeto = File(
      '${objetos.path}/${sha.substring(0, 2)}/${sha.substring(2)}',
    );
    expect(
      objeto.existsSync(),
      isTrue,
      reason:
          'el blob de $archivo tiene que vivir en el almacén temporal para '
          'que este ayudante lo pueda corromper',
    );
    final cuerpo = utf8.encode(contenidoConSecreto);
    final crudo = [...utf8.encode('blob ${cuerpo.length}\u0000'), ...cuerpo];
    // `git` escribe los objetos sueltos de solo lectura. Se borra y se
    // recrea en vez de sobreescribir: reabrir el mismo archivo con el modo
    // que `git` le puso falla con «permiso denegado».
    objeto.deleteSync();
    objeto.writeAsBytesSync(ZLibEncoder().convert(crudo));
  }

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('candidato_');
    repo = RepositorioGit(
      directorio: raiz.path,
      politica: const _TodoEsFuente(),
    );
    git(['init', '--initial-branch=main', '.']);
    git(['config', 'user.email', 'p@p']);
    git(['config', 'user.name', 'prueba']);
    escribir('a.txt', 'uno\n');
    escribir('sub/hondo.txt', 'anidado\n');
    git(['add', '-A']);
    git(['commit', '-m', 'base']);
  });

  tearDown(() => raiz.deleteSync(recursive: true));

  PullRequestSlice rebanada(
    List<String> files, {
    String intent = 'porque sí',
  }) => PullRequestSlice(id: 'r1', intent: intent, files: files);

  /// Crear la revisión y aplicarla, que es lo que hace el coordinador.
  ///
  /// **Son dos llamadas y no una, a propósito.** En medio va la persistencia
  /// de `prepared` con la revisión adentro; el puerto las separa justamente
  /// para que ahí quepa. Acá no se persiste nada, pero el orden se respeta.
  Future<CommitOutcome> aplicar(PreparedCandidate c) async {
    await c.createRevision();
    return c.applyRevision();
  }

  /// Prepara y **siempre** libera, incluso si la prueba falla.
  Future<T> conCandidato<T>(
    PullRequestSlice slice,
    Future<T> Function(PreparedCandidate) usar,
  ) async {
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
        expect(
          objetosDelRepo().difference(antes),
          isEmpty,
          reason: 'preparar no puede escribir en el almacén del usuario',
        );
        return null;
      });
      expect(objetosDelRepo().difference(antes), isEmpty);
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

  group('la integridad del candidato se comprueba, no se supone', () {
    test('un candidato intacto no tiene alteraciones', () async {
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(await c.alteraciones(), isEmpty);
        return null;
      });
    });

    test('modificado, borrado, +x y un regular donde había enlace', () async {
      escribir('a.txt', 'dos\n');
      escribir('b.txt', 'b\n');
      Link('${raiz.path}/enlace').createSync('a.txt');
      git(['add', '-A']);
      git(['commit', '-m', 'con enlace']);
      escribir('a.txt', 'tres\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        File('${c.root}/a.txt').writeAsStringSync('otra cosa\n');
        File('${c.root}/sub/hondo.txt').deleteSync();
        Process.runSync('chmod', ['755', '${c.root}/b.txt']);
        Link('${c.root}/enlace').deleteSync();
        File('${c.root}/enlace').writeAsStringSync('regular\n');
        final a = {for (final x in await c.alteraciones()) x.ruta: x.tipo};
        expect(a, {
          'a.txt': TipoDeAlteracion.modificada,
          'sub/hondo.txt': TipoDeAlteracion.borrada,
          'b.txt': TipoDeAlteracion.cambioDeModo,
          'enlace': TipoDeAlteracion.cambioDeTipo,
        });
        return null;
      });
    });

    test('un ARTEFACTO nuevo no es una alteración; un archivo de FUENTE '
        'nuevo SÍ', () async {
      // **La generalización que costó un review.** La primera versión decía que
      // ningún archivo nuevo contaba, porque todos serían generados por la
      // derivación. Es falso: un archivo de fuente creado entre la derivación y
      // este control queda dentro del alcance que la cascada lee, y la corrida
      // salía roja concluyendo sobre bytes que el candidato nunca fijó.
      repo = RepositorioGit(
        directorio: raiz.path,
        politica: const _ConArtefactos(),
      );
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        Directory('${c.root}/generado').createSync();
        File('${c.root}/generado/mapa.json').writeAsStringSync('{}');
        File('${c.root}/salida.g.txt').writeAsStringSync('derivado');
        expect(
          await c.alteraciones(),
          isEmpty,
          reason: 'generar es el trabajo del entorno, no una alteración',
        );

        File('${c.root}/nuevo.txt').writeAsStringSync('esto es fuente');
        final a = await c.alteraciones();
        expect(a.single.ruta, 'nuevo.txt');
        expect(a.single.tipo, TipoDeAlteracion.agregada);
        return null;
      });
    });

    test('quién decide qué es artefacto es la POLÍTICA, no las exclusiones '
        'del repositorio', () async {
      // Con `--exclude-standard`, un archivo que el repositorio excluye quedaría
      // callado aunque la política lo llame fuente. Serían dos autoridades sobre
      // la misma pregunta, y la que manda ya está decidida.
      escribir('.gitignore', 'excluido.txt\n');
      git(['add', '-A']);
      git(['commit', '-m', 'con exclusiones']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        File('${c.root}/excluido.txt').writeAsStringSync('el repo lo excluye');
        final a = await c.alteraciones();
        expect(a.map((x) => x.ruta), ['excluido.txt']);
        expect(a.single.tipo, TipoDeAlteracion.agregada);
        return null;
      });
    });

    test('una ruta declarada en noMaterializadas no cuenta como agregada '
        'cuando el candidato no la recreó', () async {
      // Sutil: la ruta NO está en el disco, así que no puede aparecer como
      // nueva. Pero si alguien la escribe, `diff-index` la ve como cambio de
      // tipo —ya cubierto— y no como agregada. Esta prueba fija que las dos
      // vías no se pisen y produzcan la misma ruta dos veces.
      Link('${raiz.path}/abs').createSync('/etc/hosts');
      git(['add', '-A']);
      git(['commit', '-m', 'abs']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        File('${c.root}/abs').writeAsStringSync('regular\n');
        final a = await c.alteraciones();
        expect(a.map((x) => x.ruta), ['abs'], reason: 'una sola vez');
        expect(a.single.tipo, TipoDeAlteracion.cambioDeTipo);
        return null;
      });
    });

    test('lo declarado en noMaterializadas no es una alteración, los cuatro '
        'a la vez', () async {
      // Enlace absoluto, enlace con `..`, destino que no es UTF-8, y submódulo.
      Link('${raiz.path}/abs').createSync('/etc/hosts');
      Link('${raiz.path}/up').createSync('../fuera');
      git(['add', '-A']);
      // El destino que no es UTF-8 no se puede escribir como enlace del árbol de
      // trabajo con una cadena, así que el objeto va directo al índice.
      // `Process.start` y no `runSync`: hay que mandarle BYTES por la entrada.
      final p = await Process.start('git', [
        'hash-object',
        '-w',
        '--stdin',
      ], workingDirectory: raiz.path);
      p.stdin.add([0xff, 0xfe, 0x2f, 0x78]);
      await p.stdin.close();
      final shaMalo = (await utf8.decodeStream(p.stdout)).trim();
      await p.exitCode;
      git(['update-index', '--add', '--cacheinfo', '120000,$shaMalo,raro']);
      git([
        'update-index',
        '--add',
        '--cacheinfo',
        '160000,4b825dc642cb6eb9a060e54bf8d69288fbee4904,submodulo',
      ]);
      git(['commit', '-m', 'lo que no se materializa']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(
          c.noMaterializadas.map((n) => n.ruta),
          unorderedEquals(['abs', 'up', 'raro', 'submodulo']),
        );
        expect(
          await c.alteraciones(),
          isEmpty,
          reason:
              'sin restar lo declarado, todo candidato con un enlace absoluto '
              'sería no concluyente para siempre',
        );
        return null;
      });
    });

    test('un regular escrito donde el árbol tiene un enlace no materializado '
        'SÍ es una alteración', () async {
      Link('${raiz.path}/abs').createSync('/etc/hosts');
      git(['add', '-A']);
      git(['commit', '-m', 'abs']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        File('${c.root}/abs').writeAsStringSync('regular\n');
        final a = await c.alteraciones();
        expect(a.single.ruta, 'abs');
        expect(a.single.tipo, TipoDeAlteracion.cambioDeTipo);
        return null;
      });
    });

    test('intacto con clean, smudge y eol=crlf da CERO alteraciones', () async {
      git(['config', 'filter.marca.clean', 'sed s/SUCIO/LIMPIO/']);
      git(['config', 'filter.marca.smudge', 'sed s/LIMPIO/SUCIO/']);
      git(['config', 'core.autocrlf', 'true']);
      escribir(
        '.gitattributes',
        'conmarca.txt filter=marca\ncrlf.txt text eol=crlf\n',
      );
      escribir('conmarca.txt', 'esto esta SUCIO\n');
      escribir('crlf.txt', 'l1\r\nl2\r\n');
      git(['add', '-A']);
      git(['commit', '-m', 'filtros']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(await c.alteraciones(), isEmpty);
        return null;
      });
    });

    test('un clean NO idempotente hace «modificada» a un candidato intacto: '
        'el límite declarado', () async {
      // **Esta prueba FIJA un límite, no comprueba una capacidad.**
      // `update-index --refresh` pasa cada archivo por el filtro `clean` antes
      // de comparar —la traza lo muestra— y la materialización escribe los
      // bytes del objeto sin `smudge`. Con filtros idempotentes eso cierra en
      // cero; con uno que no lo es, no hay forma de distinguir «intacto» de
      // «modificado».
      //
      // El límite es de git antes que nuestro: `gitattributes(5)` pide que
      // `clean → clean` equivalga a `clean`, y un repositorio que lo viola ya ve
      // sus archivos perpetuamente modificados en `git status`. Si algún día
      // esto da cero, lo que hay que revisar es la decisión, no el código.
      git(['config', 'filter.suma.clean', r'sed s/$/x/']);
      escribir('.gitattributes', 'suma.txt filter=suma\n');
      escribir('suma.txt', 'base\n');
      git(['add', '-A']);
      git(['commit', '-m', 'no idempotente']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        final a = await c.alteraciones();
        expect(a.map((x) => x.ruta), ['suma.txt']);
        expect(a.single.tipo, TipoDeAlteracion.modificada);
        return null;
      });
    });

    test('se puede comprobar dos veces, y también después de crear la '
        'revisión', () async {
      // Después de promover, el almacén temporal se borra y el árbol resuelve
      // desde el repositorio real. Que la comprobación siga funcionando ahí es
      // lo que permite llamarla antes y después de la cascada.
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(await c.alteraciones(), isEmpty);
        await c.createRevision();
        expect(await c.alteraciones(), isEmpty);
        return null;
      });
    });
  });

  group('git corre con el entorno saneado', () {
    late File registro;
    late File gitFalso;

    setUp(() {
      // Un `git` que anota qué entorno recibió y después delega en el de
      // verdad. Es la única forma de comprobar qué llega y qué no sin
      // depender del shell de quien corre la suite.
      registro = File('${raiz.path}/entorno-visto.txt');
      gitFalso = File('${raiz.path}/git-falso.sh')
        ..writeAsStringSync(
          '#!/bin/sh\nenv >> "${registro.path}"\nexec git "\$@"\n',
        );
      Process.runSync('chmod', ['755', gitFalso.path]);
    });

    test('el token del padre no llega a git, ni un GIT_DIR hostil', () async {
      final r = RepositorioGit(
        directorio: raiz.path,
        politica: const _TodoEsFuente(),
        programa: gitFalso.path,
        entornoDelPadre: EntornoDelProceso({
          'PATH': Platform.environment['PATH']!,
          'HOME': Platform.environment['HOME']!,
          'SHIPFLOW_GITHUB_TOKEN': 'secreto-de-prueba',
          'GIT_DIR': '/otro/repositorio/.git',
        }),
      );
      escribir('a.txt', 'dos\n');
      final c = await r.prepareCandidate(rebanada(['a.txt']));
      await c.dispose();

      final visto = registro.readAsStringSync();
      expect(visto, isNotEmpty, reason: 'el git falso tiene que haber corrido');
      expect(visto, isNot(contains('secreto-de-prueba')));
      expect(
        visto.split('\n').where((l) => l.startsWith('GIT_DIR=')),
        isEmpty,
        reason:
            'un GIT_DIR del shell del usuario corrompería nuestras '
            'operaciones sin que nada lo notara',
      );
      expect(
        visto,
        contains('GIT_INDEX_FILE='),
        reason: 'las propias de la invocación sí viajan',
      );
    });

    test('chmod también corre saneado', () async {
      escribir('ejecutable.sh', '#!/bin/sh\n');
      Process.runSync('chmod', ['755', '${raiz.path}/ejecutable.sh']);
      git(['add', '-A']);
      git(['commit', '-m', 'con ejecutable']);
      final chmodFalso = File('${raiz.path}/chmod-falso.sh')
        ..writeAsStringSync(
          '#!/bin/sh\nenv >> "${registro.path}"\nexec chmod "\$@"\n',
        );
      Process.runSync('chmod', ['755', chmodFalso.path]);
      final r = RepositorioGit(
        directorio: raiz.path,
        politica: const _TodoEsFuente(),
        programaChmod: chmodFalso.path,
        entornoDelPadre: EntornoDelProceso({
          'PATH': Platform.environment['PATH']!,
          'HOME': Platform.environment['HOME']!,
          'SHIPFLOW_GITHUB_TOKEN': 'secreto-de-prueba',
        }),
      );
      escribir('ejecutable.sh', '#!/bin/sh\necho x\n');
      final c = await r.prepareCandidate(rebanada(['ejecutable.sh']));
      await c.dispose();
      expect(registro.readAsStringSync(), contains('PATH='));
      expect(registro.readAsStringSync(), isNot(contains('secreto-de-prueba')));
    });
  });

  group('la identidad del autor es la configurada, o no hay commit', () {
    late Directory hogar;

    setUp(() {
      // Sin identidad LOCAL: la que se prueba es la global, que es la que el
      // saneamiento puede perder.
      git(['config', '--unset', 'user.email']);
      git(['config', '--unset', 'user.name']);
      hogar = Directory.systemTemp.createTempSync('hogar_');
    });
    tearDown(() => hogar.deleteSync(recursive: true));

    Map<String, String> padre([Map<String, String> extra = const {}]) => {
      'PATH': Platform.environment['PATH']!,
      'HOME': hogar.path,
      ...extra,
    };

    RepositorioGit con(Map<String, String> p) => RepositorioGit(
      directorio: raiz.path,
      politica: const _TodoEsFuente(),
      entornoDelPadre: EntornoDelProceso(p),
    );

    Future<String> autorDe(RepositorioGit r) async {
      escribir('a.txt', 'dos\n');
      final c = await r.prepareCandidate(rebanada(['a.txt']));
      try {
        final rev = await c.createRevision();
        return git(['log', '-1', '--format=%an <%ae>', rev]);
      } finally {
        await c.dispose();
      }
    }

    test('con la identidad en el hogar', () async {
      File('${hogar.path}/.gitconfig').writeAsStringSync(
        '[user]\n\tname = Del Hogar\n\temail = hogar@ejemplo.test\n',
      );
      expect(await autorDe(con(padre())), 'Del Hogar <hogar@ejemplo.test>');
    });

    test(
      'con la identidad SOLO en XDG, que la lista blanca no lleva',
      () async {
        // **Está medido que con PATH+HOME solos git FABRICA el autor**: usa el
        // usuario del sistema y el hostname. Enumerar por dónde git puede leer
        // su configuración —XDG_CONFIG_HOME, GIT_CONFIG_GLOBAL— es la misma
        // carrera que una lista negra, así que la identidad se captura.
        final xdg = Directory('${hogar.path}/config/git')
          ..createSync(recursive: true);
        File('${xdg.path}/config').writeAsStringSync(
          '[user]\n\tname = Solo XDG\n\temail = xdg@ejemplo.test\n',
        );
        expect(
          await autorDe(
            con(padre({'XDG_CONFIG_HOME': '${hogar.path}/config'})),
          ),
          'Solo XDG <xdg@ejemplo.test>',
        );
      },
    );

    test('sin ninguna identidad, git se niega en vez de inventar una', () async {
      // La diferencia entre un fallo y un dato falso. Sin `useConfigOnly`, git
      // no falla: inventa un autor y lo escribe en el historial del usuario.
      await expectLater(
        autorDe(con(padre())),
        throwsA(
          isA<GitFallo>().having(
            (e) => e.salida,
            'salida',
            contains('identity'),
          ),
        ),
      );
    });
  });

  group('la identidad es un árbol', () {
    test('el contenido preparado es el árbol que se commitea', () async {
      escribir('a.txt', 'modificado\n');
      final revision = await conCandidato(rebanada(['a.txt']), (c) async {
        final d = await aplicar(c);
        expect(d, isA<Committed>());
        expect((d as Committed).revision, isNotEmpty);
        expect(
          git(['rev-parse', '${d.revision}^{tree}']),
          c.identity.contentRevision,
          reason: 'el árbol del commit ES el candidato, no una copia',
        );
        return d.revision;
      });
      expect(git(['rev-parse', 'HEAD']), revision);
    });

    test(
      'el bit ejecutable cambia la identidad aunque el objeto no cambie',
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
          expect(c.changedPaths, [
            'ejec.sh',
          ], reason: 'el árbol detecta el cambio de modo');
          // **Se pregunta DESPUÉS de aplicar, y no es un rodeo.** Mientras el
          // candidato está preparado, su árbol vive en un almacén que el `git`
          // del usuario no ve: preguntarle desde afuera falla, que es justo la
          // propiedad de aislamiento que otra prueba de este archivo fija.
          await aplicar(c);
          return null;
        });
        expect(
          git(['rev-parse', 'HEAD:ejec.sh']),
          objetoAntes,
          reason: 'el objeto del archivo es el mismo: el modo no viaja ahí',
        );
        expect(git(['ls-files', '-s', 'ejec.sh']), startsWith('100755'));
      },
    );

    test('un borrado no necesita ningún objeto resultante', () async {
      // Un digest obligatorio por ruta sería un tipo mal formado: acá no hay
      // ninguno que poner.
      File('${raiz.path}/a.txt').deleteSync();
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(c.changedPaths, ['a.txt']);
        final d = await aplicar(c);
        expect(d, isA<Committed>());
        expect(
          Process.runSync('git', [
            'cat-file',
            '-e',
            'HEAD:a.txt',
          ], workingDirectory: raiz.path).exitCode,
          isNot(0),
          reason: 'el borrado quedó commiteado',
        );
        return null;
      });
    });
  });

  group('los bytes que se verifican son los que se commitean', () {
    /// Un repositorio con las dos conversiones que rompen la igualdad.
    void conFiltros() {
      git(['config', 'filter.marca.clean', 'sed s/SUCIO/LIMPIO/']);
      git(['config', 'filter.marca.smudge', 'sed s/LIMPIO/SUCIO/']);
      escribir(
        '.gitattributes',
        'conmarca.txt filter=marca\ncrlf.txt text eol=crlf\n',
      );
      escribir('conmarca.txt', 'valor LIMPIO\n');
      escribir('crlf.txt', 'l1\nl2\n');
      git(['add', '-A']);
      git(['commit', '-m', 'filtros']);
    }

    test(
      'con filtro smudge y con eol=crlf, lo materializado ES el objeto',
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
          expect(await aplicar(c), isA<Committed>());
          for (final nombre in ['conmarca.txt', 'crlf.txt']) {
            final r = Process.runSync(
              'git',
              ['cat-file', 'blob', 'HEAD:$nombre'],
              workingDirectory: raiz.path,
              stdoutEncoding: null,
            );
            expect(
              r.exitCode,
              0,
              reason: 'el objeto de $nombre tiene que existir',
            );
            final delObjeto = r.stdout as List<int>;
            expect(delObjeto, isNotEmpty);
            final enDisco = File('${c.root}/$nombre').readAsBytesSync();
            expect(
              enDisco,
              delObjeto,
              reason:
                  'igualdad literal en $nombre: sin esto el artefacto '
                  'afirma sobre bytes que nadie verificó',
            );
          }
          return null;
        });
      },
    );

    test(
      'el filtro clean corre UNA vez: promover no lo vuelve a correr',
      () async {
        // `hash-object -t <tipo> -w --stdin` sin `--path` no aplica atributos.
        // Que el identificador que vuelve sea el mismo es lo que lo convierte en
        // un hecho comprobado y no en una expectativa.
        conFiltros();
        escribir('conmarca.txt', 'otro SUCIO\n');
        await conCandidato(rebanada(['conmarca.txt']), (c) async {
          final esperado = c.identity.contentRevision;
          await aplicar(c);
          expect(git(['rev-parse', 'HEAD^{tree}']), esperado);
          expect(
            git(['cat-file', 'blob', 'HEAD:conmarca.txt']),
            'otro LIMPIO',
            reason: 'el filtro corrió una sola vez, en la preparación',
          );
          return null;
        });
      },
    );

    test('el árbol de trabajo puede cambiar entre verificar y commitear, y el '
        'commit se lleva el candidato', () async {
      // **Acá muere el TOCTOU.** No hay `git add` en el momento del commit: el
      // objeto ya está fijado. Sabotaje del estado intermedio n.º 2: si alguien
      // reintroduce un `add` acá, esta prueba se pone roja.
      escribir('a.txt', 'lo que se verificó\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        escribir('a.txt', 'lo que alguien escribió después\n');
        final d = await aplicar(c) as Committed;
        expect(
          git(['cat-file', 'blob', '${d.revision}:a.txt']),
          'lo que se verificó',
        );
        return null;
      });
    });
  });

  group('la rebanada sigue siendo exacta', () {
    test('un archivo declarado sin cambios no arma candidato', () async {
      expect(
        () => repo.prepareCandidate(rebanada(['a.txt'])),
        throwsA(isA<RebanadaNoAplicable>()),
      );
    });

    test('los cambios ajenos sobreviven y no entran', () async {
      escribir('a.txt', 'declarado\n');
      escribir('ajeno.txt', 'no declarado\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(c.changedPaths, ['a.txt']);
        await aplicar(c);
        return null;
      });
      expect(
        File('${raiz.path}/ajeno.txt').readAsStringSync(),
        'no declarado\n',
        reason: 'lo que no es de la rebanada queda intacto en el árbol',
      );
      expect(
        Process.runSync('git', [
          'cat-file',
          '-e',
          'HEAD:ajeno.txt',
        ], workingDirectory: raiz.path).exitCode,
        isNot(0),
        reason: 'y no se commitea',
      );
    });

    test('un alta entra como alta', () async {
      escribir('nuevo.txt', 'alta\n');
      await conCandidato(rebanada(['nuevo.txt']), (c) async {
        expect(c.changedPaths, ['nuevo.txt']);
        await aplicar(c);
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
      expect(
        () => repo.prepareCandidate(rebanada(['a.txt', 'a.txt'])),
        throwsA(isA<RebanadaNoAplicable>()),
      );
    });

    test('una rebanada vacía se rechaza', () {
      expect(
        () => repo.prepareCandidate(rebanada([])),
        throwsA(isA<RebanadaNoAplicable>()),
      );
    });
  });

  group('lo que el árbol contiene y no se materializa, se declara', () {
    test('un enlace interno se recrea como enlace', () async {
      Link('${raiz.path}/enlace').createSync('sub/hondo.txt');
      git(['add', 'enlace']);
      git(['commit', '-m', 'enlace']);
      escribir('a.txt', 'x\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(
          Link('${c.root}/enlace').existsSync(),
          isTrue,
          reason: 'se crea el enlace, no un archivo con el destino adentro',
        );
        expect(Link('${c.root}/enlace').targetSync(), 'sub/hondo.txt');
        expect(c.noMaterializadas, isEmpty);
        return null;
      });
    });

    test(
      'un enlace absoluto o con .. NO se recrea, y queda declarado',
      () async {
        Link('${raiz.path}/afuera').createSync('/etc/passwd');
        Link('${raiz.path}/escapa').createSync('../../fuera');
        git(['add', 'afuera', 'escapa']);
        git(['commit', '-m', 'enlaces']);
        escribir('a.txt', 'x\n');
        await conCandidato(rebanada(['a.txt']), (c) async {
          expect(
            FileSystemEntity.typeSync('${c.root}/afuera', followLinks: false),
            FileSystemEntityType.notFound,
          );
          expect(
            FileSystemEntity.typeSync('${c.root}/escapa', followLinks: false),
            FileSystemEntityType.notFound,
          );
          expect(
            c.noMaterializadas.map((n) => n.ruta).toSet(),
            {'afuera', 'escapa'},
            reason: 'una sola conducta: no se recrea, y no se calla',
          );
          expect(
            c.noMaterializadas.every(
              (n) =>
                  n.motivo == MotivoDeNoMaterializacion.enlaceQueNoQuedaAdentro,
            ),
            isTrue,
          );
          return null;
        });
      },
    );

    test('un enlace cuyo DESTINO no es UTF-8 no se recrea', () async {
      // El destino se decodificaba con reemplazo, así que un enlace con bytes
      // inválidos se creaba apuntando a otro lado —con caracteres de
      // reemplazo— y el candidato parecía materializado. Las rutas ya se
      // decodificaban estricto; el destino no, y son el mismo problema.
      final crudo = File('${raiz.path}/destino-crudo');
      crudo.writeAsBytesSync([0xff, 0xfe, 0x2f, 0x61]);
      final blob = git(['hash-object', '-w', crudo.path]);
      crudo.deleteSync();
      git(['update-index', '--add', '--cacheinfo', '120000,$blob,enlace-raro']);
      git(['commit', '-m', 'enlace raro']);
      escribir('a.txt', 'x\n');

      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(
          FileSystemEntity.typeSync(
            '${c.root}/enlace-raro',
            followLinks: false,
          ),
          FileSystemEntityType.notFound,
          reason: 'no se crea un enlace que no es el que el árbol dice',
        );
        expect(c.noMaterializadas.map((n) => n.ruta), contains('enlace-raro'));
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
        expect(
          c.noMaterializadas.single.motivo,
          MotivoDeNoMaterializacion.referenciaAOtroRepositorio,
        );
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
        expect(
          File('${c.root}/con\nsalto.txt').readAsStringSync(),
          'nombre raro\n',
        );
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
        // **Sin `stat`.** `stat -f %Lp` es sintaxis BSD: pasaba en esta
        // máquina y habría fallado en el runner de CI, que es Ubuntu. El modo
        // lo da la biblioteca estándar, sin depender de qué `stat` haya.
        expect(
          File('${c.root}/ejec.sh').statSync().mode & 0x1FF,
          0x1ED,
          reason: '0o755',
        );
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
        programaChmod: '${raiz.path}/no-existe-chmod',
      );
      expect(
        () => sinChmod.prepareCandidate(rebanada(['a.txt'])),
        throwsA(anyOf(isA<PromesaIncumplida>(), isA<ProcessException>())),
      );
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
        final d = await aplicar(c);
        expect(d, isA<Committed>());
        expect(git(['rev-parse', 'HEAD^{tree}']), esperado);
        expect(git(['cat-file', 'blob', 'HEAD:sub/hondo.txt']), 'anidado v2');
        return null;
      });
    });

    test(
      'el contenido resuelve desde el repositorio real, sin alternates',
      () async {
        escribir('sub/hondo.txt', 'anidado v2\n');
        final c = await repo.prepareCandidate(rebanada(['sub/hondo.txt']));
        final contenido = c.identity.contentRevision;
        await aplicar(c);
        await c.dispose();
        // Sin `GIT_ALTERNATE_OBJECT_DIRECTORIES`, y con el temporal borrado.
        expect(git(['cat-file', '-t', contenido]), 'tree');
      },
    );
  });

  group('el compare-and-swap', () {
    test('con HEAD movido: NO aplica, y el trabajo ajeno sobrevive', () async {
      escribir('a.txt', 'lo mío\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        escribir('ajeno.txt', 'commit ajeno\n');
        git(['add', 'ajeno.txt']);
        git(['commit', '-m', 'ajeno']);
        final movido = git(['rev-parse', 'HEAD']);

        final d = await aplicar(c);
        expect(d, isA<NotApplied>());
        final na = d as NotApplied;
        expect(na.causa, CausaDeNoAplicacion.baseMovida);
        expect(na.ramaObservada, isNull);
        expect(na.baseEsperada, c.identity.baseRevision);
        expect(na.headObservado, movido);
        expect(
          git(['rev-parse', 'HEAD']),
          movido,
          reason: 'la rama quedó intacta',
        );
        expect(git(['rev-parse', 'refs/heads/main']), movido);
        expect(
          na.revision,
          isNotEmpty,
          reason: 'el objeto commit existe y queda inalcanzable: no es daño',
        );
        expect(git(['cat-file', '-t', na.revision]), 'commit');
        return null;
      });
    });

    test('si el usuario cambió de rama, no se aplica nada', () async {
      escribir('a.txt', 'lo mío\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        final antes = git(['rev-parse', 'refs/heads/main']);
        git(['switch', '--create', 'otra']);
        final d = await aplicar(c);
        expect(d, isA<NotApplied>());
        final na = d as NotApplied;
        expect(na.causa, CausaDeNoAplicacion.ramaCambiada);
        expect(na.ramaObservada, 'otra');
        // **La revisión existe igual.** Se crea antes de mirar la rama, así
        // que este desenlace nunca sale con una revisión en blanco — que es
        // exactamente lo que pasaba antes.
        expect(na.revision, isNotEmpty);
        expect(git(['cat-file', '-t', na.revision]), 'commit');
        expect(
          git(['rev-parse', 'refs/heads/main']),
          antes,
          reason: 'no se mueve una rama que no está puesta',
        );
        return null;
      });
    });

    test('tras aplicar, el índice queda al día', () async {
      // Sin esto `git status` reporta lo recién commiteado como borrado.
      // `commit-tree` no toca el índice: no es `git commit`.
      escribir('a.txt', 'modificado\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        await aplicar(c);
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
      expect(
        () => repo.prepareCandidate(rebanada(['a.txt'])),
        throwsA(isA<RebanadaNoAplicable>()),
      );
    });

    test('un repositorio sin ningún commit', () async {
      final vacio = Directory.systemTemp.createTempSync('vacio_');
      addTearDown(() => vacio.deleteSync(recursive: true));
      Process.runSync('git', [
        'init',
        '--initial-branch=main',
        '.',
      ], workingDirectory: vacio.path);
      File('${vacio.path}/a.txt').writeAsStringSync('x\n');
      final r = RepositorioGit(
        directorio: vacio.path,
        politica: const _TodoEsFuente(),
      );
      expect(
        () => r.prepareCandidate(rebanada(['a.txt'])),
        throwsA(isA<RebanadaNoAplicable>()),
      );
    });

    test('un merge sin resolver', () async {
      git(['switch', '--create', 'rama-b']);
      escribir('a.txt', 'de la rama b\n');
      git(['commit', '-am', 'b']);
      git(['switch', 'main']);
      escribir('a.txt', 'de main\n');
      git(['commit', '-am', 'main']);
      Process.runSync('git', ['merge', 'rama-b'], workingDirectory: raiz.path);
      expect(
        () => repo.prepareCandidate(rebanada(['a.txt'])),
        throwsA(isA<RebanadaNoAplicable>()),
      );
    });

    test('commit sobre un candidato ya liberado no escribe nada', () async {
      escribir('a.txt', 'x\n');
      final c = await repo.prepareCandidate(rebanada(['a.txt']));
      final antes = git(['rev-parse', 'HEAD']);
      await c.dispose();
      await expectLater(c.createRevision(), throwsA(isA<StateError>()));
      await expectLater(c.applyRevision(), throwsA(isA<StateError>()));
      expect(git(['rev-parse', 'HEAD']), antes);
    });
  });

  group('el secreto corta el commit por LOS DOS caminos', () {
    // **El hallazgo que este archivo no tenía.** `apply` bloqueaba secretos
    // porque el escaneo está adentro; el candidato los dejaba pasar porque lo
    // dejé para el llamador. Un puerto con dos caminos de escritura y dos
    // garantías distintas es peor que un puerto sin el camino nuevo.
    const clave = 'const k = "AKIAIOSFODNN7EXAMPLE";\n';

    test('createRevision se niega, y no escribe NADA', () async {
      escribir('a.txt', clave);
      final antes = objetosDelRepo();
      final cabeza = git(['rev-parse', 'HEAD']);
      await conCandidato(rebanada(['a.txt']), (c) async {
        await expectLater(
          c.createRevision(),
          throwsA(isA<SecretoEnLaRebanada>()),
        );
        return null;
      });
      expect(
        objetosDelRepo().difference(antes),
        isEmpty,
        reason: 'se niega ANTES de promover: cero objetos nuevos',
      );
      expect(git(['rev-parse', 'HEAD']), cabeza);
    });

    test('el hallazgo viaja como dato, no como mensaje', () async {
      // Quien tenga que ordenar una precedencia entre causas no puede estar
      // obligado a parsear una frase.
      escribir('a.txt', clave);
      await conCandidato(rebanada(['a.txt']), (c) async {
        try {
          await c.createRevision();
          fail('tenía que negarse');
        } on SecretoEnLaRebanada catch (e) {
          expect(e.hallazgos, isNotEmpty);
          expect(e.hallazgos.first.archivo, 'a.txt');
          expect(e.hallazgos.first.linea, greaterThan(0));
        }
        return null;
      });
    });

    test('apply da la MISMA causa tipada', () async {
      escribir('b.txt', clave);
      git(['add', 'b.txt']);
      git(['commit', '-m', 'x']);
      escribir('b.txt', clave.replaceFirst('EXAMPLE', 'EXAMPLF'));
      expect(
        () => repo.apply(rebanada(['b.txt'])),
        throwsA(isA<SecretoEnLaRebanada>()),
      );
    });
  });

  group('el escaneo se puede pedir antes de escribir nada', () {
    // El diseño lo pone en el paso 5, antes de la previsualización: mientras
    // el único escaneo viviera dentro de `createRevision` —el paso 11—, una
    // corrida sin `--yes` se comportaba como una previsualización, nunca
    // llegaba ahí, y el secreto no aparecía nunca.
    const clave = 'const k = "AKIAIOSFODNN7EXAMPLE";\n';

    test('el escaneo se puede pedir SIN escribir ningún objeto', () async {
      escribir('a.txt', clave);
      await conCandidato(rebanada(['a.txt']), (c) async {
        // **Contra el almacén TEMPORAL, no el real.** `exigirSinSecretos`
        // nunca promueve, así que comprobar solo el almacén real no
        // distinguiría este paso de una implementación futura que sí
        // escribiera objetos sueltos ahí adentro — la aserción pasaría
        // igual, y el nombre de esta prueba mentiría. Listar `objetos` antes
        // y después es lo que de verdad puede ponerse rojo si eso pasa.
        final antes = objetosDelAlmacenTemporal(c);
        await expectLater(
          c.exigirSinSecretos(),
          throwsA(isA<SecretoEnLaRebanada>()),
        );
        expect(
          objetosDelAlmacenTemporal(c),
          antes,
          reason: 'el paso 5 no escribe en el almacén temporal del candidato',
        );
        return null;
      });
    });

    test(
      'la ventana REAL no la ve ningún escaneo, y la cubre otra cosa',
      () async {
        // **Lo que sí puede pasar entre el paso 4 y el 11**: un verificador
        // escribe un secreto en la raíz del candidato. No lo ve ninguno de los
        // dos escaneos —los dos diffean la revisión fijada, no el árbol de
        // trabajo—, y esta prueba lo fija en vez de dejarlo implícito en la
        // frase de que «el segundo cierra una ventana», que era falsa.
        //
        // Lo que la cubre son dos cosas: `alteraciones` la informa —y una
        // alteración vuelve la corrida no concluyente, aguas arriba— y lo que
        // se commitea es el árbol FIJADO, así que el secreto no entra al commit
        // ni aunque alguien autorice publicar una corrida incompleta.
        escribir('a.txt', 'limpio\n');
        await conCandidato(rebanada(['a.txt']), (c) async {
          File('${c.root}/a.txt').writeAsStringSync(clave);

          // Ninguno de los dos escaneos lo ve: los dos miran lo fijado.
          await c.exigirSinSecretos();
          final revision = await c.createRevision();

          // Lo informa la comprobación de integridad, que es la que sí mira el
          // árbol del candidato.
          expect(
            {for (final a in await c.alteraciones()) a.ruta},
            contains('a.txt'),
            reason: 'sin esto, la escritura en la raíz no la ve NADIE',
          );

          // Y el commit se lleva el árbol fijado, no el workspace.
          expect(
            git(['cat-file', 'blob', '$revision:a.txt']),
            'limpio',
            reason: 'lo que se commitea es la revisión fijada',
          );
          return null;
        });
      },
    );

    test('createRevision escanea POR SU CUENTA: la garantía del commit no '
        'depende de que se haya pedido el paso 5', () async {
      // **Lo que se mide es la independencia del llamador, no una ventana.**
      // Los dos escaneos miran el mismo par de revisiones inmutables, así que
      // el segundo no puede encontrar nada que el primero no haya encontrado;
      // lo que sostiene la repetición es que la promesa «una rebanada con
      // secretos no se commitea» valga sin condiciones, y no solo si quien
      // llama se acordó de pedir la otra operación antes. La divergencia que
      // hace falta para observarlo la fabrica un ayudante desde afuera — ver
      // su doc: ningún camino del comando la produce.
      escribir('a.txt', 'limpio\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        await c.exigirSinSecretos(); // pasa: todavía no hay secreto
        ensuciarElArbolDelCandidato(c, 'a.txt', clave);
        await expectLater(
          c.createRevision(),
          throwsA(isA<SecretoEnLaRebanada>()),
        );
        return null;
      });
    });
  });

  group('la revisión se puede persistir antes de mover la rama', () {
    test('createRevision no mueve NINGUNA referencia', () async {
      // La ventana que la separación cierra: entre crear el objeto y mover la
      // rama hay que poder anotar la revisión. Si fueran una sola operación,
      // un proceso que muriera en el medio dejaría una revisión que no quedó
      // en ningún lado.
      escribir('a.txt', 'modificado\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        final antes = git(['rev-parse', 'HEAD']);
        final revision = await c.createRevision();
        expect(
          git(['cat-file', '-t', revision]),
          'commit',
          reason: 'el objeto existe y se puede persistir',
        );
        expect(
          git(['rev-parse', 'HEAD']),
          antes,
          reason: 'y la rama no se movió',
        );
        expect(await c.applyRevision(), isA<Committed>());
        expect(git(['rev-parse', 'HEAD']), revision);
        return null;
      });
    });

    test('createRevision es idempotente: dos llamadas, una revisión', () async {
      // Crearla dos veces daría dos objetos distintos por la fecha del
      // committer, y el segundo no sería el que alguien persistió.
      escribir('a.txt', 'modificado\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(await c.createRevision(), await c.createRevision());
        return null;
      });
    });

    test('aplicar sin haber creado la revisión no escribe', () async {
      escribir('a.txt', 'modificado\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        final antes = git(['rev-parse', 'HEAD']);
        await expectLater(c.applyRevision(), throwsA(isA<StateError>()));
        expect(git(['rev-parse', 'HEAD']), antes);
        return null;
      });
    });
  });

  group('el índice que no se pudo sincronizar', () {
    test('da LocalInconsistent, con el commit hecho y su revisión', () async {
      // **No había ninguna prueba de este desenlace.** El commit existe y no
      // se deshace; lo que quedó mal es el índice. Se fuerza con un `git` al
      // que se le sacó una sola capacidad, que es como este repositorio prueba
      // que un guardia sabe fallar.
      final falso = '${raiz.path}/git-sin-reset';
      File(falso).writeAsStringSync(
        '#!/bin/sh\n'
        'for a in "\$@"; do [ "\$a" = reset ] && exit 9; done\n'
        'exec git "\$@"\n',
      );
      Process.runSync('chmod', ['700', falso]);

      escribir('a.txt', 'modificado\n');
      final r = RepositorioGit(
        directorio: raiz.path,
        politica: const _TodoEsFuente(),
        programa: falso,
      );
      final c = await r.prepareCandidate(rebanada(['a.txt']));
      try {
        await c.createRevision();
        final d = await c.applyRevision();
        expect(d, isA<LocalInconsistent>());
        final li = d as LocalInconsistent;
        expect(li.revision, isNotEmpty);
        expect(li.detalle, isNotEmpty);
        expect(
          git(['rev-parse', 'HEAD']),
          li.revision,
          reason: 'la rama SÍ avanzó: el commit no se deshace',
        );
      } finally {
        await c.dispose();
      }
    });
  });

  group('el formato del identificador no se supone', () {
    test('un repositorio sha256 se prepara y se aplica igual', () async {
      // Fijar la longitud en 40 dejaba fuera todo repositorio creado con
      // `--object-format=sha256`: el candidato se preparaba, no se promovía
      // nada, y la identidad fallaba con un mensaje que no nombraba la causa.
      final s256 = Directory.systemTemp.createTempSync('s256_');
      addTearDown(() => s256.deleteSync(recursive: true));
      void g(List<String> a) {
        final r = Process.runSync('git', a, workingDirectory: s256.path);
        if (r.exitCode != 0) {
          throw StateError('git ${a.join(" ")}: ${r.stderr}');
        }
      }

      g(['init', '--object-format=sha256', '--initial-branch=main', '.']);
      g(['config', 'user.email', 'p@p']);
      g(['config', 'user.name', 'p']);
      File('${s256.path}/a.txt').writeAsStringSync('uno\n');
      Directory('${s256.path}/sub').createSync();
      File('${s256.path}/sub/hondo.txt').writeAsStringSync('anidado\n');
      g(['add', '-A']);
      g(['commit', '-m', 'base']);

      final r = RepositorioGit(
        directorio: s256.path,
        politica: const _TodoEsFuente(),
      );
      File('${s256.path}/sub/hondo.txt').writeAsStringSync('anidado v2\n');
      final c = await r.prepareCandidate(rebanada(['sub/hondo.txt']));
      try {
        expect(
          c.identity.contentRevision.length,
          64,
          reason: 'la premisa: acá los identificadores son de 64',
        );
        await c.createRevision();
        expect(await c.applyRevision(), isA<Committed>());
        expect(
          (Process.runSync('git', [
                'cat-file',
                'blob',
                'HEAD:sub/hondo.txt',
              ], workingDirectory: s256.path).stdout
              as String),
          'anidado v2\n',
        );
      } finally {
        await c.dispose();
      }
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
      expect(
        File('${wt.path}/.git').existsSync(),
        isTrue,
        reason: 'la premisa: acá .git es un ARCHIVO',
      );

      final desdeWt = RepositorioGit(
        directorio: wt.path,
        politica: const _TodoEsFuente(),
      );
      File('${wt.path}/a.txt').writeAsStringSync('desde el worktree\n');
      final c = await desdeWt.prepareCandidate(rebanada(['a.txt']));
      try {
        expect(
          File('${c.root}/a.txt').readAsStringSync(),
          'desde el worktree\n',
        );
        expect(await aplicar(c), isA<Committed>());
      } finally {
        await c.dispose();
      }
    });
  });

  group('la premisa de git, no la nuestra', () {
    test(
      'check-attr NO informa core.autocrlf: no hay preflight barato',
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
          'a.txt',
        ]);
        expect(salida, contains('unspecified'));
        expect(
          salida.split('\n').every((l) => l.endsWith('unspecified')),
          isTrue,
          reason: 'las tres claves sin especificar, con autocrlf activo',
        );
      },
    );

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
      Process.runSync('git', [
        'checkout-index',
        '-a',
        '--prefix=${salida.path}/',
      ], workingDirectory: raiz.path);
      final delObjeto = git(['cat-file', 'blob', 'HEAD:conmarca.txt']);
      final tras = File(
        '${salida.path}/conmarca.txt',
      ).readAsStringSync().trim();
      expect(
        tras,
        isNot(delObjeto),
        reason:
            'si esto deja de ser cierto, `checkout-index` volvió a ser '
            'una opción y hay que revisar la decisión, no el código',
      );
      expect(utf8.encode(tras), isNotEmpty);
    });
  });
}
