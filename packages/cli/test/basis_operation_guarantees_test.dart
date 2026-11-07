@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/basis/basis_canonical.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_service_support.dart';
import 'support/basis_store_wrappers.dart';

const _otherProject = 'cccccccc-0000-4000-8000-000000000001';
const _mebibyte = 1024 * 1024;

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  /// Reescribe la base con otro projectId y su sello recalculado:
  /// formalmente válida, de otra copia.
  void foreignBasis() {
    final data =
        jsonDecode(box.basis.readAsStringSync()) as Map<String, dynamic>;
    data['projectId'] = _otherProject;
    data['digest'] = sealedDigest(data, 'digest');
    box.basis.writeAsStringSync(jsonEncode(data));
  }

  group('a repeated acceptance is bound to this project', () {
    test('repeat accept cannot claim an event from another project', () async {
      final accepted = await box.publish(box.input([create('a', ruleOf())]));
      foreignBasis();
      final result = await box.accept(accepted.draftDigest!);
      expect(result.exitCode, isNot(0));
      expect(result.outcome, isNot(BasisOutcome.alreadyApplied));
      expect(codesOf(result), contains('invalid_reference'));
      expect(result.selected, isEmpty);
    });

    test('without context a repeat claims nothing', () async {
      final accepted = await box.publish(box.input([create('a', ruleOf())]));
      File(box.path('shipflow/project.json')).deleteSync();
      final result = await box.accept(accepted.draftDigest!);
      expect(result.exitCode, isNot(0));
      expect(codesOf(result), contains('context_required'));
      expect(result.selected, isEmpty);
    });

    test('a repeat in the same project is still already applied', () async {
      final accepted = await box.publish(box.input([create('a', ruleOf())]));
      final again = await box.accept(accepted.draftDigest!);
      expect(again.exitCode, 0);
      expect(again.outcome, BasisOutcome.alreadyApplied);
      expect(again.selected, hasLength(1));
    });

    test('under the lock a repeat is bound to the project too', () async {
      final prepared = await box.prepare(box.input([create('a', ruleOf())]));
      box.storeWrap = (real) => BeforeLock(real, () async {
        box.storeWrap = null;
        expect((await box.accept(prepared.draftDigest!)).published, isTrue);
        foreignBasis();
      });
      final result = await box.accept(prepared.draftDigest!);
      expect(result.outcome, isNot(BasisOutcome.alreadyApplied));
      expect(codesOf(result), contains('invalid_reference'));
      expect(result.selected, isEmpty);
    });
  });

  group('an acceptance has one source budget', () {
    /// Diez fuentes de 1 MiB y una regla que las cita todas.
    Future<BasisResponse> tenSources() {
      for (var i = 0; i < 10; i++) {
        box.box.file('docs/s$i.md', 'x' * _mebibyte);
      }
      return box.prepare(
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
    }

    test('an acceptance respects the total standard source budget', () async {
      final prepared = await tenSources();
      late CountingReads counter;
      box.storeWrap = (real) => counter = CountingReads(real);
      final accepted = await box.accept(prepared.draftDigest!);
      expect(accepted.published, isTrue, reason: '${codesOf(accepted)}');
      expect(
        counter.contentBytes,
        lessThanOrEqualTo(box.limits.maxTotalSourceBytes),
      );
    });

    test('a revalidation that does not fit stops before publishing', () async {
      final prepared = await tenSources();
      box.limits = BasisLimits.fromJson({
        ...box.limits.toJson(),
        'maxTotalSourceBytes': 5 * _mebibyte,
      });
      final accepted = await box.accept(prepared.draftDigest!);
      expect(accepted.published, isFalse);
      expect(codesOf(accepted), contains('budget_exceeded'));
      expect(box.basis.existsSync(), isFalse);
      expect(box.journal.existsSync(), isFalse);
    });

    test('a source changed after the journal stops the publication', () async {
      box.box.file('docs/politica.md', 'Una política.\n');
      final prepared = await box.prepare(
        box.input(ruleWithSource('docs/politica.md')),
      );
      box.storeWrap = (real) => AfterJournal(real, () {
        box.box.file('docs/politica.md', 'Otra política.\n');
      });
      final accepted = await box.accept(prepared.draftDigest!);
      expect(accepted.published, isFalse);
      expect(codesOf(accepted), contains('source_changed'));
      expect(box.basis.existsSync(), isFalse);
      expect(box.journal.existsSync(), isFalse);
    });
  });
}
