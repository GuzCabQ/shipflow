import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/promotion_layout.dart';
import '../../tool/src/promotion_lock.dart';

/// Un descriptor cuyo lock, unlock y close fallan a pedido: el sistema de
/// archivos no permite provocar esos fallos de verdad.
final class _FakeLock implements RandomAccessFile {
  _FakeLock({
    this.busy = false,
    this.unlockFails = false,
    this.closeFails = false,
  });

  final bool busy;
  final bool unlockFails;
  final bool closeFails;
  final calls = <String>[];

  FileSystemException _failure(String operation) => FileSystemException(
    '$operation falló',
    '/ruta/interna/.shipflow.promote.lock',
    const OSError('Input/output error', 5),
  );

  @override
  Future<RandomAccessFile> lock([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]) async {
    calls.add('lock');
    if (busy) throw _failure('lock');
    return this;
  }

  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) async {
    calls.add('unlock');
    if (unlockFails) throw _failure('unlock');
    return this;
  }

  @override
  Future<void> close() async {
    calls.add('close');
    if (closeFails) throw _failure('close');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final layout = PromotionLayout(Directory('/bin-dir'));

  Matcher controlled(String fragment) => throwsA(
    isA<PromotionException>().having(
      (e) => e.message,
      'message',
      allOf(
        contains(fragment),
        contains('Input/output error'),
        isNot(contains('/ruta/interna')),
        isNot(contains('Exception')),
      ),
    ),
  );

  test(
    'si unlock falla igual cierra, y el éxito informa un fallo controlado',
    () async {
      final lock = _FakeLock(unlockFails: true);
      await expectLater(
        withPromotionLock(layout, () async => 7, open: (_) async => lock),
        controlled('no se pudo liberar el lock'),
      );
      expect(lock.calls, ['lock', 'unlock', 'close']);
    },
  );

  test('si close falla tras un éxito, el fallo es controlado', () async {
    final lock = _FakeLock(closeFails: true);
    await expectLater(
      withPromotionLock(layout, () async => 7, open: (_) async => lock),
      controlled('no se pudo liberar el lock'),
    );
    expect(lock.calls, ['lock', 'unlock', 'close']);
  });

  test(
    'el fallo del cuerpo se conserva aunque liberar el lock falle',
    () async {
      final lock = _FakeLock(unlockFails: true, closeFails: true);
      const primary = PromotionException('el fallo primario');
      await expectLater(
        withPromotionLock<void>(
          layout,
          () async => throw primary,
          open: (_) async => lock,
        ),
        throwsA(same(primary)),
      );
      expect(lock.calls, ['lock', 'unlock', 'close']);
    },
  );

  test('un defecto del cuerpo se propaga con su tipo y su traza', () async {
    final lock = _FakeLock(unlockFails: true);
    final defect = StateError('defecto interno');
    Object? thrown;
    StackTrace? stack;
    try {
      await withPromotionLock<void>(
        layout,
        () async => throw defect,
        open: (_) async => lock,
      );
    } on Object catch (error, trace) {
      thrown = error;
      stack = trace;
    }
    expect(thrown, same(defect));
    expect(
      stack.toString().split('\n').first,
      contains('promotion_lock_test.dart'),
    );
  });

  test('con el lock ocupado, un cierre que falla no tapa el motivo', () async {
    final lock = _FakeLock(busy: true, closeFails: true);
    await expectLater(
      withPromotionLock(layout, () async => 7, open: (_) async => lock),
      throwsA(
        isA<PromotionException>().having(
          (e) => e.message,
          'message',
          contains('otra promoción tiene el lock'),
        ),
      ),
    );
    expect(lock.calls, ['lock', 'close']);
  });

  test('sin fallos devuelve el resultado y libera en orden', () async {
    final lock = _FakeLock();
    expect(
      await withPromotionLock(layout, () async => 7, open: (_) async => lock),
      7,
    );
    expect(lock.calls, ['lock', 'unlock', 'close']);
  });
}
