@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/executable_checks.dart';
import '../../tool/src/promotion.dart';
import 'promotion_support.dart';

void main() {
  final box = PromotionSandbox()..register();

  group('verificación posterior al reemplazo', () {
    test('si falla, restaura el anterior y éste vuelve a responder', () async {
      final old = await box.install(await box.executable('1.0.0'));
      final oldBytes = old.readAsBytesSync();
      await expectLater(
        promote(
          await box.request(
            await box.executable('2.0.0', failsWhenInstalled: true),
            '2.0.0',
          ),
        ),
        rejected('restaur'),
      );
      expect(
        File('${box.binDir.path}/$installedName').readAsBytesSync(),
        oldBytes,
      );
      await box.expectClean('1.0.0');
    });

    test(
      'un fallo de archivo a mitad del reemplazo restaura sin detalles crudos',
      () async {
        await box.install(await box.executable('1.0.0'));
        Directory('${box.binDir.path}/$candidateName').createSync();
        await expectLater(
          promote(await box.request(await box.executable('2.0.0'), '2.0.0')),
          throwsA(
            isA<PromotionException>().having(
              (e) => e.message,
              'message',
              allOf(contains('Se restauró'), isNot(contains('Exception'))),
            ),
          ),
        );
        expect(
          await answer('${box.binDir.path}/$installedName'),
          'shipflow 1.0.0\n',
        );
        expect(File('${box.binDir.path}/$manifestName').existsSync(), isFalse);
      },
    );

    test(
      'un defecto interno restaura y se propaga con su tipo y su traza',
      () async {
        await box.install(await box.executable('1.0.0'));
        final defect = StateError('defecto interno');
        var installedReads = 0;
        Future<String?> readVersion(File file) async {
          if (file.path.endsWith('/$installedName') && ++installedReads == 2) {
            throw defect;
          }
          return reportedVersion(file);
        }

        Object? thrown;
        StackTrace? stack;
        try {
          await promote(
            await box.request(await box.executable('2.0.0'), '2.0.0'),
            readVersion: readVersion,
          );
        } on Object catch (error, trace) {
          thrown = error;
          stack = trace;
        }
        expect(thrown, same(defect));
        expect(
          stack.toString().split('\n').first,
          contains('promotion_rollback_test.dart'),
        );
        await box.expectClean('1.0.0');
      },
    );

    test('si además la restauración falla, sale el defecto original', () async {
      await box.install(await box.executable('1.0.0'));
      final defect = StateError('defecto interno');
      var installedReads = 0;
      Future<String?> readVersion(File file) async {
        if (!file.path.endsWith('/$installedName')) {
          return reportedVersion(file);
        }
        installedReads++;
        if (installedReads == 2) throw defect;
        if (installedReads == 3) return 'otra';
        return reportedVersion(file);
      }

      await expectLater(
        promote(
          await box.request(await box.executable('2.0.0'), '2.0.0'),
          readVersion: readVersion,
        ),
        throwsA(same(defect)),
      );
    });

    test(
      'un candidato que se cuelga al instalarse se mata y se restaura',
      () async {
        await box.install(await box.executable('1.0.0'));
        await expectLater(
          promote(
            await box.request(
              await box.executable('2.0.0', hangsWhenInstalled: true),
              '2.0.0',
            ),
            readVersion: (file) =>
                reportedVersion(file, timeout: const Duration(seconds: 1)),
          ),
          rejected('Se restauró'),
        );
        await box.expectClean('1.0.0');
      },
    );

    test('en una primera instalación no deja un ejecutable roto', () async {
      await expectLater(
        promote(
          await box.request(
            await box.executable('2.0.0', failsWhenInstalled: true),
            '2.0.0',
          ),
        ),
        throwsA(isA<PromotionException>()),
      );
      expect(box.binDir.listSync().map((e) => e.path.split('/').last), [
        lockName,
      ]);
    });
  });
}
