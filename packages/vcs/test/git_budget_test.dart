import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/src/bounded_git_process.dart';
import 'package:vcs/vcs.dart';

import 'git_support.dart';

void main() {
  final sandbox = GitSandbox()..register();

  /// Cada lanzamiento deja una línea en `launches`: un testigo que no se
  /// deriva del contador que se prueba. Un proceso cortado antes de que su
  /// shell escriba no deja línea, y el primer exec de un script recién
  /// escrito puede tardar más de 100 ms: donde se cuenta un corte, el plazo
  /// deja ese margen.
  String marked(String script) =>
      "echo >> '${sandbox.base.path}/launches'\n$script";

  int launches() {
    final file = File('${sandbox.base.path}/launches');
    return file.existsSync() ? file.readAsLinesSync().length : 0;
  }

  BoundedGitProcess runner(
    GitBudget budget,
    String script, {
    String dir = 'bin',
    Duration perProcess = const Duration(seconds: 5),
  }) {
    final fake = sandbox.fakeGit(dir, marked(script));
    return BoundedGitProcess(
      executable: '${fake.path}/git',
      parentEnvironment: realPath(),
      budget: budget,
      perProcess: perProcess,
    );
  }

  Future<GitCommandResult> query(BoundedGitProcess process) =>
      process.run(['--version'], cwd: sandbox.base);

  /// Rechazada sin lanzar: ni el testigo, ni el contador ni el tiempo
  /// restante cambian.
  Future<void> expectRefused(BoundedGitProcess process) async {
    final budget = process.budget;
    final (before, started, remaining) = (
      launches(),
      budget.started,
      budget.remaining,
    );
    expect((await query(process)).cut, 'git_budget');
    expect(launches(), before);
    expect(budget.started, started);
    expect(budget.remaining, remaining);
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

  test('an empty budget launches nothing', () async {
    await expectRefused(runner(GitBudget(maxProcesses: 0), 'exit 0'));
    await expectRefused(runner(GitBudget(total: Duration.zero), 'exit 0'));
    await expectRefused(
      runner(GitBudget(), 'exit 0', perProcess: Duration.zero),
    );
    expect(launches(), 0);
  });

  test('an exceeded budget stays exceeded and launches nothing', () async {
    final budget = GitBudget(total: const Duration(milliseconds: 100));
    final process = runner(budget, 'exec /bin/sleep 0.3');
    expect((await query(process)).cut, 'git_timeout');
    expect(budget.remaining, lessThanOrEqualTo(Duration.zero));
    await expectRefused(process);
  });

  test('a failed start counts and charges the attempt', () async {
    final budget = GitBudget(maxProcesses: 1);
    final missing = BoundedGitProcess(
      executable: '${sandbox.base.path}/ausente',
      parentEnvironment: realPath(),
      budget: budget,
    );
    expect((await query(missing)).cut, 'git_start');
    expect(budget.started, 1);
    expect(budget.remaining, lessThan(budget.total));
    expect((await query(missing)).cut, 'git_budget');
    expect(budget.started, 1);
  });

  test('runners sharing a budget share its cap', () async {
    final budget = GitBudget(maxProcesses: 2);
    final a = runner(budget, 'exit 0', dir: 'a');
    final b = runner(budget, 'exit 0', dir: 'b');
    expect((await query(a)).exitCode, 0);
    expect((await query(b)).exitCode, 0);
    final third = await query(a);
    expect(third.cut, 'git_budget');
    expect(launches(), 2);
    expect(budget.started, 2);
  });

  test('separate budgets keep separate counts', () async {
    final spent = GitBudget(maxProcesses: 1);
    final own = GitBudget(maxProcesses: 1);
    final a = runner(spent, 'exit 0', dir: 'a');
    expect((await query(a)).exitCode, 0);
    expect((await query(a)).cut, 'git_budget');
    expect((await query(runner(own, 'exit 0', dir: 'b'))).exitCode, 0);
    expect(spent.started, 1);
    expect(own.started, 1);
    expect(launches(), 2);
  });

  test('the public adapter accumulates a budget it receives', () async {
    final fake = sandbox.fakeGit('falso', marked('exit 1'));
    final adapter = GitContextAdapter(
      parentEnvironment: {'PATH': fake.path, 'HOME': sandbox.base.path},
    );
    final budget = GitBudget(maxProcesses: 2);
    final root = sandbox.directory('raiz');
    Future<GitObservation> observe() =>
        adapter.observe(root, ownPaths: ['x'], budget: budget);
    final first = await observe();
    expect(first.state, GitState.unavailable);
    expect(first.processesStarted, 1);
    final second = await observe();
    expect(second.state, GitState.unavailable);
    expect(second.processesStarted, 2);
    final third = await observe();
    expect(third.code, 'git_budget');
    expect(third.processesStarted, 2);
    expect(launches(), 2);
  });

  test('every admitted outcome counts one attempt', () async {
    final budget = GitBudget();
    final failed = await query(runner(budget, 'exit 3', dir: 'falla'));
    expect(failed.cut, isNull);
    expect(failed.exitCode, 3);
    const noise = 'exec /usr/bin/head -c 2000000 /dev/zero';
    final noisy = runner(budget, noise, dir: 'ruido');
    expect((await query(noisy)).cut, 'git_output_limit');
    const short = Duration(seconds: 1);
    final slow = runner(
      budget,
      'exec /bin/sleep 5',
      dir: 'lento',
      perProcess: short,
    );
    expect((await query(slow)).cut, 'git_timeout');
    expect(budget.started, 3);
    expect(launches(), 3);
  });
}
