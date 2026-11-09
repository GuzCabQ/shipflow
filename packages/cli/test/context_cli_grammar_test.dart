import 'package:cli/src/command/cli_command.dart';
import 'package:cli/src/command/cli_parser.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('the persistent commands', () {
    for (final (arguments, matches) in [
      (['init'], isA<RunInit>().having((c) => c.sharing, 'sharing', isNull)),
      (
        ['init', '--sharing=local'],
        isA<RunInit>().having((c) => c.sharing, 'sharing', SharingChoice.local),
      ),
      (
        ['init', '--sharing=share', '--json'],
        isA<RunInit>().having((c) => c.json, 'json', isTrue),
      ),
      (['init', '--refresh'], isA<RunInitRefresh>()),
      (
        ['init', '--refresh', '--sharing=local'],
        isA<RunInitRefresh>().having(
          (c) => c.sharing,
          'sharing',
          SharingChoice.local,
        ),
      ),
      (['init', '--recover'], isA<RunInitRecover>()),
      (['doctor'], isA<RunDoctor>()),
      (
        ['doctor', '--json', '--report-budget=extended'],
        isA<RunDoctor>().having(
          (c) => c.budgetProfile,
          'profile',
          ReportBudgetProfile.extended,
        ),
      ),
      (['init', '--dry-run'], isA<RunInitDryRun>()),
      (
        ['doctor', '--help', '--json'],
        isA<ShowHelp>().having((c) => c.topic, 'topic', HelpTopic.doctor),
      ),
      (
        ['init', '--help'],
        isA<ShowHelp>().having((c) => c.topic, 'topic', HelpTopic.init),
      ),
    ]) {
      test(arguments.join(' '), () {
        expect(parseCliCommand(arguments), matches);
      });
    }
  });

  group('invalid usage is 64 before any inspection', () {
    for (final arguments in [
      ['init', '--dry-run', '--refresh'],
      ['init', '--refresh', '--recover'],
      ['init', '--dry-run', '--recover'],
      ['init', '--dry-run', '--sharing=local'],
      ['init', '--recover', '--sharing=share'],
      ['init', '--help', '--sharing=local'],
      ['init', '--sharing=otra'],
      ['init', '--sharing'],
      ['init', '--sharing=share', '--sharing=local'],
      ['init', '--refresh', '--refresh'],
      ['init', 'carpeta'],
      ['init', '--force'],
      ['init', '--yes'],
      ['doctor', 'carpeta'],
      ['doctor', '--sharing=share'],
      ['doctor', '--refresh'],
      ['doctor', '--report-budget=enorme'],
      ['doctor', '--help', '--report-budget=extended'],
    ]) {
      test(arguments.join(' '), () {
        final command = parseCliCommand(arguments);
        expect(command, isA<RejectUsage>());
        expect(
          (command as RejectUsage).topic,
          arguments.first == 'doctor' ? HelpTopic.doctor : HelpTopic.init,
        );
      });
    }

    test('--json forces a structured answer despite another bad token', () {
      final command = parseCliCommand(['init', '--force', '--json']);
      expect(command, isA<RejectUsage>().having((c) => c.json, 'json', true));
    });

    test('the root keeps V0 and lists doctor', () {
      expect(parseCliCommand(['--version']), isA<ShowVersion>());
      expect(parseCliCommand(['doctor', '--version']), isA<RejectUsage>());
    });
  });
}
