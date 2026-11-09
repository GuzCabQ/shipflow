@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';
import 'support/store_spy_support.dart';

/// Ante un fallo, la administración abierta se cierra igual y quien llama
/// ve el fallo original con su traza; si sólo falla el cierre, ése es el
/// fallo que ve.
void main() {
  late ServiceSandbox box;
  late AdminSpies spies;
  setUp(() {
    box = ServiceSandbox.create()
      ..project()
      ..gitInit();
    spies = AdminSpies();
  });
  tearDown(() async {
    await spies.dispose();
    box.dispose();
  });

  InjectedFailure failure(String what) =>
      (StateError(what), StackTrace.current);

  /// Lo que lanza un init local con [opener], o null si no lanza.
  Future<(Object, StackTrace)?> initLocal(
    Future<ContextStore> Function(Directory) opener,
  ) async {
    try {
      await box.run(
        ContextOperation.init,
        sharing: SharingChoice.local,
        git: box.realGit,
        openAdministration: opener,
      );
      return null;
    } on Object catch (error, trace) {
      return (error, trace);
    }
  }

  void expectSame((Object, StackTrace)? thrown, InjectedFailure original) {
    expect(thrown, isNotNull);
    expect(thrown!.$1, same(original.$1));
    expect(thrown.$2.toString(), original.$2.toString());
  }

  test('a failure before handing it over closes it, error intact', () async {
    final read = failure('lectura');
    expectSame(await initLocal(spies.opener(failRead: read)), read);
    expect(spies.opened.single.closes, 1);
    expect(File(box.path('shipflow/project.json')).existsSync(), isFalse);
  });

  test('a failure under the lease closes it after, error intact', () async {
    final publish = failure('exclude');
    bool? free;
    final thrown = await initLocal(
      spies.opener(
        failPublish: publish,
        onClose: () async =>
            free = await publicationFree(box.root, Directory(box.path('.git'))),
      ),
    );
    expectSame(thrown, publish);
    expect(spies.opened.single.closes, 1);
    expect(free, isTrue);
    expect(
      File(box.path('shipflow/local/transaction.json')).existsSync(),
      isTrue,
    );
  });

  test('a store failure under the lease keeps its diagnostics', () async {
    final result = await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
      openAdministration: spies.opener(
        failPublish: (const ContextStoreFailure('io'), StackTrace.current),
      ),
    );
    expect(
      [for (final d in result.diagnostics) d.code],
      ['io_failure', 'recovery_pending'],
    );
    expect(spies.opened.single.closes, 1);
  });

  test('if opening fails there is nothing to close', () async {
    final open = failure('apertura');
    StoreSpy? root;
    Object? thrown;
    try {
      await box.run(
        ContextOperation.init,
        sharing: SharingChoice.local,
        git: box.realGit,
        wrap: (real) => root = StoreSpy(real),
        openAdministration: (_) => Future.error(open.$1, open.$2),
      );
    } on Object catch (error) {
      thrown = error;
    }
    expect(thrown, same(open.$1));
    expect(root!.closes, 0);
  });

  test('a failing close never replaces the original error', () async {
    final read = failure('lectura');
    final publish = failure('exclude');
    final close = failure('cierre');
    expectSame(
      await initLocal(spies.opener(failRead: read, failClose: close)),
      read,
    );
    expectSame(
      await initLocal(spies.opener(failPublish: publish, failClose: close)),
      publish,
    );
    expect([for (final s in spies.opened) s.closes], [1, 1]);
  });

  test('a close that fails alone is reported, not retried', () async {
    final close = failure('cierre');
    expectSame(await initLocal(spies.opener(failClose: close)), close);
    expect(spies.opened.single.closes, 1);
    expect(File(box.path('shipflow/project.json')).existsSync(), isTrue);
  });
}
