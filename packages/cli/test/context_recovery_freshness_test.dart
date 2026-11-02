@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';

void main() {
  late ServiceSandbox box;
  setUp(() {
    box = ServiceSandbox.create();
    box.project();
  });
  tearDown(() => box.dispose());

  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];
  ContextCheck freshnessCheck(ContextOperationResult r) =>
      r.checks.singleWhere((c) => c.id == ContextCheckId.recognitionFreshness);

  /// Primer init que muere con el contexto ya publicado.
  Future<void> publishedThenCrash() => expectLater(
    box.run(ContextOperation.init, wrap: (real) => CrashingStore(real, 6)),
    throwsA(isA<SimulatedCrash>()),
  );

  test('RV2-03: a source changed after publishing is reported stale', () async {
    await publishedThenCrash();
    expect(File(box.path('shipflow/project.json')).existsSync(), isTrue);
    box.file('packages/nuevo/pubspec.yaml', 'name: nuevo\n');
    final recover = await box.run(ContextOperation.recover);
    expect(recover.exitCode, 65, reason: '${codes(recover)}');
    expect(codes(recover), contains('context_stale'));
    expect(recover.freshness, ContextFreshness.stale);
    expect(freshnessCheck(recover).status, ContextCheckStatus.failed);
    final doctor = await box.run(ContextOperation.doctor);
    expect(doctor.freshness, recover.freshness);
  });

  test('RV2-03: an unobservable source leaves freshness unverified', () async {
    await publishedThenCrash();
    File(box.path('pubspec.yaml')).deleteSync();
    final recover = await box.run(ContextOperation.recover);
    expect(recover.exitCode, 65, reason: '${codes(recover)}');
    expect(codes(recover), isNot(contains('context_stale')));
    expect(recover.freshness, ContextFreshness.unverified);
    expect(freshnessCheck(recover).status, isNot(ContextCheckStatus.passed));
    final doctor = await box.run(ContextOperation.doctor);
    expect(doctor.freshness, recover.freshness);
    expect(codes(recover), containsAll(codes(doctor)..remove('git_absent')));
  });
}
