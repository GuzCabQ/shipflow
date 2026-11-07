@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_service_support.dart';
import 'support/context_service_support.dart';

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  /// Prepara una regla y muere en la escritura número [writes] + 1 de la
  /// aceptación: 2 corta antes del rename y 3 justo después.
  Future<String> interrupted(int writes, {List<BasisChange>? changes}) async {
    final prepared = await box.prepare(
      box.input(changes ?? [create('rule', ruleOf())]),
    );
    box.storeWrap = (real) => CrashingStore(real, writes);
    await expectLater(
      box.accept(prepared.draftDigest!),
      throwsA(isA<SimulatedCrash>()),
    );
    box.storeWrap = null;
    expect(box.journal.existsSync(), isTrue);
    return prepared.draftDigest!;
  }

  test('nothing to recover is a no-op that writes nothing', () async {
    final before = box.snapshot();
    final result = await box.recover();
    expect(result.outcome, BasisOutcome.noChanges);
    expect(result.exitCode, 0);
    expect(box.snapshot(), before);
  });

  test(
    'a crash before the rename is finished with the same approval',
    () async {
      final digest = await interrupted(2);
      expect(box.basis.existsSync(), isFalse);
      final result = await box.recover();
      expect(result.outcome, BasisOutcome.recovered);
      expect(result.published, isTrue);
      expect(box.document.revision, 1);
      expect(box.document.events.single.draftDigest, digest);
      expect(box.journal.existsSync(), isFalse);
      expect(box.draft.existsSync(), isFalse);
    },
  );

  test('a crash after the rename only completes the cleanup', () async {
    await interrupted(3);
    final bytes = box.basis.readAsBytesSync();
    final result = await box.recover();
    expect(result.outcome, BasisOutcome.recovered);
    expect(result.exitCode, 0);
    expect(box.basis.readAsBytesSync(), bytes);
    expect(box.document.revision, 1);
    expect(box.journal.existsSync(), isFalse);
  });

  test('changed preconditions keep everything and offer discard', () async {
    box.box.file('docs/politica.md', 'v1\n');
    final digest = await interrupted(
      2,
      changes: ruleWithSource('docs/politica.md'),
    );
    box.box.file('docs/politica.md', 'v2\n');
    final before = box.snapshot();
    final result = await box.recover();
    expect(result.exitCode, 75);
    expect(codesOf(result), contains('recovery_preconditions_changed'));
    expect(box.snapshot(), before);
    final args = [for (final a in result.nextActions) a.arguments.join(' ')];
    expect(args, contains('--discard $digest'));
  });

  test('discard_aborts_only_matching_before', () async {
    final digest = await interrupted(2);
    final wrong = await box.discard('sha256:${'0' * 64}');
    expect(wrong.exitCode, 75);
    expect(box.journal.existsSync(), isTrue);
    final result = await box.discard(digest);
    expect(result.outcome, BasisOutcome.abortedBeforePublication);
    expect(result.exitCode, 0);
    expect(box.journal.existsSync(), isFalse);
    expect(box.draft.existsSync(), isFalse);
    expect(box.basis.existsSync(), isFalse);
    expect(
      Directory(box.path('shipflow/local/basis-staging')).listSync(),
      isEmpty,
    );
  });

  test('a publication that already happened cannot be discarded', () async {
    final digest = await interrupted(3);
    final result = await box.discard(digest);
    expect(result.exitCode, 75);
    expect(codesOf(result), contains('recovery_required'));
    expect(box.journal.existsSync(), isTrue);
  });

  test('corrupt_journal_is_not_noop', () async {
    box.journal.writeAsStringSync('{roto');
    final result = await box.recover();
    expect(result.exitCode, 65);
    expect(result.storageIntegrity.transaction, BasisIntegrity.invalid);
    expect(box.journal.readAsStringSync(), '{roto');
  });

  test('a basis that is neither before nor after is a conflict', () async {
    await interrupted(2);
    box.basis.writeAsStringSync('{"ajeno": true}\n');
    final result = await box.recover();
    expect(result.exitCode, 75);
    expect(codesOf(result), contains('recovery_required'));
    expect(box.basis.readAsStringSync(), '{"ajeno": true}\n');
    expect(box.journal.existsSync(), isTrue);
  });

  test('rename_succeeded_readback_failed_is_published', () async {
    final prepared = await box.prepare(box.input([create('rule', ruleOf())]));
    box.storeWrap = (real) => _ReplacedThenFails(real);
    final result = await box.accept(prepared.draftDigest!);
    box.storeWrap = null;
    expect(result.published, isTrue);
    expect(result.exitCode, 74);
    expect(codesOf(result), contains('recovery_required'));
    final recovered = await box.recover();
    expect(recovered.outcome, BasisOutcome.recovered);
    expect(box.document.revision, 1);
    expect(box.journal.existsSync(), isFalse);
  });

  test('an own complete candidate without journal is removed', () async {
    final prepared = await box.prepare(box.input([create('rule', ruleOf())]));
    box.storeWrap = (real) => CrashingStore(real, 1);
    await expectLater(
      box.accept(prepared.draftDigest!),
      throwsA(isA<SimulatedCrash>()),
    );
    box.storeWrap = null;
    expect(box.journal.existsSync(), isFalse);
    final staging = Directory(box.path('shipflow/local/basis-staging'));
    expect(staging.listSync(recursive: true).whereType<File>(), hasLength(1));
    final result = await box.recover();
    expect(result.outcome, BasisOutcome.recovered);
    expect(result.exitCode, 0);
    expect(staging.listSync(recursive: true).whereType<File>(), isEmpty);
    expect(box.draft.existsSync(), isTrue);
    expect((await box.box.run(ContextOperation.doctor)).exitCode, 0);
  });

  test('a temporary without journal is never a no-op', () async {
    final stray = File(
      box.path('shipflow/local/.basis-transaction.json.0123456789abcdef.tmp'),
    )..writeAsStringSync('{');
    final result = await box.recover();
    expect(result.exitCode, 75);
    expect(codesOf(result), contains('recovery_required'));
    expect(stray.existsSync(), isTrue);
  });

  test('a pending basis publication blocks preparing another', () async {
    await interrupted(2);
    final result = await box.prepare(box.input([create('b', ruleOf())]));
    expect(result.exitCode, 75);
    expect(codesOf(result), contains('recovery_required'));
  });
}

/// Reemplaza basis.json y falla la confirmación posterior, como un fsync
/// del directorio con EIO; después ya no deja leer el documento.
final class _ReplacedThenFails extends CrashingStore {
  _ReplacedThenFails(ContextStore real) : super(real, 1 << 30);

  var _replaced = false;

  @override
  Future<void> publishRelative(
    String path,
    List<int> bytes, {
    required String? expectedSha256,
  }) async {
    await real.publishRelative(path, bytes, expectedSha256: expectedSha256);
    if (path == 'shipflow/basis.json') {
      _replaced = true;
      throw const ContextStoreFailure('io', replaced: true);
    }
  }

  @override
  Future<List<int>?> readRelative(String path, {required int maxBytes}) {
    if (_replaced && path == 'shipflow/basis.json') {
      throw const ContextStoreFailure('io');
    }
    return real.readRelative(path, maxBytes: maxBytes);
  }
}
