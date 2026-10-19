@Timeout(Duration(minutes: 5))
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../../tool/build_release.dart';
import '../../tool/src/checksum.dart';

Future<Directory> packageRoot() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:cli/cli.dart'),
  );
  return File.fromUri(barrel!).parent.parent;
}

String get hostPlatform => switch (Abi.current()) {
  Abi.macosArm64 => 'macos-arm64',
  Abi.linuxX64 => 'linux-x64',
  final other => throw StateError('host no declarado: $other'),
};

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shipflow-build-');
  });

  tearDown(() => directory.delete(recursive: true));

  group('plataformas declaradas', () {
    test('sólo macOS ARM64 y Linux x64 tienen nombre de release', () {
      expect(releasePlatformFor(Abi.macosArm64), 'macos-arm64');
      expect(releasePlatformFor(Abi.linuxX64), 'linux-x64');
      for (final abi in Abi.values) {
        if (abi == Abi.macosArm64 || abi == Abi.linuxX64) continue;
        expect(releasePlatformFor(abi), isNull, reason: '$abi');
      }
    });

    test('un host no declarado no produce artefacto', () async {
      final output = Directory('${directory.path}/release');
      await expectLater(
        buildRelease(version: '1.0.0', output: output, hostAbi: Abi.windowsX64),
        throwsA(
          isA<ReleaseBuildException>().having(
            (e) => e.message,
            'message',
            contains('no es una plataforma declarada'),
          ),
        ),
      );
      expect(directory.listSync(), isEmpty);
    });
  });

  group('build', () {
    test('un destino existente no se toca', () async {
      final output = await Directory('${directory.path}/release').create();
      final marker = File('${output.path}/previo')..writeAsStringSync('x');
      await expectLater(
        buildRelease(version: '1.0.0', output: output),
        throwsA(isA<ReleaseBuildException>()),
      );
      expect(output.listSync().map((e) => e.path), [marker.path]);
    });

    test('una compilación fallida no deja candidato', () async {
      final broken = File('${directory.path}/roto.dart')
        ..writeAsStringSync('void main( {\n');
      final output = Directory('${directory.path}/release');
      await expectLater(
        buildRelease(version: '1.0.0', output: output, entrypoint: broken),
        throwsA(
          isA<ReleaseBuildException>().having(
            (e) => e.message,
            'message',
            contains('no compiló'),
          ),
        ),
      );
      expect(directory.listSync().map((e) => e.path), [broken.path]);
    });

    test('un artefacto que informa otra versión se invalida', () async {
      final impostor = File('${directory.path}/impostor.dart')
        ..writeAsStringSync("void main() => print('shipflow 0.0.1');\n");
      final output = Directory('${directory.path}/release');
      await expectLater(
        buildRelease(version: '1.0.0', output: output, entrypoint: impostor),
        throwsA(
          isA<ReleaseBuildException>().having(
            (e) => e.message,
            'message',
            contains('no respondió «shipflow 1.0.0»'),
          ),
        ),
      );
      expect(directory.listSync().map((e) => e.path), [impostor.path]);
    });

    test(
      'sin herramienta de checksum no hay candidato ni digest vacío',
      () async {
        final output = Directory('${directory.path}/release');
        await expectLater(
          buildRelease(
            version: '1.0.0',
            output: output,
            checksumTool: ChecksumTool(
              executable: '${directory.path}/no-existe',
              arguments: [],
            ),
          ),
          throwsA(
            isA<ReleaseBuildException>().having(
              (e) => e.message,
              'message',
              contains('no se pudo ejecutar'),
            ),
          ),
        );
        expect(directory.listSync(), isEmpty);
      },
    );

    test(
      'si la limpieza del directorio de trabajo falla, el error sigue controlado',
      () async {
        final parent = await Directory('${directory.path}/padre').create();
        try {
          await expectLater(
            buildRelease(
              version: '1.0.0',
              output: Directory('${parent.path}/release'),
              checksumTool: _lockingChecksumTool,
            ),
            throwsA(_controlledCleanupFailure),
          );
        } finally {
          await Process.run('chmod', ['-R', 'u+w', parent.path]);
        }
      },
    );

    test(
      'la build oficial compila, ejecuta, compara y publica SHA256SUMS',
      () async {
        const version = '1.4.0-rc.1+ci.7';
        final root = await packageRoot();
        final output = '${directory.path}/release';
        final result = await _officialBuild(root, directory, version, output);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(result.stderr, '');

        final name = 'shipflow-$version-$hostPlatform';
        _expectOnlyPublished(directory, output, name);

        final digest = (await computeSha256(File('$output/$name'))).sha256;
        expect(
          File('$output/SHA256SUMS').readAsStringSync(),
          '$digest  $name\n',
        );
        await _expectChecksumsVerify(output);

        expect(
          await _versionInCleanEnvironment('$output/$name', directory),
          'shipflow $version\n',
        );
        expect(result.stdout, contains(digest));
        expect(result.stdout, contains('nativamente en $hostPlatform'));
      },
    );
  });
}

/// Una herramienta de checksum que, antes de fallar, deja el padre del
/// directorio de trabajo sin permiso de escritura.
const _lockingChecksumTool = ChecksumTool(
  executable: '/bin/sh',
  arguments: ['-c', r'chmod 0555 "$(dirname "$(dirname "$1")")"; exit 3', 'sh'],
);

/// El fallo de limpieza informado sin traza ni nombre de excepción.
final _controlledCleanupFailure = isA<ReleaseBuildException>().having(
  (e) => e.message,
  'message',
  allOf(
    contains('no se pudo borrar el directorio de trabajo'),
    contains('Permission denied'),
    isNot(contains('#0')),
    isNot(contains('Exception')),
  ),
);

Future<ProcessResult> _officialBuild(
  Directory root,
  Directory workingDirectory,
  String version,
  String output,
) => Process.run(Platform.resolvedExecutable, [
  'run',
  '${root.path}/tool/build_release.dart',
  '--version',
  version,
  '--output',
  output,
], workingDirectory: workingDirectory.path);

/// La herramienta del sistema acepta el SHA256SUMS publicado en [output].
Future<void> _expectChecksumsVerify(String output) async {
  final verify = await Process.run(Platform.isMacOS ? 'shasum' : 'sha256sum', [
    if (Platform.isMacOS) ...['-a', '256'],
    '-c',
    'SHA256SUMS',
  ], workingDirectory: output);
  expect(verify.exitCode, 0, reason: '${verify.stdout}${verify.stderr}');
}

/// [output] tiene sólo el artefacto y SHA256SUMS, y no queda directorio de
/// trabajo junto a él.
void _expectOnlyPublished(Directory directory, String output, String name) {
  final entries = Directory(output).listSync().map((e) => e.path).toList()
    ..sort();
  expect(entries, ['$output/SHA256SUMS', '$output/$name']);
  expect(
    directory.listSync().map((e) => e.path),
    [output],
    reason: 'no queda directorio de trabajo',
  );
}

/// Lo que [binary] responde a --version sin ninguna variable de entorno.
Future<Object?> _versionInCleanEnvironment(
  String binary,
  Directory workingDirectory,
) async => (await Process.run(
  binary,
  ['--version'],
  workingDirectory: workingDirectory.path,
  environment: const {},
  includeParentEnvironment: false,
)).stdout;
