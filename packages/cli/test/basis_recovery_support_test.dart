@Timeout(Duration(minutes: 3))
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_service_support.dart';
import 'support/basis_store_wrappers.dart';
import 'support/context_service_support.dart';

const _mebibyte = 1024 * 1024;

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  /// Acepta [digest] y muere justo después de escribir el journal, antes
  /// de revalidar: queda la aceptación registrada y la base en before.
  Future<void> crashAfterJournal(String digest) async {
    box.storeWrap = (real) => AfterJournal(real, () => throw SimulatedCrash());
    await expectLater(box.accept(digest), throwsA(isA<SimulatedCrash>()));
    box.storeWrap = null;
    expect(box.journal.existsSync(), isTrue);
  }

  List<String> actions(BasisResponse r) => [
    for (final a in r.nextActions) a.arguments.join(' '),
  ];

  group('recover verifies the supports that accept verifies', () {
    for (final (name, locator) in [
      ('a missing source', 'docs/missing.md'),
      ('an excluded source', '.ssh/notas.md'),
    ]) {
      test('a rule supported by $name is never published', () async {
        final prepared = await box.prepare(box.input(ruleWithSource(locator)));
        final digest = prepared.draftDigest!;
        final direct = await box.accept(digest);
        expect(direct.published, isFalse);
        expect(codesOf(direct), contains('source_unverified'));
        await crashAfterJournal(digest);
        final before = box.snapshot();
        final recovered = await box.recover();
        expect(recovered.published, isFalse);
        expect(codesOf(recovered), contains('source_unverified'));
        expect(actions(recovered), contains('--discard $digest'));
        expect(box.snapshot(), before);
        final discarded = await box.discard(digest);
        expect(discarded.outcome, BasisOutcome.abortedBeforePublication);
        expect(box.basis.existsSync(), isFalse);
        expect(box.journal.existsSync(), isFalse);
      });
    }

    test('a rule with a current source is recovered and published', () async {
      box.box.file('docs/politica.md', 'Una política.\n');
      final prepared = await box.prepare(
        box.input(ruleWithSource('docs/politica.md')),
      );
      await crashAfterJournal(prepared.draftDigest!);
      final recovered = await box.recover();
      expect(recovered.published, isTrue, reason: '${codesOf(recovered)}');
      expect(recovered.exitCode, 0);
      expect(box.journal.existsSync(), isFalse);
      expect(box.draft.existsSync(), isFalse);
    });

    test('an older rule that lost its source does not block', () async {
      box.box.file('docs/politica.md', 'Una política.\n');
      await box.publish(box.input(ruleWithSource('docs/politica.md')));
      box.box.file('docs/politica.md', 'Otra política.\n');
      final prepared = await box.prepare(box.input([create('p', pendingOf())]));
      await crashAfterJournal(prepared.draftDigest!);
      final recovered = await box.recover();
      expect(recovered.published, isTrue, reason: '${codesOf(recovered)}');
      expect(box.document.revision, 2);
    });

    test('recovering reads each source once within the budget', () async {
      for (var i = 0; i < 10; i++) {
        box.box.file('docs/s$i.md', 'x' * _mebibyte);
      }
      final prepared = await box.prepare(
        box.input([
          for (var i = 0; i < 10; i++)
            create('s$i', localSource('docs/s$i.md')),
          create(
            'r',
            ruleOf(
              support: BasisSupport.sourceSupported,
              sourceRefs: [
                for (var i = 0; i < 10; i++)
                  BasisReference(ref: 'new:s$i', version: 1),
              ],
            ),
          ),
        ]),
      );
      await crashAfterJournal(prepared.draftDigest!);
      late CountingReads counter;
      box.storeWrap = (real) => counter = CountingReads(real);
      final recovered = await box.recover();
      expect(recovered.published, isTrue, reason: '${codesOf(recovered)}');
      expect(counter.contentBytes, 10 * _mebibyte);
    });
  });
}
