import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

void main() {
  test('the barrel keeps the budget constructor, defaults and readings', () {
    final budget = GitBudget();
    final custom = GitBudget(
      maxProcesses: 3,
      total: const Duration(milliseconds: 750),
    );

    expect(budget.maxProcesses, 12);
    expect(budget.total, const Duration(seconds: 20));
    expect(budget.started, 0);
    expect(budget.remaining, const Duration(seconds: 20));
    expect(custom.maxProcesses, 3);
    expect(custom.total, const Duration(milliseconds: 750));
    expect(custom.started, 0);
    expect(custom.remaining, const Duration(milliseconds: 750));
  });

  test('a consumer cannot write the started count', () {
    final dynamic budget = GitBudget(maxProcesses: 1);

    expect(() => budget.started = 0, throwsNoSuchMethodError);
    expect((budget as GitBudget).started, 0);
  });
}
