/// El `.gitignore` de las corridas: no alcanza con que exista, tiene que
/// ignorar la ruta.
///
/// **Contra `git` de verdad**, igual que `repositorio_test.dart` de `vcs`: es
/// determinista, está instalado y es rápido, y un doble de `check-ignore`
/// solo probaría que el doble hace lo que se le programó, no que `git`
/// protege la ruta de verdad.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

void main() {
  late Directory raizRepo;
  late RepositorioGit repo;
  late String raiz;

  void git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: raizRepo.path);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
    }
  }

  setUp(() {
    raizRepo = Directory.systemTemp.createTempSync('ship_gitignore_');
    git(['init', '--initial-branch=main', '.']);
    git(['config', 'user.email', 'p@p']);
    git(['config', 'user.name', 'prueba']);
    File('${raizRepo.path}/README.md').writeAsStringSync('x\n');
    git(['add', '-A']);
    git(['commit', '-m', 'base']);
    repo = RepositorioGit(
      directorio: raizRepo.path,
      politica: const PoliticaDeArtefactosDart(),
    );
    // `.shipflow` no existe todavía: es exactamente la situación del primer
    // uso, que el preflight no puede exigir y esta operación sí resuelve.
    raiz = '${raizRepo.path}/.shipflow';
  });

  tearDown(() => raizRepo.deleteSync(recursive: true));

  test('se crea con `*` si no hay ninguno', () async {
    await asegurarGitignore(raiz);
    expect(await File('$raiz/.gitignore').readAsString(), contains('*'));
  });

  test('crea el directorio si todavía no existe: el primer uso', () async {
    expect(
      Directory(raiz).existsSync(),
      isFalse,
      reason: '`.shipflow` no existe antes de la primera corrida',
    );
    await asegurarGitignore(raiz);
    expect(Directory(raiz).existsSync(), isTrue);
  });

  test('uno existente y DISTINTO no se sobrescribe: falla', () async {
    await Directory(raiz).create(recursive: true);
    await File('$raiz/.gitignore').writeAsString('!importante\n');
    await expectLater(asegurarGitignore(raiz), throwsA(isA<GitignoreAjeno>()));
    expect(
      await File('$raiz/.gitignore').readAsString(),
      '!importante\n',
      reason: 'el contenido de alguien más no se pisa',
    );
  });

  test('uno existente e IGUAL no es un error', () async {
    await asegurarGitignore(raiz);
    await expectLater(asegurarGitignore(raiz), completes);
  });

  test('la comprobación pregunta por la RUTA, no por el archivo', () async {
    // Un `.gitignore` puede existir y no aplicar. Lo que importa es si `git`
    // ignora la ruta, y eso lo contesta `git`.
    await asegurarGitignore(raiz);
    expect(await corridasIgnoradas(repo, '$raiz/runs/r-1.json'), isTrue);
  });

  test('si una regla de negación lo desprotege, se detecta', () async {
    await asegurarGitignore(raiz);
    // Negar solo el directorio no alcanza —la prueba siguiente lo mide—:
    // `*` empareja también el nombre de cada archivo, en cualquier
    // profundidad, así que hace falta negar el directorio Y su contenido
    // para que la ruta deje de estar protegida. Es exactamente la clase de
    // `.gitignore` que existe y no aplica del todo, que el diseño de esta
    // tarea nombra.
    await File('$raiz/.gitignore').writeAsString('*\n!runs/\n!runs/*\n');
    expect(await corridasIgnoradas(repo, '$raiz/runs/r-1.json'), isFalse);
  });

  test('negar solo el directorio no desprotege lo que hay adentro', () async {
    await asegurarGitignore(raiz);
    // Medido contra `git` real: `!runs/` reincluye el directorio, pero
    // `*` sigue emparejando `r-1.json` por su propio nombre. Sin esto, la
    // prueba anterior podría estar pasando por casualidad y no porque
    // `corridasIgnoradas` de verdad le pregunte a `git`.
    await File('$raiz/.gitignore').writeAsString('*\n!runs/\n');
    expect(
      await corridasIgnoradas(repo, '$raiz/runs/r-1.json'),
      isTrue,
      reason:
          'reincluir el directorio no reincluye, por sí solo, lo que '
          'tiene adentro',
    );
  });
}
