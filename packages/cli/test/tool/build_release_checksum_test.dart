@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/checksum.dart';

const abcDigest =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

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
}
