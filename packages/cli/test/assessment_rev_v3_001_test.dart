@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';
import 'support/context_service_support.dart';

/// Regresiones de la revisión independiente REV-V3-001 (R1–R8; R9 vive en
/// assessment_capacity_test.dart por su tamaño).
void main() {
  late AssessServiceBox box;
  setUp(() async => box = await AssessServiceBox.initialized());
  tearDown(() {
    Process.runSync('/bin/chmod', ['644', box.path('lib/main.dart')]);
    box.dispose();
  });

  Future<AssessmentResult> observe() => box.run(AssessmentOperation.observe);
  Future<AssessmentResult> recover() => box.run(AssessmentOperation.recover);
  String documentHash() => sha256Of(box.document.readAsBytesSync());
  void unreadable(String path) =>
      Process.runSync('/bin/chmod', ['000', box.path(path)]);

  test('R1: a source unreadable at revalidation is never published', () async {
    box.observerWrap = (real) => (root, context, limits) async {
      final observed = await real(root, context, limits);
      unreadable('lib/main.dart');
      return observed;
    };
    final result = await observe();
    expect(result.effects.published, isFalse);
    expect(result.exitCode, 75);
    expect(diagnosticCodes(result), contains('concurrent_change'));
    expect(result.freshness, isNot(AssessmentFreshness.current));
    expect(box.document.existsSync(), isFalse);
  });

  test('R1: recover does not finish over an unreadable source', () async {
    await observe();
    await interruptPublication(box);
    final before = documentHash();
    unreadable('lib/main.dart');
    final result = await recover();
    expect(result.effects.published, isFalse);
    expect(diagnosticCodes(result), contains('recovery_aborted'));
    expect(documentHash(), before);
  });

  test('R2: an unchanged snapshot is still revalidated', () async {
    await observe();
    final before = documentHash();
    box.observerWrap = (real) => (root, context, limits) async {
      final observed = await real(root, context, limits);
      File(
        box.path('lib/main.dart'),
      ).writeAsStringSync("import 'other.dart';\n");
      return observed;
    };
    final result = await observe();
    expect(result.exitCode, 75);
    expect(diagnosticCodes(result), contains('source_changed'));
    expect(result.freshness, isNot(AssessmentFreshness.current));
    expect(documentHash(), before);
  });

  test('R3: recover reports a commit that a later failure followed', () async {
    await observe();
    await interruptPublication(box);
    final before = documentHash();
    box.storeWrap = (real) => FailingStore(real, 2);
    final result = await recover();
    expect(documentHash(), isNot(before));
    expect(result.effects.published, isTrue);
    expect(result.effects.replaced, contains(assessmentPath));
    expect(result.exitCode, 74);
    expect(diagnosticCodes(result), contains('assessment_recovery_pending'));
  });

  test('R3: recovering a first publication says it was created', () async {
    await observe();
    await interruptPublication(box, first: true);
    final result = await recover();
    expect(result.exitCode, 0, reason: '${diagnosticCodes(result)}');
    expect(result.effects.published, isTrue);
    expect(result.effects.created, contains(assessmentPath));
    expect(result.effects.replaced, isEmpty);
  });

  test('R4: a journal of another project is kept, never adopted', () async {
    await observe();
    final saved = decodeAssessment(box.document.readAsBytesSync());
    await interruptPublication(
      box,
      projectId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final before = documentHash();
    final result = await recover();
    expect(result.exitCode, 75);
    expect(diagnosticCodes(result), contains('recovery_conflict'));
    expect(result.effects.published, isFalse);
    expect(documentHash(), before);
    expect(
      decodeAssessment(box.document.readAsBytesSync()).projectId,
      saved.projectId,
    );
    expect(File(box.path(assessmentJournalPath)).existsSync(), isTrue);
  });

  test(
    'R5: a compared value outside the safe vocabulary is not saved',
    () async {
      box.box.file(
        'lib/main.dart',
        "import 'other.dart' if (environment.key == 'PRIVATE_TEST_VALUE_123') "
            "'other.dart';\n",
      );
      final result = await observe();
      expect(result.effects.published, isTrue);
      expect(box.document.readAsStringSync(), isNot(contains('PRIVATE_TEST')));
    },
  );

  test(
    'R6: --previous with the current digest must match the context',
    () async {
      await observe();
      final saved = decodeAssessment(box.document.readAsBytesSync());
      final json = saved.current.toJson();
      ((json['units']! as List).first as Map)['label'] = 'foreign-unit';
      json['snapshotId'] = snapshotIdOf(AssessmentSnapshot.fromJson(json));
      box.document.writeAsBytesSync(
        encodeAssessment(
          AssessmentDocument(
            projectId: saved.projectId,
            revision: 2,
            current: saved.current,
            previous: AssessmentSnapshot.fromJson(json),
          ),
        ),
      );
      final result = await box.run(AssessmentOperation.show, previous: true);
      expect(result.exitCode, 65);
      expect(diagnosticCodes(result), contains('assessment_context_mismatch'));
    },
  );

  test('R7: recover rereads the context under the lock', () async {
    await observe();
    await interruptPublication(box);
    final before = documentHash();
    box.storeWrap = (real) =>
        _ContextChangeOnLock(real, box.path('shipflow/project.json'));
    final result = await recover();
    expect(result.effects.published, isFalse);
    expect(diagnosticCodes(result), contains('recovery_aborted'));
    expect(documentHash(), before);
  });

  test('R8: --show does not hide a journal it cannot read', () async {
    await observe();
    File(box.path(assessmentJournalPath)).writeAsStringSync('{broken journal');
    final result = await box.run(AssessmentOperation.show);
    expect(result.exitCode, 65);
    expect(diagnosticCodes(result), contains('state_invalid'));
    expect(result.diagnostics.first.examples, contains(assessmentJournalPath));
  });
}

/// Cambia los bytes del contexto justo al tomar el lock de publicación.
final class _ContextChangeOnLock extends CrashingStore {
  _ContextChangeOnLock(ContextStore real, this.project) : super(real, 1 << 30);

  final String project;

  @override
  Future<ContextLease> acquirePublication(
    List<ContextResource> resources,
  ) async {
    final lease = await real.acquirePublication(resources);
    final file = File(project);
    file.writeAsStringSync('${file.readAsStringSync()}\n');
    return lease;
  }
}
