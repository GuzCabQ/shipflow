import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

// Sólo el barril nombra los símbolos de cli: si pierde un export, este
// archivo deja de compilar aunque las pruebas que importan `src/` sigan bien.

const _digest =
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

String _variant(CliCommand command) => switch (command) {
  ShowHelp() => 'help',
  ShowVersion() => 'version',
  RejectUsage() => 'reject',
  RunInitDryRun() => 'init-dry-run',
  RunInit() => 'init',
  RunInitRefresh() => 'init-refresh',
  RunInitRecover() => 'init-recover',
  RunDoctor() => 'doctor',
  RunAssessment() => 'assess',
  RunBootstrap() => 'bootstrap',
};

void main() {
  test('the barrel names every command variant', () {
    final cases = {
      '': 'help',
      '--version': 'version',
      '--inventada': 'reject',
      'init --dry-run': 'init-dry-run',
      'init': 'init',
      'init --refresh': 'init-refresh',
      'init --recover': 'init-recover',
      'doctor': 'doctor',
      'assess': 'assess',
      'bootstrap': 'bootstrap',
    };
    for (final MapEntry(key: line, value: variant) in cases.entries) {
      final arguments = line.isEmpty ? <String>[] : line.split(' ');
      expect(_variant(parseCliCommand(arguments)), variant, reason: line);
    }
    expect(parseCliCommand(['--help']), isA<StaticCommand>());
    expect(parseCliCommand(['doctor']), isA<RunContext>());
    expect(ReportBudgetProfile.values, [
      ReportBudgetProfile.standard,
      ReportBudgetProfile.extended,
    ]);
  });

  test('init commands carry their fields', () {
    expect(
      parseCliCommand([
        'init',
        '--refresh',
        '--sharing=share',
        '--report-budget=extended',
        '--json',
      ]),
      isA<RunInitRefresh>()
          .having((c) => c.json, 'json', isTrue)
          .having(
            (c) => c.budgetProfile,
            'budget',
            ReportBudgetProfile.extended,
          )
          .having((c) => c.sharing, 'sharing', SharingChoice.share),
    );
    expect(
      parseCliCommand(['init', '--dry-run']),
      isA<RunInitDryRun>()
          .having((c) => c.json, 'json', isFalse)
          .having(
            (c) => c.budgetProfile,
            'budget',
            ReportBudgetProfile.standard,
          ),
    );
  });

  test('doctor and assessment commands carry their fields', () {
    expect(
      parseCliCommand(['doctor', '--report-budget=extended']),
      isA<RunDoctor>().having(
        (c) => c.budgetProfile,
        'budget',
        ReportBudgetProfile.extended,
      ),
    );
    expect(
      parseCliCommand(['assess', '--show', '--previous']),
      isA<RunAssessment>()
          .having((c) => c.action, 'action', AssessmentOperation.show)
          .having((c) => c.previous, 'previous', isTrue),
    );
  });

  test('bootstrap commands carry their fields', () {
    expect(
      parseCliCommand(['bootstrap', '--show', '--scope', '.']),
      isA<RunBootstrap>()
          .having((c) => c.operation, 'operation', BasisOperation.show)
          .having((c) => c.scope, 'scope', '.')
          .having((c) => c.history, 'history', isFalse),
    );
    expect(
      parseCliCommand(['bootstrap', '--show', '--history']),
      isA<RunBootstrap>()
          .having((c) => c.scope, 'scope', isNull)
          .having((c) => c.history, 'history', isTrue),
    );
    expect(
      parseCliCommand([
        'bootstrap',
        '--input',
        '-',
        '--report-budget=extended',
      ]),
      isA<RunBootstrap>()
          .having((c) => c.operation, 'operation', BasisOperation.prepare)
          .having((c) => c.input, 'input', '-')
          .having((c) => c.profile, 'profile', BasisProfile.extended),
    );
  });

  test('bootstrap acceptance carries the exact digest', () {
    expect(
      parseCliCommand(['bootstrap', '--accept', _digest]),
      isA<RunBootstrap>()
          .having((c) => c.operation, 'operation', BasisOperation.accept)
          .having((c) => c.digest, 'digest', _digest),
    );
  });

  test('static commands carry the exact problem and json choice', () {
    expect(
      parseCliCommand(['init', '--inventada', '--json']),
      isA<RejectUsage>()
          .having((c) => c.json, 'json', isTrue)
          .having(
            (c) => c.problem,
            'problem',
            "opción desconocida: '--inventada'",
          )
          .having((c) => c.topic.name, 'topic', 'init'),
    );
    expect(
      parseCliCommand(['--json=true']),
      isA<RejectUsage>().having((c) => c.json, 'json', isFalse),
    );
  });
}
