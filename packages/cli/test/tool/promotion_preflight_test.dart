@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/promotion.dart';
import 'promotion_support.dart';

void main() {
  final box = PromotionSandbox()..register();

  group('verificación previa: el destino no se toca', () {
    late File installed;
    late Map<String, String> before;

    setUp(() async {
      installed = await box.install(await box.executable('1.0.0'));
      before = await state(box.binDir);
    });

    test('un digest que no coincide se rechaza', () async {
      final artifact = await box.executable('2.0.0');
      await expectLater(
        promote(await box.request(artifact, '2.0.0', sha256: '0' * 64)),
        rejected('SHA-256'),
      );
      expect(await state(box.binDir), before);
    });

    test('un candidato que informa otra versión se rechaza', () async {
      await expectLater(
        promote(await box.request(await box.executable('2.0.1'), '2.0.0')),
        rejected('2.0.0'),
      );
      expect(await state(box.binDir), before);
    });

    test('un candidato que no responde se rechaza', () async {
      final mute = File('${box.artifacts.path}/mudo')
        ..writeAsStringSync('#!/bin/sh\nexit 1\n');
      await chmod('0755', mute.path);
      await expectLater(
        promote(await box.request(mute, '2.0.0')),
        rejected('2.0.0'),
      );
      expect(await state(box.binDir), before);
    });

    test('la misma versión con bytes distintos se rechaza', () async {
      await expectLater(
        promote(
          await box.request(
            await box.executable('1.0.0', salt: 'otro'),
            '1.0.0',
          ),
        ),
        rejected('misma versión'),
      );
      expect((await state(box.binDir))..remove(lockName), before);
      expect(await answer(installed.path), 'shipflow 1.0.0\n');
    });

    test('una versión esperada que no es SemVer se rechaza', () async {
      await expectLater(
        promote(await box.request(await box.executable('v2.0.0'), 'v2.0.0')),
        rejected('SemVer'),
      );
      expect(await state(box.binDir), before);
    });

    test('un digest esperado mal formado se rechaza', () async {
      await expectLater(
        promote(
          await box.request(
            await box.executable('2.0.0'),
            '2.0.0',
            sha256: 'ab',
          ),
        ),
        rejected('SHA-256'),
      );
      expect(await state(box.binDir), before);
    });

    test('un artefacto inexistente se rechaza', () async {
      await expectLater(
        promote(
          PromotionRequest(
            artifact: File('${box.artifacts.path}/no-existe'),
            expectedSha256: '0' * 64,
            expectedVersion: '2.0.0',
            binDirectory: box.binDir,
          ),
        ),
        rejected('no-existe'),
      );
      expect(await state(box.binDir), before);
    });

    test('un bin-dir inexistente no se crea', () async {
      final missing = Directory('${box.sandbox.path}/no-existe');
      final artifact = await box.executable('2.0.0');
      await expectLater(
        promote(
          PromotionRequest(
            artifact: artifact,
            expectedSha256: await sha(artifact),
            expectedVersion: '2.0.0',
            binDirectory: missing,
          ),
        ),
        rejected('no-existe'),
      );
      expect(missing.existsSync(), isFalse);
    });

    test('un bin-dir sin escritura deja la instalación intacta', () async {
      await chmod('0555', box.binDir.path);
      await expectLater(
        promote(await box.request(await box.executable('2.0.0'), '2.0.0')),
        throwsA(isA<PromotionException>()),
      );
      expect(await state(box.binDir), before);
    });

    test('con el lock ya creado y sin escritura tampoco cambia', () async {
      File('${box.binDir.path}/$lockName').createSync();
      before = await state(box.binDir);
      await chmod('0555', box.binDir.path);
      await expectLater(
        promote(await box.request(await box.executable('2.0.0'), '2.0.0')),
        throwsA(isA<PromotionException>()),
      );
      expect(await state(box.binDir), before);
    });
  });
}
