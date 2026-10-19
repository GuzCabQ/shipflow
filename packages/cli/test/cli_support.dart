import 'package:cli/cli.dart';
import 'package:test/test.dart';
import 'static_evaluation.dart';

const version = '1.2.3-rc.1+build.7';

const helpText =
    'Shipflow supervisa cambios de software verificables y recuperables.\n'
    '\n'
    'Uso:\n'
    '  shipflow [--help] [--json]\n'
    '  shipflow --version [--json]\n'
    '  shipflow init --dry-run [--json] [--report-budget=standard|extended]\n'
    '\n'
    'Comandos:\n'
    '  init        Reconoce un proyecto sin modificarlo.\n'
    '\n'
    'Opciones:\n'
    '  -h, --help  Muestra esta ayuda.\n'
    '  --version   Muestra la versión del ejecutable.\n'
    '  --json      Emite una única respuesta JSON.\n';

const helpJson =
    '{"schemaVersion":1,"type":"help","name":"shipflow","usage":["shipflow '
    '[--help] [--json]","shipflow --version [--json]","shipflow init '
    '--dry-run [--json] [--report-budget=standard|extended]"],"commands":'
    '[{"name":"init","description":'
    '"Reconoce un proyecto sin modificarlo."}],"options":[{"flags":'
    '["-h","--help"],"description":"Muestra esta ayuda."},{"flags":'
    '["--version"],"description":"Muestra la versión del ejecutable."},'
    '{"flags":["--json"],"description":"Emite una única respuesta JSON."}],'
    '"exitCode":0}\n';

const _initSummary =
    'Reconoce la raíz tecnológica y propone una inicialización sin aplicarla. '
    'Sólo inspecciona: no modifica el proyecto, no guarda el reporte ni crea '
    'un expediente, y no comprueba si compila, si pasan sus pruebas, su '
    'arquitectura ni el SDK instalado.';

const _budgetText =
    'Perfil del reporte de esta invocación: standard, el de omisión, o '
    'extended, que admite un reporte mayor y puede consumir más recursos. '
    'No se guarda entre invocaciones.';

const initHelpText =
    '$_initSummary\n'
    '\n'
    'Uso:\n'
    '  shipflow init --dry-run [--json] [--report-budget=standard|extended]\n'
    '\n'
    'Opciones:\n'
    '  -h, --help  Muestra esta ayuda.\n'
    '  --dry-run   Inspecciona sin escribir ni ejecutar herramientas del proyecto.\n'
    '  --json      Emite una única respuesta JSON.\n'
    '  --report-budget=standard|extended\n'
    '              $_budgetText\n';

const initHelpJson =
    '{"schemaVersion":1,"type":"help","name":"shipflow","command":"init",'
    '"usage":["shipflow init --dry-run [--json] '
    '[--report-budget=standard|extended]"],"options":[{"flags":'
    '["-h","--help"],"description":"Muestra esta ayuda."},{"flags":'
    '["--dry-run"],"description":"Inspecciona sin escribir ni ejecutar '
    'herramientas del proyecto."},{"flags":["--json"],"description":'
    '"Emite una única respuesta JSON."},{"flags":'
    '["--report-budget=standard","--report-budget=extended"],"description":'
    '"$_budgetText"}],"exitCode":0}\n';

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
  final response = evaluate(arguments, version: version);
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
