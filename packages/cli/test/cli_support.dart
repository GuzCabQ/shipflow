import 'package:cli/cli.dart';
import 'package:test/test.dart';

const version = '1.2.3-rc.1+build.7';

const helpText =
    'Shipflow supervisa cambios de software verificables y recuperables.\n'
    '\n'
    'Uso:\n'
    '  shipflow [--help] [--json]\n'
    '  shipflow --version [--json]\n'
    '\n'
    'Opciones:\n'
    '  -h, --help  Muestra esta ayuda.\n'
    '  --version   Muestra la versión del ejecutable.\n'
    '  --json      Emite una única respuesta JSON.\n';

const helpJson =
    '{"schemaVersion":1,"type":"help","name":"shipflow","usage":["shipflow '
    '[--help] [--json]","shipflow --version [--json]"],"options":[{"flags":'
    '["-h","--help"],"description":"Muestra esta ayuda."},{"flags":'
    '["--version"],"description":"Muestra la versión del ejecutable."},'
    '{"flags":["--json"],"description":"Emite una única respuesta JSON."}],'
    '"exitCode":0}\n';

const versionJson =
    '{"schemaVersion":1,"type":"version","name":"shipflow",'
    '"version":"1.2.3-rc.1+build.7","exitCode":0}\n';

String humanError(String reason) =>
    "shipflow: $reason\nUsa 'shipflow --help'.\n";

String jsonError(String quotedReason) =>
    '{"schemaVersion":1,"type":"error","code":"invalid_usage",'
    '"message":$quotedReason,"exitCode":64}\n';

void expectResponse(
  List<String> arguments, {
  required int exitCode,
  required CliOutputChannel channel,
  required String payload,
}) {
  final response = evaluateCli(arguments, version: version);
  expect(response.exitCode, exitCode, reason: '$arguments');
  expect(response.channel, channel, reason: '$arguments');
  expect(response.payload, payload, reason: '$arguments');
}

void expectHumanError(List<String> arguments, String reason) => expectResponse(
  arguments,
  exitCode: 64,
  channel: CliOutputChannel.stderr,
  payload: humanError(reason),
);

void expectJsonError(List<String> arguments, String quotedReason) =>
    expectResponse(
      arguments,
      exitCode: 64,
      channel: CliOutputChannel.stdout,
      payload: jsonError(quotedReason),
    );
