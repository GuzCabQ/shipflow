@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../../tool/build_release.dart';
import '../../tool/src/checksum.dart';

const abcDigest =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

final class _Collector implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(bytes.addAll);

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

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

  group('checksum', () {
    late File artifact;

    setUp(() {
      artifact = File('${directory.path}/artefacto')..writeAsStringSync('abc');
    });

    ChecksumTool script(String body) =>
        ChecksumTool(executable: '/bin/sh', arguments: ['-c', body, 'sh']);

    Matcher failsWith(ChecksumFailure kind) =>
        throwsA(isA<ChecksumException>().having((e) => e.kind, 'kind', kind));

    test('calcula el SHA-256 con la herramienta de la plataforma', () async {
      final evidence = await computeSha256(artifact);
      expect(evidence.sha256, abcDigest);
      expect(evidence.tool, Platform.isMacOS ? 'shasum -a 256' : 'sha256sum');
    });

    test('la herramienta se elige explícitamente por sistema operativo', () {
      final macos = checksumToolFor('macos');
      expect([macos.executable, ...macos.arguments], ['shasum', '-a', '256']);
      final linux = checksumToolFor('linux');
      expect([linux.executable, ...linux.arguments], ['sha256sum']);
    });

    test('un sistema sin herramienta declarada es una capacidad ausente', () {
      expect(
        () => checksumToolFor('windows'),
        failsWith(ChecksumFailure.unavailable),
      );
    });

    test(
      'una herramienta ausente es capacidad ausente, no un digest vacío',
      () {
        expect(
          computeSha256With(
            artifact,
            ChecksumTool(
              executable: '${directory.path}/no-existe',
              arguments: [],
            ),
          ),
          failsWith(ChecksumFailure.unavailable),
        );
      },
    );

    test('una salida que no es un digest es ilegible', () {
      expect(
        computeSha256With(artifact, script(r'printf "listo %s\n" "$1"')),
        failsWith(ChecksumFailure.unreadable),
      );
    });

    test('un digest corto es ilegible', () {
      expect(
        computeSha256With(
          artifact,
          script('printf "%s  %s\\n" ${'a' * 63} "\$1"'),
        ),
        failsWith(ChecksumFailure.unreadable),
      );
    });

    test('un digest de otro archivo es ilegible', () {
      expect(
        computeSha256With(
          artifact,
          script('printf "%s  %s\\n" $abcDigest /otro/archivo'),
        ),
        failsWith(ChecksumFailure.unreadable),
      );
    });

    test('más de una línea es ilegible', () {
      expect(
        computeSha256With(
          artifact,
          script(
            'printf "%s  %s\\n%s  %s\\n" $abcDigest "\$1" $abcDigest "\$1"',
          ),
        ),
        failsWith(ChecksumFailure.unreadable),
      );
    });

    test('una herramienta que termina con error falla', () {
      expect(
        computeSha256With(artifact, script('exit 3')),
        failsWith(ChecksumFailure.failed),
      );
    });

    test('el formato binario de sha256sum se acepta', () async {
      final tool = script('printf "%s *%s\\n" $abcDigest "\$1"');
      final evidence = await computeSha256With(artifact, tool);
      expect(evidence.sha256, abcDigest);
      expect(evidence.tool, tool.description);
    });
  });

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

  group('argumentos de la build oficial', () {
    Future<(int, String)> invoke(List<String> arguments) async {
      final out = _Collector();
      final err = _Collector();
      final code = await runBuildRelease(
        arguments,
        standardOut: IOSink(out),
        standardError: IOSink(err),
      );
      expect(out.bytes, isEmpty, reason: '$arguments');
      return (code, err.text);
    }

    test('sin versión falla antes de compilar', () async {
      final (code, message) = await invoke([
        '--output',
        '${directory.path}/release',
      ]);
      expect(code, 64);
      expect(message, contains('--version'));
      expect(directory.listSync(), isEmpty);
    });

    for (final version in [
      'v1.2.3',
      '1.2',
      '01.2.3',
      '1.2.3-01',
      ' 1.2.3',
      '1.2.3\n',
      '1.2.3-rc..1',
      '',
    ]) {
      test(
        '«${version.replaceAll('\n', r'\n')}» falla antes de compilar',
        () async {
          final (code, message) = await invoke([
            '--version',
            version,
            '--output',
            '${directory.path}/release',
          ]);
          expect(code, 64);
          expect(message, contains('no es SemVer 2.0'));
          expect(directory.listSync(), isEmpty);
        },
      );
    }

    test(
      'un --output sin directorio padre falla sin detalles del runtime',
      () async {
        final (code, message) = await invoke([
          '--version',
          '1.0.0',
          '--output',
          '${directory.path}/no-existe/release',
        ]);
        expect(code, 1);
        expect(
          message,
          'build_release: el directorio que contiene --output no existe o no '
          'es un directorio; no se compiló nada.\n',
        );
        expect(directory.listSync(), isEmpty);
      },
    );

    test(
      'un padre de --output sin escritura falla sin detalles del runtime',
      () async {
        final parent = await Directory(
          '${directory.path}/solo-lectura',
        ).create();
        await Process.run('chmod', ['0555', parent.path]);
        try {
          final (code, message) = await invoke([
            '--version',
            '1.0.0',
            '--output',
            '${parent.path}/release',
          ]);
          expect(code, 1);
          expect(
            message,
            'build_release: no se pudo crear el directorio de trabajo junto a '
            '--output (Permission denied); no se compiló nada.\n',
          );
          expect(parent.listSync(), isEmpty);
        } finally {
          await Process.run('chmod', ['0755', parent.path]);
        }
      },
    );

    for (final arguments in [
      <String>[],
      ['--version', '1.0.0'],
      ['--version'],
      ['--version', '1.0.0', '--output'],
      ['--version', '1.0.0', '--version', '1.0.1', '--output', 'x'],
      ['--version', '1.0.0', '--output', 'x', '--target-os', 'windows'],
      ['--version=1.0.0', '--output', 'x'],
    ]) {
      test('$arguments es uso inválido', () async {
        final (code, _) = await invoke(arguments);
        expect(code, 64);
        expect(directory.listSync(), isEmpty);
      });
    }
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
              checksumTool: const ChecksumTool(
                executable: '/bin/sh',
                arguments: [
                  '-c',
                  r'chmod 0555 "$(dirname "$(dirname "$1")")"; exit 3',
                  'sh',
                ],
              ),
            ),
            throwsA(
              isA<ReleaseBuildException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('no se pudo borrar el directorio de trabajo'),
                  contains('Permission denied'),
                  isNot(contains('#0')),
                  isNot(contains('Exception')),
                ),
              ),
            ),
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
        final result = await Process.run(Platform.resolvedExecutable, [
          'run',
          '${root.path}/tool/build_release.dart',
          '--version',
          version,
          '--output',
          output,
        ], workingDirectory: directory.path);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(result.stderr, '');

        final name = 'shipflow-$version-$hostPlatform';
        final entries = Directory(output).listSync().map((e) => e.path).toList()
          ..sort();
        expect(entries, ['$output/SHA256SUMS', '$output/$name']);
        expect(
          directory.listSync().map((e) => e.path),
          [output],
          reason: 'no queda directorio de trabajo',
        );

        final digest = (await computeSha256(File('$output/$name'))).sha256;
        expect(
          File('$output/SHA256SUMS').readAsStringSync(),
          '$digest  $name\n',
        );
        final verify = await Process.run(
          Platform.isMacOS ? 'shasum' : 'sha256sum',
          [
            if (Platform.isMacOS) ...['-a', '256'],
            '-c',
            'SHA256SUMS',
          ],
          workingDirectory: output,
        );
        expect(verify.exitCode, 0, reason: '${verify.stdout}${verify.stderr}');

        final ran = await Process.run(
          '$output/$name',
          ['--version'],
          workingDirectory: directory.path,
          environment: const {},
          includeParentEnvironment: false,
        );
        expect(ran.stdout, 'shipflow $version\n');
        expect(result.stdout, contains(digest));
        expect(result.stdout, contains('nativamente en $hostPlatform'));
      },
    );
  });
}
