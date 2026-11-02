import 'package:test/test.dart';
import 'package:vcs/src/bounded_git_process.dart';

import 'git_support.dart';

void main() {
  final sandbox = GitSandbox()..register();

  BoundedGitProcess runner(GitBudget budget, String script) {
    final fake = sandbox.fakeGit('bin', script);
    return BoundedGitProcess(
      executable: '${fake.path}/git',
      parentEnvironment: realPath(),
      budget: budget,
    );
  }

  test(
    'idle time before and between queries does not consume Git time',
    () async {
      final budget = GitBudget(total: const Duration(milliseconds: 500));
      final process = runner(budget, 'exit 0');
      for (var i = 0; i < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final result = await process.run(['--version'], cwd: sandbox.base);
        expect(result.cut, isNull);
        expect(result.exitCode, 0);
      }
      expect(budget.started, 2);
    },
  );

  test('queries share the time cap instead of resetting it', () async {
    final budget = GitBudget(total: const Duration(seconds: 2));
    final process = runner(budget, 'exec /bin/sleep 1.2');
    final first = await process.run(['--version'], cwd: sandbox.base);
    expect(first.cut, isNull);
    expect(first.exitCode, 0);
    final second = await process.run(['--version'], cwd: sandbox.base);
    expect(second.cut, 'git_timeout');
    final third = await process.run(['--version'], cwd: sandbox.base);
    expect(third.cut, 'git_budget');
    expect(budget.started, 2);
  });

  test('queries still share the process cap', () async {
    final budget = GitBudget();
    final process = runner(budget, 'exit 0');
    for (var i = 0; i < 12; i++) {
      final result = await process.run(['--version'], cwd: sandbox.base);
      expect(result.exitCode, 0);
    }
    final exhausted = await process.run(['--version'], cwd: sandbox.base);
    expect(exhausted.cut, 'git_budget');
    expect(budget.started, 12);
  });
}
