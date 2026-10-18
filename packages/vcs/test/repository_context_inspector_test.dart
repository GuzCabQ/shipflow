import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp('shipflow-vcs-');
    sandbox = Directory(temporary.resolveSymbolicLinksSync());
  });

  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+rwx', sandbox.path]);
    await sandbox.delete(recursive: true);
  });

  Directory directory(String relative) =>
      Directory('${sandbox.path}/$relative')..createSync(recursive: true);

  void expectContext(
    RepositoryContext context,
    RepositoryStatus status,
    String? root,
    RepositoryRelation relation,
  ) {
    expect(context.toJson(), {
      'status': status.toWireName(),
      'root': root,
      'relation': relation.toWireName(),
    });
  }

  group('marcador directorio', () {
    test('en la misma raíz', () async {
      final root = directory('proyecto');
      directory('proyecto/.git');
      expectContext(
        await inspectRepositoryContext(root),
        RepositoryStatus.detected,
        root.path,
        RepositoryRelation.same,
      );
    });

    test('en un ancestro, sin reemplazar la raíz', () async {
      final repository = directory('repo');
      directory('repo/.git');
      final root = directory('repo/packages/app');
      expectContext(
        await inspectRepositoryContext(root),
        RepositoryStatus.detected,
        repository.path,
        RepositoryRelation.ancestor,
      );
    });

    test('el más cercano gana', () async {
      directory('externo/.git');
      final inner = directory('externo/interno');
      directory('externo/interno/.git');
      expectContext(
        await inspectRepositoryContext(inner),
        RepositoryStatus.detected,
        inner.path,
        RepositoryRelation.same,
      );
    });

    test('sin marcador es ausente', () async {
      expectContext(
        await inspectRepositoryContext(directory('suelto')),
        RepositoryStatus.absent,
        null,
        RepositoryRelation.none,
      );
    });

    test('un nombre que sólo contiene .git no es un marcador', () async {
      directory('proyecto.git/.gitignore-no');
      expectContext(
        await inspectRepositoryContext(directory('proyecto.git')),
        RepositoryStatus.absent,
        null,
        RepositoryRelation.none,
      );
    });
  });

  group('marcador archivo', () {
    late Directory root;
    late File marker;

    setUp(() {
      root = directory('worktree');
      marker = File('${root.path}/.git');
    });

    Future<void> expectIndeterminate() async => expectContext(
      await inspectRepositoryContext(root),
      RepositoryStatus.indeterminate,
      root.path,
      RepositoryRelation.same,
    );

    test('gitdir relativo a un directorio existente', () async {
      directory('principal/.git/worktrees/w');
      marker.writeAsStringSync('gitdir: ../principal/.git/worktrees/w\n');
      expectContext(
        await inspectRepositoryContext(root),
        RepositoryStatus.detected,
        root.path,
        RepositoryRelation.same,
      );
    });

    test('gitdir absoluto a un directorio existente', () async {
      final target = directory('principal/.git/worktrees/w');
      marker.writeAsStringSync('gitdir: ${target.path}');
      expectContext(
        await inspectRepositoryContext(root),
        RepositoryStatus.detected,
        root.path,
        RepositoryRelation.same,
      );
    });

    test('más de 4096 bytes es indeterminado', () async {
      final target = directory('principal/.git');
      marker.writeAsStringSync('gitdir: ${target.path}${' ' * 4096}');
      await expectIndeterminate();
    });

    test('justo 4096 bytes se lee', () async {
      final target = directory('principal/.git');
      final line = 'gitdir: ${target.path}';
      marker.writeAsStringSync(line.padRight(4096));
      expect(marker.lengthSync(), 4096);
      expectContext(
        await inspectRepositoryContext(root),
        RepositoryStatus.detected,
        root.path,
        RepositoryRelation.same,
      );
    });

    test('varias líneas son indeterminadas', () async {
      final target = directory('principal/.git');
      marker.writeAsStringSync(
        'gitdir: ${target.path}\ngitdir: ${target.path}',
      );
      await expectIndeterminate();
    });

    test('sin directiva gitdir es indeterminado', () async {
      marker.writeAsStringSync('otra cosa\n');
      await expectIndeterminate();
    });

    test('un destino inexistente es indeterminado', () async {
      marker.writeAsStringSync('gitdir: ../no-existe\n');
      await expectIndeterminate();
    });

    test('un destino que es archivo es indeterminado', () async {
      File('${sandbox.path}/plano').writeAsStringSync('x');
      marker.writeAsStringSync('gitdir: ../plano\n');
      await expectIndeterminate();
    });

    test('bytes que no son UTF-8 son indeterminados', () async {
      marker.writeAsBytesSync([0x67, 0x69, 0xff, 0xfe]);
      await expectIndeterminate();
    });

    test('un marcador ilegible es indeterminado, no ausente', () async {
      final target = directory('principal/.git');
      marker.writeAsStringSync('gitdir: ${target.path}\n');
      await Process.run('chmod', ['000', marker.path]);
      await expectIndeterminate();
    });

    test('un marcador que es enlace simbólico no se sigue', () async {
      final target = directory('principal/.git');
      Link(marker.path).createSync(target.path);
      await expectIndeterminate();
    });
  });
}
