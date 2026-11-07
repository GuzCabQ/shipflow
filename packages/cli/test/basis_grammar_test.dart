import 'package:cli/src/cli_command.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

CliCommand parse(String line) => parseCliCommand([
  'bootstrap',
  ...line.split(' ').where((s) => s.isNotEmpty),
]);

RunBootstrap run(String line) => parse(line) as RunBootstrap;

void main() {
  final digest = 'sha256:${'a' * 64}';

  group('valid invocations', () {
    test('without an operation it is the guide', () {
      expect(run('').operation, BasisOperation.guide);
      expect(run('--json').json, isTrue);
    });

    test('each operation with its operand', () {
      expect(run('--show').operation, BasisOperation.show);
      expect(run('--show --scope lib/a').scope, 'lib/a');
      expect(run('--show --history').history, isTrue);
      expect(run('--show --draft').draft, isTrue);
      expect(run('--input propuesta.json').input, 'propuesta.json');
      expect(run('--input -').input, '-');
      expect(run('--accept $digest').digest, digest);
      expect(run('--discard $digest').operation, BasisOperation.discard);
      expect(run('--recover').operation, BasisOperation.recover);
      expect(run('--input -').operation, BasisOperation.prepare);
    });

    test('the budget profile is a modifier of any operation', () {
      expect(
        run('--show --report-budget=extended').profile,
        BasisProfile.extended,
      );
      expect(run('--recover').profile, BasisProfile.standard);
    });

    test('help alone shows the bootstrap help', () {
      final help = parse('--help') as ShowHelp;
      expect(help.topic, HelpTopic.bootstrap);
    });
  });

  group('invalid_flags_do_not_read_project', () {
    for (final line in [
      '--nope',
      'posicional',
      '--show --show',
      '--scope lib/a',
      '--history',
      '--draft',
      '--show --scope lib/a --history',
      '--show --draft --history',
      '--show --scope lib/a --draft',
      '--show --recover',
      '--input a.json --accept $digest',
      '--accept $digest --discard $digest',
      '--input',
      '--accept',
      '--accept no-es-huella',
      '--show --scope',
      '--show --scope ../etc',
      '--show --scope /etc',
      '--show --scope lib/',
      '--show --scope lib//a',
      '--help --show',
      '--report-budget=enorme',
      '--json --json',
    ]) {
      test('«$line» is usage', () {
        final rejected = parse(line);
        expect(rejected, isA<RejectUsage>());
        expect((rejected as RejectUsage).topic, HelpTopic.bootstrap);
      });
    }
  });
}
