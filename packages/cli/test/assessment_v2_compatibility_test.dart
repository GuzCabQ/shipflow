@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/context/state_layout.dart';
import 'package:cli/src/context/state_ownership.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_store_support.dart';
import 'support/context_service_support.dart';

void main() {
  late AssessmentBox box;
  late AssessmentDocument first;
  setUp(() async {
    box = await AssessmentBox.initialized();
    (first, _) = await twoRevisions();
  });
  tearDown(() => box.dispose());

  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];

  test('a valid assessment keeps shipflow owned for init and doctor', () async {
    await box.publish(first);
    final bytes = box.document.readAsBytesSync();
    expect(
      (await inspectStateOwnership(box.box.root)).kind,
      StateOwnershipKind.owned,
    );
    final doctor = await box.box.run(ContextOperation.doctor);
    expect(doctor.exitCode, 0, reason: '${codes(doctor)}');
    final init = await box.box.run(ContextOperation.init);
    expect(init.exitCode, 0, reason: '${codes(init)}');
    expect(box.document.readAsBytesSync(), bytes);
  });

  test('a look-alike file is foreign and is never removed', () async {
    for (final name in ['assessment.json.bak', 'assessments.json']) {
      final file = File(box.path('shipflow/$name'))..writeAsStringSync('{}');
      final ownership = await inspectStateOwnership(box.box.root);
      expect(ownership.kind, StateOwnershipKind.foreign, reason: name);
      final doctor = await box.box.run(ContextOperation.doctor);
      expect(codes(doctor), contains('state_occupied'));
      expect(file.existsSync(), isTrue);
      file.deleteSync();
    }
  });

  test(
    'init --recover points to assess --recover and leaves its journal',
    () async {
      await expectLater(
        box.publish(first, wrap: (real) => CrashingStore(real, 2)),
        throwsA(isA<SimulatedCrash>()),
      );
      final journal = File(box.path(assessmentJournalPath)).readAsBytesSync();
      final recover = await box.box.run(ContextOperation.recover);
      expect(recover.exitCode, 75);
      final pending = recover.diagnostics.singleWhere(
        (d) => d.code == 'recovery_pending',
      );
      expect(pending.path, assessmentTransactionPath);
      expect(pending.message, contains('assess --recover'));
      expect(File(box.path(assessmentJournalPath)).readAsBytesSync(), journal);
    },
  );

  test('two active journals are a conflict, not a guessed order', () async {
    box.box.file('packages/b/pubspec.yaml', 'name: b\n');
    await expectLater(
      box.box.run(
        ContextOperation.refresh,
        wrap: (real) => CrashingStore(real, 1),
      ),
      throwsA(isA<SimulatedCrash>()),
    );
    expect(File(box.path(transactionPath)).existsSync(), isTrue);
    await expectLater(
      box.publish(first, wrap: (real) => CrashingStore(real, 2)),
      throwsA(isA<SimulatedCrash>()),
    );
    final recover = await box.box.run(ContextOperation.recover);
    expect(codes(recover), contains('recovery_conflict'));
    expect(recover.exitCode, 75);
    expect(File(box.path(transactionPath)).existsSync(), isTrue);
    expect(File(box.path(assessmentJournalPath)).existsSync(), isTrue);
  });
}
