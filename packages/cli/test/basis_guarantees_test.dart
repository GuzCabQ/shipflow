@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/basis/basis_canonical.dart';
import 'package:cli/src/basis/basis_human.dart';
import 'package:cli/src/basis/basis_sources.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_service_support.dart';
import 'support/basis_store_wrappers.dart';
import 'support/context_service_support.dart';

const _otherProject = 'cccccccc-0000-4000-8000-000000000001';

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  /// Reescribe [file] con otro projectId y su sello recalculado: formalmente
  /// válido, de otra copia.
  void foreign(File file) {
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    data['projectId'] = _otherProject;
    data['digest'] = sealedDigest(data, 'digest');
    file.writeAsStringSync(jsonEncode(data));
  }

  group('accepting and discarding keep what they cannot prove', () {
    test('accept rechecks the exact draft after taking the lock', () async {
      final prepared = await box.prepare(box.input([create('a', ruleOf())]));
      box.storeWrap = (real) => BeforeLock(real, () async {
        box.storeWrap = null;
        final discarded = await box.discard(prepared.draftDigest!);
        expect(discarded.exitCode, 0);
      });
      final result = await box.accept(prepared.draftDigest!);
      expect(result.published, isFalse);
      expect(box.basis.existsSync(), isFalse);
    });

    test(
      'a draft revised meanwhile is not accepted under its old digest',
      () async {
        final prepared = await box.prepare(box.input([create('a', ruleOf())]));
        box.storeWrap = (real) => BeforeLock(real, () async {
          box.storeWrap = null;
          final revised = await box.using(
            (s) => s.revise(
              box.input([create('a', ruleOf()), create('b', pendingOf())]),
              expectedDraftDigest: prepared.draftDigest!,
            ),
          );
          expect(revised.outcome, BasisOutcome.draftPrepared);
        });
        final result = await box.accept(prepared.draftDigest!);
        expect(result.published, isFalse);
        expect(codesOf(result), contains('draft_conflict'));
        expect(box.draft.existsSync(), isTrue);
      },
    );

    test('two accepts of one draft publish one revision', () async {
      final prepared = await box.prepare(box.input([create('a', ruleOf())]));
      late BasisResponse first;
      box.storeWrap = (real) => BeforeLock(real, () async {
        box.storeWrap = null;
        first = await box.accept(prepared.draftDigest!);
      });
      final second = await box.accept(prepared.draftDigest!);
      expect(first.published, isTrue);
      expect(second.outcome, BasisOutcome.alreadyApplied);
      expect(box.document.revision, 1);
    });

    test(
      'discard never reads an unreadable basis as the state before',
      () async {
        final p = await box.prepare(box.input([create('a', ruleOf())]));
        box.storeWrap = (real) => CrashingStore(real, 3);
        await expectLater(
          box.accept(p.draftDigest!),
          throwsA(isA<SimulatedCrash>()),
        );
        box.storeWrap = (real) => UnreadableBasis(real);
        final result = await box.discard(p.draftDigest!);
        expect(result.outcome, isNot(BasisOutcome.abortedBeforePublication));
        expect(result.exitCode, isNot(0));
        expect(box.journal.existsSync(), isTrue);
      },
    );

    test('discard keeps a journal of another project', () async {
      final digest = await interruptBasis(box, [create('a', ruleOf())]);
      foreign(box.journal);
      final result = await box.discard(digest);
      expect(result.exitCode, isNot(0));
      expect(box.journal.existsSync(), isTrue);
    });
  });

  group('discarding a publication keeps what is not its own', () {
    late String digest;
    setUp(() async {
      digest = await interruptBasis(box, [create('a', ruleOf())]);
    });

    test('alongside a pending init transaction', () async {
      box.box.file('pubspec.yaml', 'name: app\n# cambio\n');
      await expectLater(
        box.box.run(
          ContextOperation.refresh,
          wrap: (real) => CrashingStore(real, 1),
        ),
        throwsA(isA<SimulatedCrash>()),
      );
      final result = await box.discard(digest);
      expect(result.exitCode, 75);
      expect(box.journal.existsSync(), isTrue);
    });

    test('with a candidate that is not the accepted one', () async {
      final candidate = Directory(
        box.path('shipflow/local/basis-staging'),
      ).listSync(recursive: true).whereType<File>().single;
      candidate.writeAsStringSync('{"otro": true}\n');
      final result = await box.discard(digest);
      expect(result.exitCode, 75);
      expect(box.journal.existsSync(), isTrue);
      expect(candidate.readAsStringSync(), '{"otro": true}\n');
    });
  });

  group('queries are bound to this project', () {
    test('a valid basis of another project is not shown', () async {
      await box.publish(box.input([create('a', ruleOf())]));
      foreign(box.basis);
      final result = await box.show();
      expect(result.exitCode, isNot(0));
      expect(result.selected, isEmpty);
      expect(result.storageIntegrity.basis, BasisIntegrity.invalid);
    });

    test('doctor does not pass a basis of another project', () async {
      await box.publish(box.input([create('a', ruleOf())]));
      foreign(box.basis);
      final result = await box.box.run(ContextOperation.doctor);
      final check = result.checks.singleWhere(
        (c) => c.id == ContextCheckId.basisIntegrity,
      );
      expect(check.status, ContextCheckStatus.failed);
    });

    test('without context nothing is shown as applicable', () async {
      await box.publish(box.input([create('a', ruleOf())]));
      File(box.path('shipflow/project.json')).deleteSync();
      final result = await box.show();
      expect(result.exitCode, isNot(0));
      expect(result.selected, isEmpty);
    });
  });

  test('recover without proof of no leftovers is not a no-op', () async {
    box.box.file(
      'shipflow/local/.basis-transaction.json.0123456789abcdef.tmp',
      'partial',
    );
    box.box.file('shipflow/unowned.txt', 'unowned');
    final result = await box.recover();
    expect(result.exitCode, isNot(0));
    expect(result.outcome, isNot(BasisOutcome.noChanges));
  });

  test('recover whose inspection is cut short is not a no-op', () async {
    final local = Directory(box.path('shipflow/local/basis-staging'))
      ..createSync(recursive: true);
    Process.runSync('chmod', ['000', local.path]);
    try {
      final result = await box.recover();
      expect(result.exitCode, isNot(0));
      expect(result.outcome, isNot(BasisOutcome.noChanges));
    } finally {
      Process.runSync('chmod', ['755', local.path]);
    }
  });

  group('budgets and protected paths', () {
    List<BasisRecordVersion> sixSources() => [
      for (var i = 0; i < 6; i++)
        BasisRecordVersion(
          id: 'r$i',
          version: 1,
          previousVersion: null,
          payload: localSource('docs/s$i.md'),
        ),
    ];

    test('an exhausted source budget is never a success', () async {
      for (var i = 0; i < 65; i++) {
        box.box.file('docs/s$i.md', 'policy $i');
      }
      await box.publish(
        box.input([
          for (var i = 0; i < 64; i++)
            create('s$i', localSource('docs/s$i.md')),
        ]),
      );
      await box.publish(
        box.input([create('last', localSource('docs/s64.md'))]),
      );
      final result = await box.show();
      expect(result.selection.complete, isFalse);
      expect(result.exitCode, 65);
      expect(codesOf(result), contains('budget_exceeded'));
    });

    test('the total source byte budget stops further reads', () async {
      final limits = BasisLimits.fromJson({
        ...box.limits.toJson(),
        'maxSourceBytes': 10,
        'maxTotalSourceBytes': 10,
      });
      for (var i = 0; i < 6; i++) {
        box.box.file('docs/s$i.md', '1234567890');
      }
      final real = await SecureContextStore.open(box.box.root);
      final counter = CountingReads(real);
      try {
        final report = await BasisSourceReader(
          counter,
        ).readSources(sixSources(), limits, observe: true);
        expect(report.complete, isFalse);
        expect(counter.contentBytes, lessThanOrEqualTo(11));
      } finally {
        await real.close();
      }
    });

    test('protected local state is excluded whatever its case', () async {
      box.box.file('shipflow/local/nota.md', 'marca local');
      if (!File(box.path('SHIPFLOW/LOCAL/nota.md')).existsSync()) {
        markTestSkipped('requiere un sistema de archivos sin mayúsculas');
        return;
      }
      final result = await box.prepare(
        box.input([create('p', localSource('SHIPFLOW/LOCAL/nota.md'))]),
      );
      expect(result.sourceStatus.single.status, BasisSourceState.excluded);
    });
  });

  test('a draft names the rule it retires', () async {
    await box.publish(box.input([create('a', ruleOf())]));
    final current = currentOf(box, 'rule');
    final result = await box.prepare(
      box.input([
        revise(current.id, 1, ruleOf(lifecycle: BasisRuleLifecycle.retired)),
      ]),
    );
    expect(renderBasisHuman(result), contains('«Contratos»'));
  });
}
