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

  test('prepare_does_not_activate', () async {
    final result = await box.prepare(box.input([create('rule', ruleOf())]));
    expect(result.outcome, BasisOutcome.draftPrepared);
    expect(result.exitCode, 65);
    expect(codesOf(result), contains('draft_prepared'));
    expect(result.published, isFalse);
    expect(result.changedFiles, ['shipflow/local/basis-draft.json']);
    expect(box.draft.existsSync(), isTrue);
    expect(box.basis.existsSync(), isFalse);
    final args = [for (final a in result.nextActions) a.arguments.join(' ')];
    expect(args, contains('--accept ${result.draftDigest}'));
    expect(args, contains('--discard ${result.draftDigest}'));
    final shown = await box.show();
    expect(codesOf(shown), contains('basis_absent'));
    expect(shown.selected, isEmpty);
  });

  test('accept_exact_digest_once', () async {
    final prepared = await box.prepare(box.input([create('rule', ruleOf())]));
    final other = 'sha256:${'0' * 64}';
    final wrong = await box.accept(other);
    expect(wrong.exitCode, 75);
    expect(codesOf(wrong), contains('draft_conflict'));
    expect(box.basis.existsSync(), isFalse);
    final accepted = await box.accept(prepared.draftDigest!);
    expect(accepted.outcome, BasisOutcome.published);
    expect(accepted.exitCode, 0);
    expect(accepted.published, isTrue);
    expect(accepted.basisDigest, box.document.digest);
    expect(box.document.revision, 1);
    expect(box.draft.existsSync(), isFalse);
    expect(box.journal.existsSync(), isFalse);
    final bytes = box.basis.readAsBytesSync();
    final again = await box.accept(prepared.draftDigest!);
    expect(again.outcome, BasisOutcome.alreadyApplied);
    expect(again.exitCode, 0);
    expect(again.published, isFalse);
    expect(box.basis.readAsBytesSync(), bytes);
  });

  test('changed_sources_before_rename_require_new_review', () async {
    box.box.file('docs/politica.md', 'Revisar contratos.\n');
    final prepared = await box.prepare(
      box.input(ruleWithSource('docs/politica.md')),
    );
    box.box.file('docs/politica.md', 'Otra política.\n');
    final result = await box.accept(prepared.draftDigest!);
    expect(result.exitCode, 75);
    expect(codesOf(result), contains('source_changed'));
    expect(result.published, isFalse);
    expect(box.basis.existsSync(), isFalse);
    expect(box.draft.existsSync(), isTrue);
    expect(box.journal.existsSync(), isFalse);
  });

  test('an unverifiable support blocks accepting an active rule', () async {
    final prepared = await box.prepare(
      box.input(ruleWithSource('docs/ausente.md')),
    );
    final result = await box.accept(prepared.draftDigest!);
    expect(result.exitCode, 65);
    expect(codesOf(result), contains('source_unverified'));
    expect(box.basis.existsSync(), isFalse);
    expect(box.draft.existsSync(), isTrue);
  });

  test(
    'an empty first acceptance is not_established; later, no_changes',
    () async {
      final first = await box.publish(box.input([]));
      expect(first.normativeCoverage, BasisCoverage.notEstablished);
      expect(box.document.revision, 1);
      final again = await box.prepare(box.input([]));
      expect(again.outcome, BasisOutcome.noChanges);
      expect(again.exitCode, 0);
      expect(box.draft.existsSync(), isFalse);
    },
  );

  test('a stale expected basis is base_changed', () async {
    await box.publish(box.input([create('rule', ruleOf())]));
    final result = await box.prepare(
      box.input([create('other', ruleOf())], currentBase: false),
    );
    expect(result.exitCode, 75);
    expect(codesOf(result), contains('base_changed'));
  });

  group('two_writers_do_not_overwrite_draft', () {
    test('another prepare is a draft_conflict and keeps the first', () async {
      final first = await box.prepare(box.input([create('a', ruleOf())]));
      final bytes = box.draft.readAsBytesSync();
      final second = await box.prepare(
        box.input([create('b', ruleOf(statement: 'Otra.'))]),
      );
      expect(second.exitCode, 75);
      expect(codesOf(second), contains('draft_conflict'));
      expect(box.draft.readAsBytesSync(), bytes);
      final same = await box.prepare(box.input([create('a', ruleOf())]));
      expect(same.draftDigest, first.draftDigest);
      expect(box.draft.readAsBytesSync(), bytes);
    });

    test('a draft written during the publication is never replaced', () async {
      final foreign = 'ajeno\n';
      box.storeWrap = (real) => _DraftOnLock(real, box.draft.path, foreign);
      final result = await box.prepare(box.input([create('a', ruleOf())]));
      expect(result.exitCode, 75);
      expect(codesOf(result), contains('draft_conflict'));
      expect(box.draft.readAsStringSync(), foreign);
    });
  });

  test('full_history_budget_preserves_previous_bytes', () async {
    await box.publish(box.input([create('rule', ruleOf())]));
    final bytes = box.basis.readAsBytesSync();
    box.limits = BasisLimits.fromJson({
      ...box.limits.toJson(),
      'maxBasisBytes': bytes.length + 64,
    });
    final prepared = await box.prepare(
      box.input([create('big', ruleOf(statement: 'x' * 2000))]),
    );
    final result = await box.accept(prepared.draftDigest!);
    expect(result.exitCode, 65);
    expect(codesOf(result), contains('budget_exceeded'));
    expect(box.basis.readAsBytesSync(), bytes);
    expect(box.draft.existsSync(), isTrue);
  });

  test('discard removes only the matching draft', () async {
    final prepared = await box.prepare(box.input([create('a', ruleOf())]));
    final wrong = await box.discard('sha256:${'0' * 64}');
    expect(wrong.exitCode, 75);
    expect(box.draft.existsSync(), isTrue);
    final result = await box.discard(prepared.draftDigest!);
    expect(result.outcome, BasisOutcome.discarded);
    expect(result.exitCode, 0);
    expect(box.draft.existsSync(), isFalse);
    expect(box.basis.existsSync(), isFalse);
  });

  test('a pending init transaction blocks preparing', () async {
    box.box.file('pubspec.yaml', 'name: app\n# cambio\n');
    await expectLater(
      box.box.run(
        ContextOperation.refresh,
        wrap: (real) => CrashingStore(real, 1),
      ),
      throwsA(isA<SimulatedCrash>()),
    );
    final result = await box.prepare(box.input([create('a', ruleOf())]));
    expect(result.exitCode, 75);
    expect(codesOf(result), contains('recovery_required'));
    expect(box.draft.existsSync(), isFalse);
  });
}

/// Escribe un borrador ajeno justo al tomar el lock de publicación.
final class _DraftOnLock extends CrashingStore {
  _DraftOnLock(ContextStore real, this.path, this.text) : super(real, 1 << 30);

  final String path;
  final String text;

  @override
  Future<ContextLease> acquirePublication(
    List<ContextResource> resources,
  ) async {
    final lease = await real.acquirePublication(resources);
    File(path).writeAsStringSync(text);
    return lease;
  }
}
