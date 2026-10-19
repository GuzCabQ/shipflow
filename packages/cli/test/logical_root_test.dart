import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

import 'runner_support.dart';

void main() {
  final sandbox = RunnerSandbox()..register();

  Directory directory(String name) =>
      Directory('${sandbox.root.path}/$name')..createSync(recursive: true);

  /// Un enlace `alias` → `real`, ambos dentro de la raíz temporal.
  ({String alias, String real}) aliased() {
    final real = directory('real').path;
    final alias = '${sandbox.root.path}/alias';
    Link(alias).createSync(real);
    return (alias: alias, real: real);
  }

  group('corroborateLogicalRoot', () {
    test('un alias que resuelve al cwd se conserva', () async {
      final (:alias, :real) = aliased();
      expect(await corroborateLogicalRoot(alias, canonicalRoot: real), alias);
    });

    test('sin pista, relativa, a otra carpeta o rota se ignora', () async {
      final (:alias, :real) = aliased();
      final other = directory('otra').path;
      final broken = '${sandbox.root.path}/rota';
      Link(broken).createSync('${sandbox.root.path}/no-existe');
      for (final pwd in [null, '', 'alias', '../alias', other, broken]) {
        expect(
          await corroborateLogicalRoot(pwd, canonicalRoot: real),
          isNull,
          reason: '$pwd',
        );
      }
      expect(alias, isNotEmpty);
    });

    test('una pista que no se puede resolver por permisos se ignora', () async {
      final real = directory('cerrada/real').path;
      final alias = '${sandbox.root.path}/cerrada/alias';
      Link(alias).createSync(real);
      await Process.run('chmod', ['000', '${sandbox.root.path}/cerrada']);
      expect(await corroborateLogicalRoot(alias, canonicalRoot: real), isNull);
    });

    // Inyección: un PWD con NUL o de miles de bytes no se puede construir
    // como directorio real; se prueba que ni siquiera llega a resolverse.
    group('por inyección del resolvedor', () {
      final resolved = <String>[];
      Future<String> resolver(String path) async {
        resolved.add(path);
        return '/canonica';
      }

      setUp(resolved.clear);

      test('NUL se rechaza sin resolver', () async {
        expect(
          await corroborateLogicalRoot(
            '/a\x00b',
            canonicalRoot: '/canonica',
            resolve: resolver,
          ),
          isNull,
        );
        expect(resolved, isEmpty);
      });

      test('4096 bytes UTF-8 se aceptan y 4097 no', () async {
        // `/` más 2047 `ñ` (2 bytes cada una) más una `a`: 4096 bytes.
        final edge = '/${'ñ' * 2047}a';
        expect(utf8.encode(edge).length, 4096);
        final over = '/${'ñ' * 2048}';
        expect(utf8.encode(over).length, 4097);
        expect(
          await corroborateLogicalRoot(
            edge,
            canonicalRoot: '/canonica',
            resolve: resolver,
          ),
          edge,
        );
        expect(
          await corroborateLogicalRoot(
            over,
            canonicalRoot: '/canonica',
            resolve: resolver,
          ),
          isNull,
        );
        expect(resolved, [edge]);
      });
    });
  });

  group('el runner', () {
    test('pwd_forged_does_not_retarget', () async {
      sandbox.received.clear();
      final other = directory('otra').path;
      final response = await sandbox.run([
        'init',
        '--dry-run',
        '--json',
      ], logicalRootHint: other);
      expect(decode(response)['requestedRoot'], sandbox.root.path);
      expect(decode(response)['resolvedRoot'], sandbox.root.path);
      expect(sandbox.received, [sandbox.root.path]);
    });

    test('un alias corroborado distingue ambas rutas', () async {
      final (:alias, :real) = aliased();
      final response = await sandbox.run(
        ['init', '--dry-run', '--json'],
        workingDirectory: Directory(real),
        logicalRootHint: alias,
      );
      expect(decode(response)['requestedRoot'], alias);
      expect(decode(response)['resolvedRoot'], real);
      expect(sandbox.received, [real]);
    });

    // Inyección: el ejecutable no puede probar este caso. Con el cwd borrado
    // o inaccesible, el runtime de Dart sale con 255 antes de llegar a main.
    test('invalid_cwd_is_not_rescued', () async {
      final valid = directory('valida').path;
      final response = await sandbox.run(
        ['init', '--dry-run', '--json'],
        workingDirectory: Directory('${sandbox.root.path}/no-existe'),
        logicalRootHint: valid,
      );
      expect(response.exitCode, 66);
      expect(decode(response)['status'], 'invalid_root');
      expect(decode(response)['requestedRoot'], isNot(valid));
      expect(sandbox.received, isEmpty);
    });

    test('ayuda y uso inválido no corroboran ni reconocen', () async {
      final (:alias, real: _) = aliased();
      for (final arguments in [
        ['--help'],
        ['init'],
      ]) {
        await sandbox.run(arguments, logicalRootHint: alias);
      }
      expect(sandbox.received, isEmpty);
    });
  });
}
