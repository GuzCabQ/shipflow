import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

Future<Directory> packageRoot() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:cli/cli.dart'),
  );
  return File.fromUri(barrel!).parent.parent;
}

void main() {
  late String entrypoint;

  setUpAll(() async {
    entrypoint = '${(await packageRoot()).path}/bin/shipflow.dart';
  });

  group('entrypoint en desarrollo', () {
    test('sin declaración de compilación informa 0.0.0-dev', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        entrypoint,
        '--version',
      ]);
      expect(result.stdout, 'shipflow 0.0.0-dev\n');
      expect(result.stderr, '');
      expect(result.exitCode, 0);
    });

    test('con -DSHIPFLOW_VERSION informa la versión declarada', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        '-DSHIPFLOW_VERSION=4.5.6-dev.1',
        entrypoint,
        '--version',
      ]);
      expect(result.stdout, 'shipflow 4.5.6-dev.1\n');
      expect(result.stderr, '');
      expect(result.exitCode, 0);
    });

    test('el uso inválido sale por stderr con código 64', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        entrypoint,
        '--inventada',
      ]);
      expect(result.stdout, '');
      expect(
        result.stderr,
        "shipflow: opción desconocida: '--inventada'\n"
        "Usa 'shipflow --help'.\n",
      );
      expect(result.exitCode, 64);
    });
  });
}
