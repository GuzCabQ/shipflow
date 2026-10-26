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

  test(
    'without a choice and without a terminal it asks for the flag',
    () async {
      final result = await box.run(ContextOperation.init, git: box.realGit);
      expect(result.exitCode, 65);
      expect(codes(result), contains('choice_required'));
      expect([
        for (final a in result.nextActions) a.arguments.join(' '),
      ], containsAll(['--sharing=share', '--sharing=local']));
      expect(Directory(box.path('shipflow')).existsSync(), isFalse);
    },
  );

  test('a cancelled prompt is 130 and writes nothing', () async {
    final result = await box.run(
      ContextOperation.init,
      git: box.realGit,
      choose: (_) async => null,
    );
    expect(result.outcome, ContextOutcome.cancelled);
    expect(result.exitCode, 130);
    expect(Directory(box.path('shipflow')).existsSync(), isFalse);
  });

  test(
    'local excludes effectively before the record becomes visible',
    () async {
      exclude().writeAsStringSync('# ajeno\n*.log');
      final result = await box.run(
        ContextOperation.init,
        git: box.realGit,
        sharing: SharingChoice.local,
      );
      expect(
        result.outcome,
        ContextOutcome.initialized,
        reason: '${codes(result)}',
      );
      expect(result.sharing.effective, SharingEffective.localExcluded);
      expect(result.effects.excludeModified, isTrue);
      final text = exclude().readAsStringSync();
      expect(text, startsWith('# ajeno\n*.log\n# shipflow:'));
      final status =
          Process.runSync('git', [
                'status',
                '--porcelain',
              ], workingDirectory: box.root.path).stdout
              as String;
      expect(status, isNot(contains('shipflow')));
    },
  );

  test('local and back to share keeps every foreign rule', () async {
    exclude().writeAsStringSync('# ajeno\n*.log');
    await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.local,
    );
    final back = await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.share,
    );
    expect(back.exitCode, 0, reason: '${codes(back)}');
    expect(back.sharing.effective, SharingEffective.shareReady);
    expect(exclude().readAsStringSync(), '# ajeno\n*.log');
    final again = await box.run(ContextOperation.doctor, git: box.realGit);
    expect(again.exitCode, 0);
    expect(again.sharing.choice, SharingChoice.share);
  });

  test('S05: a foreign rule that ignores the record defeats share', () async {
    box.file('.gitignore', 'shipflow/\n');
    final result = await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.share,
    );
    expect(result.exitCode, 65);
    expect(codes(result), contains('sharing_conflict'));
    expect(Directory(box.path('shipflow')).existsSync(), isFalse);
    expect(File(box.path('.gitignore')).readAsStringSync(), 'shipflow/\n');
  });

  test('S05: a tracked record cannot become local', () async {
    await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.share,
    );
    Process.runSync('git', [
      'add',
      'shipflow',
    ], workingDirectory: box.root.path);
    final before = exclude().existsSync() ? exclude().readAsBytesSync() : null;
    final result = await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.local,
    );
    expect(codes(result), contains('already_tracked'));
    expect(result.exitCode, 65);
    expect(exclude().existsSync() ? exclude().readAsBytesSync() : null, before);
  });

  test('Git that appears later brings the pending choice back', () async {
    await box.run(ContextOperation.init);
    final doctor = await box.run(ContextOperation.doctor, git: box.realGit);
    expect(doctor.exitCode, 0);
    expect(doctor.sharing.effective, SharingEffective.pending);
    final init = await box.run(ContextOperation.init, git: box.realGit);
    expect(codes(init), contains('choice_required'));
  });

  test('S11: an unavailable Git keeps the choice and is not absence', () async {
    await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.share,
    );
    File(box.path('.git/HEAD')).writeAsStringSync('basura\n');
    final doctor = await box.run(ContextOperation.doctor, git: box.realGit);
    expect(doctor.sharing.gitState, GitState.unavailable);
    expect(doctor.sharing.choice, SharingChoice.share);
    expect(codes(doctor), contains('git_unavailable'));
    expect(doctor.exitCode, 65);
  });

  test('an impossible local after applying it restores the exclude', () async {
    box.file('.gitignore', '!shipflow/\n!shipflow/project.json\n');
    exclude().writeAsStringSync('# ajeno\n');
    final result = await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.local,
    );
    expect(result.exitCode, 65, reason: '${codes(result)}');
    expect(codes(result), contains('sharing_conflict'));
    expect(exclude().readAsStringSync(), '# ajeno\n');
    expect(File(box.path('shipflow/project.json')).existsSync(), isFalse);
    expect(
      File(box.path('shipflow/local/transaction.json')).existsSync(),
      isFalse,
    );
  });
}
