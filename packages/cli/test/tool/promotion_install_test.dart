@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/build_release.dart';
import '../../tool/src/promotion.dart';
import 'promotion_support.dart';

void main() {
  final box = PromotionSandbox()..register();

  group('promoción', () {
    test('primera instalación', () async {
      final artifact = await box.executable('1.0.0');
      await promote(await box.request(artifact, '1.0.0'));
      await box.expectClean('1.0.0');
    });

    test('actualización conserva sólo el instalado y el lock vacío', () async {
      await box.install(await box.executable('1.0.0'));
      await promote(await box.request(await box.executable('1.1.0'), '1.1.0'));
      await box.expectClean('1.1.0');
    });

    test('promover lo mismo que ya está instalado no cambia nada', () async {
      final artifact = await box.executable('1.0.0');
      await box.install(artifact);
      final installed = await sha(File('${box.binDir.path}/$installedName'));
      await promote(await box.request(artifact, '1.0.0'));
      expect(await sha(File('${box.binDir.path}/$installedName')), installed);
      await box.expectClean('1.0.0');
    });

    test('promueve un shipflow compilado de verdad', () async {
      final release = await buildRelease(
        version: '0.0.0-dev.7+gpromocion',
        output: Directory('${box.sandbox.path}/release'),
      );
      await promote(
        PromotionRequest(
          artifact: release.artifact,
          expectedSha256: release.evidence.sha256,
          expectedVersion: '0.0.0-dev.7+gpromocion',
          binDirectory: box.binDir,
        ),
      );
      await box.expectClean('0.0.0-dev.7+gpromocion');
    });
  });
}
