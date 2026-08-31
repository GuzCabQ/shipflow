/// El repositorio, contra `git` de verdad.
///
/// **No hay doble de `git`.** Es determinista, está instalado y es rápido: un
/// fake solo serviría para probar su ausencia, y para eso alcanza con cambiar
/// el nombre del ejecutable.
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

  void escribir(String nombre, String contenido) =>
      File('${raiz.path}/$nombre').writeAsStringSync(contenido);

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('vcs_');
    repo = RepositorioGit(directorio: raiz.path);
    Process.runSync('git', ['init', '--initial-branch=main', '.'],
        workingDirectory: raiz.path);
    Process.runSync('git', ['config', 'user.email', 'p@p'],
        workingDirectory: raiz.path);
    Process.runSync('git', ['config', 'user.name', 'prueba'],
        workingDirectory: raiz.path);
    escribir('a.txt', 'uno\n');
    escribir('b.txt', 'dos\n');
    Process.runSync('git', ['add', '-A'], workingDirectory: raiz.path);
    Process.runSync('git', ['commit', '-m', 'base'],
        workingDirectory: raiz.path);
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
      Process.runSync('git', ['add', '--', 'b.txt'],
          workingDirectory: raiz.path);

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

    test('un archivo que no existe NO se commitea en silencio', () async {
      await repo.useBranch('shipflow/x');
      expect(() => repo.apply(rebanada(['no/existe.txt'])),
          throwsA(isA<GitFallo>()));
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
