@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/promotion.dart';
import 'promotion_support.dart';

void main() {
  final box = PromotionSandbox()..register();

  group('enlaces simbólicos', () {
    test('un artefacto enlace se rechaza sin seguirlo', () async {
      final target = await box.executable('2.0.0');
      final link = Link('${box.artifacts.path}/enlace')
        ..createSync(target.path);
      await expectLater(
        promote(
          PromotionRequest(
            artifact: File(link.path),
            expectedSha256: await sha(target),
            expectedVersion: '2.0.0',
            binDirectory: box.binDir,
          ),
        ),
        rejected('enlace'),
      );
      expect(box.binDir.listSync(), isEmpty);
    });

    test('un bin-dir enlace se rechaza', () async {
      final link = Link('${box.sandbox.path}/bin-enlace')
        ..createSync(box.binDir.path);
      final artifact = await box.executable('2.0.0');
      await expectLater(
        promote(
          PromotionRequest(
            artifact: artifact,
            expectedSha256: await sha(artifact),
            expectedVersion: '2.0.0',
            binDirectory: Directory(link.path),
          ),
        ),
        rejected('enlace'),
      );
      expect(box.binDir.listSync(), isEmpty);
    });

    for (final name in [
      installedName,
      lockName,
      candidateName,
      manifestName,
      '$manifestName.tmp',
    ]) {
      test('un $name enlace se rechaza sin seguirlo', () async {
        final target = File('${box.sandbox.path}/objetivo')
          ..writeAsStringSync('no tocar');
        Link('${box.binDir.path}/$name').createSync(target.path);
        final before = await state(box.binDir);
        await expectLater(
          promote(await box.request(await box.executable('2.0.0'), '2.0.0')),
          rejected('enlace'),
        );
        expect(await state(box.binDir), before);
        expect(target.readAsStringSync(), 'no tocar');
      });
    }
  });
}
