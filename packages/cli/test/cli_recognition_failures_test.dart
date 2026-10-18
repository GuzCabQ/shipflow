import 'dart:io';

import 'package:test/test.dart';

import 'runner_support.dart';

void main() {
  final sandbox = RunnerSandbox()..register();

  Future<Map<String, Object?>> invalid(Directory workingDirectory) async {
    final response = await sandbox.run(
      ['init', '--dry-run', '--json'],
      workingDirectory: workingDirectory,
      contributor: (_) => fail('una raíz inválida no se reconoce'),
    );
    expect(response.exitCode, 66);
    final body = decode(response);
    expect(body['status'], 'invalid_root');
    expect(body['resolvedRoot'], isNull);
    expect(body['requestedRoot'], workingDirectory.absolute.path);
    return body;
  }

  String reason(Map<String, Object?> body) =>
      ((body['limitations']! as List).single as Map)['code']! as String;

  test('una raíz inexistente', () async {
    final body = await invalid(Directory('${sandbox.root.path}/no-existe'));
    expect(reason(body), 'root_not_found');
  });

  test('una raíz que es un archivo', () async {
    final file = File('${sandbox.root.path}/plano')..writeAsStringSync('x');
    expect(reason(await invalid(Directory(file.path))), 'root_not_directory');
  });

  test('un enlace roto', () async {
    final link = Link('${sandbox.root.path}/roto')
      ..createSync('${sandbox.root.path}/nada');
    expect(reason(await invalid(Directory(link.path))), 'root_not_found');
  });

  test('una raíz sin permiso de lectura', () async {
    final closed = Directory('${sandbox.root.path}/cerrada')..createSync();
    await Process.run('chmod', ['000', closed.path]);
    expect(reason(await invalid(closed)), 'root_inaccessible');
  });

  test(
    'un defecto del reconocedor sale de runCli con su objeto y su traza',
    () async {
      final defect = StateError('defecto');
      final trace = StackTrace.current;
      Object? thrown;
      StackTrace? stack;
      try {
        await sandbox.run([
          'init',
          '--dry-run',
          '--json',
        ], contributor: (_) => Future.error(defect, trace));
      } on Object catch (error, s) {
        thrown = error;
        stack = s;
      }
      expect(thrown, same(defect));
      expect(stack.toString(), trace.toString());
    },
  );
}
