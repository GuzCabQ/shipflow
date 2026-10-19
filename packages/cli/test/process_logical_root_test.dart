@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'init_process_support.dart';

void main() {
  final sandbox = InitProcessSandbox()..register();

  /// `alias` → `real/`, con un paquete Dart en `real`.
  ({Directory alias, Directory real}) aliased() {
    sandbox.place('real/pubspec.yaml', 'name: app\n');
    final real = Directory('${sandbox.root.path}/real');
    final alias = Directory('${sandbox.root.path}/alias');
    Link(alias.path).createSync(real.path);
    return (alias: alias, real: real);
  }

  Future<Map<String, Object?>> recognize(
    Directory at,
    Map<String, String> environment,
  ) async {
    final result = await sandbox.run(
      ['init', '--dry-run', '--json'],
      at: at,
      environment: environment,
    );
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0, reason: result.stdout);
    return result.json;
  }

  test('alias_survives_public_binary', () async {
    final (:alias, :real) = aliased();
    final json = await recognize(alias, {'PWD': alias.path});
    expect(json['requestedRoot'], alias.path);
    expect(json['resolvedRoot'], real.path);
  });

  test('sin PWD, o relativo, ambas rutas son la real', () async {
    final (:alias, :real) = aliased();
    for (final environment in [
      const <String, String>{},
      const {'PWD': 'alias'},
    ]) {
      final json = await recognize(alias, environment);
      expect(json['requestedRoot'], real.path, reason: '$environment');
      expect(json['resolvedRoot'], real.path, reason: '$environment');
    }
  });

  test('un PWD falso desde la raíz real no la cambia', () async {
    final (alias: _, :real) = aliased();
    sandbox.place('otra/pubspec.yaml', 'name: otra\n');
    final json = await recognize(real, {'PWD': '${sandbox.root.path}/otra'});
    expect(json['requestedRoot'], real.path);
    expect(json['resolvedRoot'], real.path);
    expect((json['units']! as List).single, containsPair('name', 'app'));
  });
}
