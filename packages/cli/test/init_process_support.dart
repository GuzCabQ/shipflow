import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

const v1Version = '0.0.0-v1-test';

Future<Directory> cliRoot() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:cli/cli.dart'),
  );
  return File.fromUri(barrel!).parent.parent;
}

Future<Directory> pilotShape() async => Directory(
  '${(await cliRoot()).parent.path}/plugin_dart/test/fixtures/smooth_app_shape',
);

/// Ruta relativa, tipo, bytes y destino de cada entrada bajo [root]: cambia
/// si algo se crea, se borra, se reescribe o se reapunta. No mira fechas de
/// acceso, que una lectura sí altera.
Map<String, String> treeSnapshot(Directory root) => {
  for (final entity in root.listSync(recursive: true, followLinks: false))
    entity.path.substring(root.path.length + 1): switch (entity) {
      Link() => 'enlace → ${entity.targetSync()}',
      File() => 'archivo ${base64.encode(entity.readAsBytesSync())}',
      Directory() => 'directorio',
      _ => 'otro',
    },
};

final class RunResult {
  RunResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  Map<String, Object?> get json => jsonDecode(stdout) as Map<String, Object?>;
}

/// El ejecutable V1 compilado una vez, en un sandbox fuera del checkout con
/// HOME y TMPDIR propios, y una raíz temporal canónica por prueba.
final class InitProcessSandbox {
  late Directory sandbox;
  late Directory home;
  late Directory temp;
  late String binary;
  late String entrypoint;
  late Directory root;

  void register() {
    setUpAll(_compile);
    tearDownAll(() => _remove(sandbox));
    setUp(() async {
      final created = await Directory.systemTemp.createTemp('shipflow-v1-');
      root = Directory(created.resolveSymbolicLinksSync());
    });
    tearDown(() => _remove(root));
  }

  Future<void> _compile() async {
    final created = await Directory.systemTemp.createTemp('shipflow-v1-bin-');
    sandbox = Directory(created.resolveSymbolicLinksSync());
    home = await Directory('${sandbox.path}/home').create();
    temp = await Directory('${sandbox.path}/tmp').create();
    binary = '${sandbox.path}/shipflow';
    entrypoint = '${(await cliRoot()).path}/bin/shipflow.dart';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSHIPFLOW_VERSION=$v1Version',
      '-o',
      binary,
      entrypoint,
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
  }

  File place(String relative, [String content = 'name: x\n']) =>
      File('${root.path}/$relative')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);

  /// [environment] se agrega a HOME y TMPDIR; nunca se hereda el global.
  Future<RunResult> run(
    List<String> arguments, {
    Directory? at,
    Map<String, String> environment = const {},
  }) => _run(binary, arguments, at ?? root, environment);

  /// El mismo contrato desde el código fuente, con `dart <entrypoint>`.
  Future<RunResult> runSource(List<String> arguments, {Directory? at}) => _run(
    Platform.resolvedExecutable,
    [entrypoint, ...arguments],
    at ?? root,
    const {},
  );

  Future<RunResult> _run(
    String executable,
    List<String> arguments,
    Directory at,
    Map<String, String> environment,
  ) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: at.path,
      environment: {'HOME': home.path, 'TMPDIR': temp.path, ...environment},
      includeParentEnvironment: false,
    );
    return RunResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }
}

Future<void> _remove(Directory directory) async {
  if (!directory.existsSync()) return;
  await Process.run('chmod', ['-R', 'u+rwx', directory.path]);
  await directory.delete(recursive: true);
}
