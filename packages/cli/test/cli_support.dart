import 'package:cli/cli.dart';
import 'package:test/test.dart';
import 'static_evaluation.dart';

const version = '1.2.3-rc.1+build.7';

const _budget = '[--report-budget=standard|extended]';
const _dryRunUsage = 'shipflow init --dry-run [--json] $_budget';
const _initUsage = 'shipflow init [--sharing=share|local] [--json] $_budget';
const _refreshUsage =
    'shipflow init --refresh [--sharing=share|local] [--json] $_budget';
const _recoverUsage = 'shipflow init --recover [--json] $_budget';
const _jsonText = 'Emite una única respuesta JSON; nunca pregunta.';
const _initCommandText =
    'Inicializa el contexto del proyecto o comprueba el guardado.';
const _doctorCommandText = 'Consulta el contexto guardado sin modificar nada.';
const _assessCommandText =
    'Observa las referencias del código y guarda o consulta su levantamiento.';
const _assess = 'shipflow assess [--json] $_budget';
const _assessShow = 'shipflow assess --show [--json] $_budget';
const _assessPrevious = 'shipflow assess --show --previous [--json] $_budget';
const _assessRecover = 'shipflow assess --recover [--json] $_budget';
const _bootstrapCommandText =
    'Guarda y consulta las decisiones aceptadas del proyecto y lo que falta '
    'aclarar.';
const _bootstrap = 'shipflow bootstrap [--json] $_budget';
const _bootstrapShow =
    'shipflow bootstrap --show [--scope <ruta> | --history | --draft] '
    '[--json] $_budget';
const _bootstrapInput =
    'shipflow bootstrap --input <archivo.json|-> [--json] $_budget';
const _bootstrapAccept =
    'shipflow bootstrap --accept <huella> [--json] $_budget';
const _bootstrapDiscard =
    'shipflow bootstrap --discard <huella> [--json] $_budget';
const _bootstrapRecover = 'shipflow bootstrap --recover [--json] $_budget';
const helpText =
    'Shipflow supervisa cambios de software verificables y recuperables.\n'
    '\n'
    'Uso:\n'
    '  shipflow [--help] [--json]\n'
    '  shipflow --version [--json]\n'
    '  $_dryRunUsage\n'
    '  $_initUsage\n'
    '  $_refreshUsage\n'
    '  $_recoverUsage\n'
    '  shipflow doctor [--json] $_budget\n'
    '  $_assess\n'
    '  $_assessShow\n'
    '  $_assessPrevious\n'
    '  $_assessRecover\n'
    '  $_bootstrap\n'
    '  $_bootstrapShow\n'
    '  $_bootstrapInput\n'
    '  $_bootstrapAccept\n'
    '  $_bootstrapDiscard\n'
    '  $_bootstrapRecover\n'
    '\n'
    'Comandos:\n'
    '  init        $_initCommandText\n'
    '  doctor      $_doctorCommandText\n'
    '  assess      $_assessCommandText\n'
    '  bootstrap   $_bootstrapCommandText\n'
    '\n'
    'Opciones:\n'
    '  -h, --help  Muestra esta ayuda.\n'
    '  --version   Muestra la versión del ejecutable.\n'
    '  --json      $_jsonText\n';

const helpJson =
    '{"schemaVersion":1,"type":"help","name":"shipflow","usage":['
    '"shipflow [--help] [--json]","shipflow --version [--json]",'
    '"$_dryRunUsage","$_initUsage","$_refreshUsage",'
    '"$_recoverUsage","shipflow doctor [--json] $_budget",'
    '"$_assess","$_assessShow","$_assessPrevious",'
    '"$_assessRecover","$_bootstrap","$_bootstrapShow","$_bootstrapInput",'
    '"$_bootstrapAccept","$_bootstrapDiscard","$_bootstrapRecover"],'
    '"commands":['
    '{"name":"init","description":"$_initCommandText"},'
    '{"name":"doctor","description":"$_doctorCommandText"},'
    '{"name":"assess","description":"$_assessCommandText"},'
    '{"name":"bootstrap","description":"$_bootstrapCommandText"}],"options":['
    '{"flags":["-h","--help"],"description":"Muestra esta ayuda."},'
    '{"flags":["--version"],"description":"Muestra la versión del '
    'ejecutable."},{"flags":["--json"],"description":"$_jsonText"}],'
    '"exitCode":0}\n';

const _initSummary =
    'Reconoce el proyecto y guarda su contexto inicial en '
    'shipflow/project.json, para reutilizarlo al volver sin repetir '
    'decisiones. Guardar no certifica su salud: no comprueba si compila, si '
    'pasan sus pruebas, su arquitectura ni el SDK instalado. Shipflow no '
    'ejecuta git add, commit ni push.';

const _budgetText =
    'Perfil del reconocimiento de esta invocación: standard, el de omisión, '
    'o extended, que admite uno mayor y puede consumir más recursos. No se '
    'guarda entre invocaciones.';
const _dryRunText =
    'Sólo inspecciona: no escribe, no pregunta ni ejecuta procesos.';
const _refreshText =
    'Reemplaza el contexto guardado por lo observado ahora, si el '
    'reconocimiento es elegible; conserva su identidad.';
const _recoverText =
    'Termina o deshace una operación propia interrumpida; no reinicia '
    'archivos dañados ni ajenos.';
const _sharingText =
    'Elige sin preguntar: share deja el contexto listo para versionarlo; '
    'local lo excluye con una regla propia en el exclude local de Git, que '
    'en copias de trabajo vinculadas puede alcanzar la misma ruta en las '
    'demás copias de ese repositorio en el equipo.';

const initHelpText =
    '$_initSummary\n'
    '\n'
    'Uso:\n'
    '  $_dryRunUsage\n'
    '  $_initUsage\n'
    '  $_refreshUsage\n'
    '  $_recoverUsage\n'
    '\n'
    'Opciones:\n'
    '  -h, --help  Muestra esta ayuda.\n'
    '  --dry-run   $_dryRunText\n'
    '  --refresh   $_refreshText\n'
    '  --recover   $_recoverText\n'
    '  --sharing=share|local\n'
    '              $_sharingText\n'
    '  --json      $_jsonText\n'
    '  --report-budget=standard|extended\n'
    '              $_budgetText\n';

const initHelpJson =
    '{"schemaVersion":1,"type":"help","name":"shipflow","command":"init",'
    '"usage":["$_dryRunUsage","$_initUsage","$_refreshUsage",'
    '"$_recoverUsage"],"options":[{"flags":["-h","--help"],'
    '"description":"Muestra esta ayuda."},{"flags":["--dry-run"],'
    '"description":"$_dryRunText"},{"flags":["--refresh"],"description":'
    '"$_refreshText"},{"flags":["--recover"],"description":"$_recoverText"},'
    '{"flags":["--sharing=share","--sharing=local"],"description":'
    '"$_sharingText"},{"flags":["--json"],"description":"$_jsonText"},'
    '{"flags":["--report-budget=standard","--report-budget=extended"],'
    '"description":"$_budgetText"}],"exitCode":0}\n';

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
