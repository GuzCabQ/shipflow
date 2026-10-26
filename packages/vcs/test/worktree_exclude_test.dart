@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

import 'git_support.dart';

const _own = ['shipflow/project.json', 'shipflow/.gitignore'];
const _id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  final sandbox = GitSandbox()..register();
  final adapter = GitContextAdapter(parentEnvironment: realPath());

  Future<GitObservation> observe(Directory root) =>
      adapter.observe(root, ownPaths: _own);

  /// Escribe el bloque local de [root] como lo haría el coordinador.
  Future<void> applyLocal(Directory root) async {
    final observation = await observe(root);
    final path = observation.excludePath!;
    final file = File(path);
    final patch = planExclude(
      prefix: observation.binding!.prefix,
      choice: SharingChoice.local,
      existing: file.existsSync() ? file.readAsBytesSync() : null,
      blockId: _id,
    );
    file
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(patch.after!);
  }

  test(
    'the local block is effective and share sees it as a conflict',
    () async {
      final repo = sandbox.repository('repo');
      await applyLocal(repo);
      final observation = await observe(repo);
      final local = await adapter.verifySharing(
        observation,
        SharingChoice.local,
      );
      expect(local.effective, SharingEffective.localExcluded);
      final share = await adapter.verifySharing(
        observation,
        SharingChoice.share,
      );
      expect(share.effective, SharingEffective.conflict);
      expect(share.rule!.source, observation.excludePath);
    },
  );

  test('sharedExcludeDriftIsReportedWithoutAutomaticToggle', () async {
    final repo = sandbox.repository('repo');
    final linked = '${sandbox.base.path}/vinculado';
    git(['worktree', 'add', '-q', linked, '-b', 'otra'], repo);
    await applyLocal(repo);
    final exclude = File('${repo.path}/.git/info/exclude');
    final before = exclude.readAsBytesSync();
    final observation = await observe(Directory(linked));
    expect(observation.linkedWorktree, isTrue);
    expect(observation.excludePath, exclude.path);
    final share = await adapter.verifySharing(observation, SharingChoice.share);
    expect(share.effective, SharingEffective.conflict);
    expect(exclude.readAsBytesSync(), before);
  });

  test('a tracked file cannot become local', () async {
    final repo = sandbox.repository('repo');
    sandbox.file('repo/shipflow/project.json', '{}\n');
    git(['add', 'shipflow/project.json'], repo);
    final observation = await observe(repo);
    final local = await adapter.verifySharing(observation, SharingChoice.local);
    expect(local.effective, SharingEffective.conflict);
    expect(local.code, 'already_tracked');
    final share = await adapter.verifySharing(observation, SharingChoice.share);
    expect(share.effective, SharingEffective.shareReady);
  });

  test('a negation with higher precedence defeats the local block', () async {
    final repo = sandbox.repository('repo');
    sandbox.file('repo/.gitignore', '!shipflow/\n!shipflow/project.json\n');
    await applyLocal(repo);
    final observation = await observe(repo);
    final local = await adapter.verifySharing(observation, SharingChoice.local);
    expect(local.effective, SharingEffective.conflict);
    expect(local.code, 'not_excluded');
  });

  test('a foreign ignore rule blocks share and names its source', () async {
    final repo = sandbox.repository('repo');
    sandbox.file('repo/.gitignore', 'shipflow/\n');
    final observation = await observe(repo);
    final share = await adapter.verifySharing(observation, SharingChoice.share);
    expect(share.effective, SharingEffective.conflict);
    expect(share.code, 'ignored_by_rule');
    expect(share.rule!.source, '${repo.path}/.gitignore');
    expect(
      utf8.decode(File('${repo.path}/.gitignore').readAsBytesSync()),
      'shipflow/\n',
    );
  });
}
