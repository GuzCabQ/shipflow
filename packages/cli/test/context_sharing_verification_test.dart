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
    box.gitInit();
  });
  tearDown(() => box.dispose());

  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];
  File exclude() => File(box.path('.git/info/exclude'));
  List<int>? excludeBytes() =>
      exclude().existsSync() ? exclude().readAsBytesSync() : null;

  test(
    'RV2-02: Git failing while corroborating local publishes nothing',
    () async {
      final before = excludeBytes();
      final result = await box.run(
        ContextOperation.init,
        sharing: SharingChoice.local,
        git: box.gitFailingAfterObservation,
      );
      expect(result.exitCode, 65, reason: '${codes(result)}');
      expect(codes(result), contains('git_unavailable'));
      expect(result.outcome, isNot(ContextOutcome.initialized));
      expect(File(box.path('shipflow/project.json')).existsSync(), isFalse);
      expect(
        File(box.path('shipflow/local/settings.json')).existsSync(),
        isFalse,
      );
      expect(
        File(box.path('shipflow/local/transaction.json')).existsSync(),
        isFalse,
      );
      expect(excludeBytes(), before);
    },
  );

  test(
    'RV2-02: Git failing while corroborating a switch keeps the old one',
    () async {
      await box.run(
        ContextOperation.init,
        sharing: SharingChoice.share,
        git: box.realGit,
      );
      final before = box.snapshot();
      final result = await box.run(
        ContextOperation.init,
        sharing: SharingChoice.local,
        git: box.gitFailingAfterObservation,
      );
      expect(result.exitCode, 65, reason: '${codes(result)}');
      expect(codes(result), contains('git_unavailable'));
      expect(
        box.snapshot()..removeWhere((k, _) => k.startsWith('.git/')),
        before..removeWhere((k, _) => k.startsWith('.git/')),
      );
      expect(excludeBytes(), isNot(contains('shipflow')));
    },
  );

  test('RV2-02: doctor does not affirm a choice Git could not check', () async {
    await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
    );
    final doctor = await box.run(
      ContextOperation.doctor,
      git: box.gitFailingAfterObservation,
    );
    expect(doctor.sharing.effective, SharingEffective.unverified);
    expect(codes(doctor), contains('git_unavailable'));
    expect(doctor.exitCode, 65);
  });

  test('RV2-02: absent Git is still not an error for doctor', () async {
    await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
    );
    final doctor = await box.run(ContextOperation.doctor);
    expect(codes(doctor), contains('git_absent'));
    expect(codes(doctor), isNot(contains('git_unavailable')));
  });
}
