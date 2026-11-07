@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_service_support.dart';
import 'support/context_service_support.dart';

/// La conservación share/local comprueba también los archivos durables de
/// V3 y V4: nunca los retira del índice ni anuncia una elección que Git
/// contradice.
void main() {
  late ServiceSandbox box;
  late BasisBox basis;
  setUp(() async {
    box = ServiceSandbox.create()
      ..project()
      ..gitInit();
    basis = BasisBox.on(box);
  });
  tearDown(() => box.dispose());

  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];

  String tracked(String path) =>
      (Process.runSync('git', [
                'ls-files',
                path,
              ], workingDirectory: box.root.path).stdout
              as String)
          .trim();

  Future<ContextOperationResult> init(SharingChoice choice) =>
      box.run(ContextOperation.init, git: box.realGit, sharing: choice);

  test('tracked_basis_blocks_local_choice', () async {
    expect((await init(SharingChoice.share)).exitCode, 0);
    await basis.publish(basis.input([create('rule', ruleOf())]));
    Process.runSync('git', [
      'add',
      'shipflow/basis.json',
    ], workingDirectory: box.root.path);
    final bytes = basis.basis.readAsBytesSync();
    final result = await init(SharingChoice.local);
    expect(result.exitCode, 65);
    expect(codes(result), contains('already_tracked'));
    expect(tracked('shipflow/basis.json'), 'shipflow/basis.json');
    expect(basis.basis.readAsBytesSync(), bytes);
  });

  test('a tracked assessment also blocks the local choice', () async {
    expect((await init(SharingChoice.share)).exitCode, 0);
    box.file('shipflow/assessment.json', '{}\n');
    Process.runSync('git', [
      'add',
      'shipflow/assessment.json',
    ], workingDirectory: box.root.path);
    final result = await init(SharingChoice.local);
    expect(codes(result), contains('already_tracked'));
    expect(tracked('shipflow/assessment.json'), 'shipflow/assessment.json');
  });

  test('share detects a foreign rule that ignores the basis', () async {
    expect((await init(SharingChoice.local)).exitCode, 0);
    await basis.publish(basis.input([create('rule', ruleOf())]));
    box.file('.gitignore', 'shipflow/basis.json\n');
    final result = await init(SharingChoice.share);
    expect(result.exitCode, 65);
    expect(codes(result), contains('sharing_conflict'));
    expect(result.sharing.effective, isNot(SharingEffective.shareReady));
    expect(
      File(box.path('.gitignore')).readAsStringSync(),
      'shipflow/basis.json\n',
    );
  });

  test('drafts and journals stay local whatever the choice', () async {
    expect((await init(SharingChoice.share)).exitCode, 0);
    await basis.prepare(basis.input([create('rule', ruleOf())]));
    final ignored = Process.runSync('git', [
      'check-ignore',
      'shipflow/local/basis-draft.json',
    ], workingDirectory: box.root.path);
    expect(ignored.exitCode, 0);
  });
}
