@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cli/src/context/secure_context_store.dart';
import 'package:test/test.dart';

import 'init_process_support.dart';
import 'support/context_store_support.dart';

/// Otro proceso Shipflow que toma [resource] en [root] y lo retiene.
Future<Process> owner(Directory root, String resource) async {
  final script = '${(await cliRoot()).path}/test/support/context_process.dart';
  final process = await Process.start(Platform.resolvedExecutable, [
    '--packages=${(await Isolate.packageConfig)!.toFilePath()}',
    script,
    root.path,
    resource,
  ]);
  final line = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 60));
  expect(line, 'held');
  return process;
}

Future<void> kill(Process process) async {
  process.kill(ProcessSignal.sigkill);
  await process.exitCode;
}

void main() {
  late StoreSandbox box;
  setUp(() async {
    box = await StoreSandbox.create();
    box.directory('shipflow/local/locks');
  });
  tearDown(() => box.dispose());

  test('a live owner is busy and its death frees the lease', () async {
    final process = await owner(box.root, 'context');
    final store = await box.open();
    await expectLater(
      store.acquirePublication([store.contextLock()]),
      throwsA(storeFailure('busy')),
    );
    await kill(process);
    final lease = await store.acquirePublication([store.contextLock()]);
    await lease.release();
    // El lock nunca se borra para apropiárselo.
    expect(box.entriesOf('shipflow/local/locks'), ['context.lock']);
  });

  test(
    'the administrative directory is locked by its anchored descriptor',
    () async {
      final info = Directory('${box.root.path}/info')..createSync();
      final process = await owner(info, 'directory');
      final admin = await SecureContextStore.open(info);
      addTearDown(admin.close);
      await expectLater(
        admin.acquirePublication([admin.directoryLock()]),
        throwsA(storeFailure('busy')),
      );
      await kill(process);
      final lease = await admin.acquirePublication([admin.directoryLock()]);
      await lease.release();
      expect(info.listSync(), isEmpty);
    },
  );

  test('a busy resource leaves no partial lease behind', () async {
    final info = Directory('${box.root.path}/info')..createSync();
    final process = await owner(info, 'directory');
    addTearDown(() => kill(process));
    final store = await box.open();
    final admin = await SecureContextStore.open(info);
    addTearDown(admin.close);
    for (final order in [
      [store.contextLock(), admin.directoryLock()],
      [admin.directoryLock(), store.contextLock()],
    ]) {
      await expectLater(
        store.acquirePublication(order),
        throwsA(storeFailure('busy')),
      );
      // El recurso libre no quedó tomado por el intento fallido.
      final free = await box.open();
      final lease = await free.acquirePublication([free.contextLock()]);
      await lease.release();
    }
  });
}
