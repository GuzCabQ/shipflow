import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:cli/src/assessment/assessment_decisions.dart';
import 'package:cli/src/cli_command.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  RunAssessment run(List<String> arguments) =>
      parseCliCommand(['assess', ...arguments]) as RunAssessment;

  test('every accepted form chooses its operation', () {
    expect(run([]).action, AssessmentOperation.observe);
    expect(run(['--show']).action, AssessmentOperation.show);
    expect(run(['--show', '--previous']).previous, isTrue);
    expect(run(['--previous', '--show']).previous, isTrue);
    expect(run(['--recover']).action, AssessmentOperation.recover);
    expect(run(['--json']).json, isTrue);
    expect(
      run(['--show', '--report-budget=extended']).budgetProfile,
      ReportBudgetProfile.extended,
    );
    expect(run([]).budgetProfile, ReportBudgetProfile.standard);
  });

  test('help needs no inspection and admits only json', () {
    expect(parseCliCommand(['assess', '--help']), isA<ShowHelp>());
    final json = parseCliCommand(['assess', '-h', '--json']) as ShowHelp;
    expect((json.topic, json.json), (HelpTopic.assess, true));
  });

  test('every rejected form is a usage error before reading', () {
    for (final arguments in [
      ['--previous'],
      ['--show', '--recover'],
      ['--recover', '--show'],
      ['--show', '--show'],
      ['--json', '--json'],
      ['extra'],
      ['--force'],
      ['--help', '--show'],
      ['--recover', '--help'],
      ['--help', '--report-budget=extended'],
      ['--previous', '--recover'],
      ['--report-budget=enorme'],
      ['--report-budget=standard', '--report-budget=extended'],
    ]) {
      final command = parseCliCommand(['assess', ...arguments]);
      expect(command, isA<RejectUsage>(), reason: '$arguments');
      expect((command as RejectUsage).topic, HelpTopic.assess);
    }
  });

  test('a usage error with json stays json and names the assess help', () {
    final rejected = respondStatically(
      parseCliCommand(['assess', '--previous', '--json']) as StaticCommand,
      version: '0.0.0',
    );
    expect(rejected.exitCode, 64);
    final body = jsonDecode(rejected.payload) as Map<String, Object?>;
    expect(body['code'], 'invalid_usage');
    final human = respondStatically(
      parseCliCommand(['assess', '--previous']) as StaticCommand,
      version: '0.0.0',
    );
    expect(human.payload, contains("Usa 'shipflow assess --help'."));
  });

  test('the root help lists assess without other future commands', () {
    final help = respondStatically(
      parseCliCommand(['--help']) as StaticCommand,
      version: '0.0.0',
    );
    expect(help.payload, contains('assess'));
    expect(help.payload, isNot(contains('analyze')));
    final assess = respondStatically(
      parseCliCommand(['assess', '--help']) as StaticCommand,
      version: '0.0.0',
    );
    expect(assess.payload, contains('shipflow assess --show --previous'));
  });

  test('nextActionsAreImplementedArgv', () {
    final codes = [
      'run_init',
      'run_init_refresh',
      'run_init_recover',
      'choose_sharing',
      'run_assess',
      'run_assess_recover',
      'widen_budget',
      'review_gaps',
    ];
    for (final show in [true, false]) {
      for (final code in codes) {
        for (final action in actionsFor(code, show: show)) {
          expect(action.argv.first, 'shipflow');
          final command = parseCliCommand(action.argv.sublist(1));
          expect(command, isNot(isA<RejectUsage>()), reason: '${action.argv}');
          expect(action.argv, isNot(contains('analyze')));
        }
      }
    }
  });
}
