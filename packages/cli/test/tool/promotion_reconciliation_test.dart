@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/promotion.dart';
import 'promotion_support.dart';

void main() {
  final box = PromotionSandbox()..register();

  group('reconciliación de una promoción interrumpida', () {
    late File old;
    late File fresh;
    late String oldSha;
    late String freshSha;

    setUp(() async {
      old = await box.executable('1.0.0');
      fresh = await box.executable('2.0.0');
      oldSha = await sha(old);
      freshSha = await sha(fresh);
      File('${box.binDir.path}/$lockName').createSync();
    });

    Map<String, Object> manifest(String phase, {bool firstInstall = false}) => {
      'phase': phase,
      'candidateVersion': '2.0.0',
      'candidateSha256': freshSha,
      if (!firstInstall) ...{
        'previousVersion': '1.0.0',
        'previousSha256': oldSha,
      },
    };

    Future<void> place(File source, String name) async {
      final placed = await source.copy('${box.binDir.path}/$name');
      await chmod('0755', placed.path);
    }

    test('interrumpida al preparar el candidato', () async {
      await place(old, installedName);
      File('${box.binDir.path}/$candidateName').writeAsStringSync('a medias');
      box.writeManifest(manifest('staging'));
      await promote(await box.request(old, '1.0.0'));
      await box.expectClean('1.0.0');
    });

    test('interrumpida antes de respaldar el instalado', () async {
      await place(old, installedName);
      await place(fresh, candidateName);
      box.writeManifest(manifest('swapping'));
      await promote(await box.request(old, '1.0.0'));
      await box.expectClean('1.0.0');
    });

    test('interrumpida entre el respaldo y el reemplazo', () async {
      await place(old, previousName);
      await place(fresh, candidateName);
      box.writeManifest(manifest('swapping'));
      await promote(await box.request(old, '1.0.0'));
      await box.expectClean('1.0.0');
    });

    test('interrumpida después del reemplazo y antes de verificar', () async {
      await place(old, previousName);
      await place(fresh, installedName);
      box.writeManifest(manifest('swapping'));
      await promote(await box.request(old, '1.0.0'));
      await box.expectClean('1.0.0');
    });

    test('interrumpida al limpiar una promoción ya verificada', () async {
      await place(old, previousName);
      await place(fresh, installedName);
      box.writeManifest(manifest('committing'));
      await promote(await box.request(fresh, '2.0.0'));
      await box.expectClean('2.0.0');
    });

    test(
      'un manifiesto temporal a medias se descarta al reconciliar',
      () async {
        await place(old, previousName);
        await place(fresh, installedName);
        box.writeManifest(manifest('swapping'));
        File(
          '${box.binDir.path}/$manifestName.tmp',
        ).writeAsStringSync('{"schem');
        await promote(await box.request(old, '1.0.0'));
        await box.expectClean('1.0.0');
      },
    );

    test(
      'reconciliar sin permiso de escritura falla sin cambiar nada',
      () async {
        await place(old, installedName);
        await place(fresh, candidateName);
        box.writeManifest(manifest('staging'));
        final before = await state(box.binDir);
        await chmod('0555', box.binDir.path);
        await expectLater(
          promote(await box.request(await box.executable('3.0.0'), '3.0.0')),
          rejected('Permission denied'),
        );
        expect(await state(box.binDir), before);
      },
    );

    test('una primera instalación interrumpida no queda instalada', () async {
      await place(fresh, installedName);
      box.writeManifest(manifest('swapping', firstInstall: true));
      final third = await box.executable('3.0.0');
      await promote(await box.request(third, '3.0.0'));
      await box.expectClean('3.0.0');
    });

    test('la reconciliación ocurre antes de promover otro artefacto', () async {
      await place(old, previousName);
      await place(fresh, installedName);
      box.writeManifest(manifest('swapping'));
      await expectLater(
        promote(
          await box.request(await box.executable('1.0.0', salt: 'x'), '1.0.0'),
        ),
        rejected('misma versión'),
      );
      expect(
        await answer('${box.binDir.path}/$installedName'),
        'shipflow 1.0.0\n',
      );
      expect(File('${box.binDir.path}/$manifestName').existsSync(), isFalse);
    });

    for (final (name, setup) in <(String, Future<void> Function())>[
      (
        'residuos sin manifiesto',
        () async {
          await place(old, installedName);
          await place(fresh, candidateName);
        },
      ),
      (
        'un manifiesto ilegible',
        () async {
          await place(old, installedName);
          File(
            '${box.binDir.path}/$manifestName',
          ).writeAsStringSync('{a medias');
        },
      ),
      (
        'un manifiesto con una versión previa que no es texto',
        () async {
          await place(old, installedName);
          box.writeManifest({...manifest('staging'), 'previousVersion': 1});
        },
      ),
      (
        'un respaldo que no es el del manifiesto',
        () async {
          await place(fresh, previousName);
          await place(fresh, installedName);
          box.writeManifest(manifest('swapping'));
        },
      ),
    ]) {
      test('$name no se sobrescribe a ciegas', () async {
        await setup();
        final before = await state(box.binDir);
        await expectLater(
          promote(await box.request(await box.executable('3.0.0'), '3.0.0')),
          throwsA(isA<PromotionException>()),
        );
        expect(await state(box.binDir), before);
      });
    }
  });
}
