import 'dart:convert';

import 'cli_command.dart';
import 'cli_response.dart';

const cliName = 'shipflow';
const schemaVersion = 1;
const successExitCode = 0;
const invalidUsageExitCode = 64;
const errorResponseType = 'error';

typedef _Option = ({List<String> flags, String column, String text});
typedef _Help = ({
  String summary,
  List<String> usage,
  List<_Option> options,
  String? command,
});

const _helpOption = (
  flags: ['-h', '--help'],
  column: '-h, --help',
  text: 'Muestra esta ayuda.',
);
const _jsonOption = (
  flags: [jsonFlag],
  column: jsonFlag,
  text: 'Emite una única respuesta JSON.',
);
const _commands = [
  (name: initCommand, text: 'Reconoce un proyecto sin modificarlo.'),
];

const _rootHelp = (
  summary:
      'Shipflow supervisa cambios de software verificables y recuperables.',
  usage: [
    'shipflow [--help] [--json]',
    'shipflow --version [--json]',
    'shipflow init --dry-run [--json]',
  ],
  options: [
    _helpOption,
    (
      flags: [versionFlag],
      column: versionFlag,
      text: 'Muestra la versión del ejecutable.',
    ),
    _jsonOption,
  ],
  command: null,
);

const _initHelp = (
  summary:
      'Reconoce la raíz tecnológica y propone una inicialización sin aplicarla.',
  usage: ['shipflow init --dry-run [--json]'],
  options: [
    _helpOption,
    (
      flags: [dryRunFlag],
      column: dryRunFlag,
      text: 'Inspecciona sin escribir ni ejecutar herramientas del proyecto.',
    ),
    _jsonOption,
  ],
  command: initCommand,
);

/// La respuesta completa de [command]; no lee nada más.
CliResponse respondStatically(
  StaticCommand command, {
  required String version,
}) => switch (command) {
  ShowHelp(:final topic, :final json) => _help(_helpOf(topic), json: json),
  ShowVersion(:final json) =>
    json
        ? jsonResponse(successExitCode, {
            'schemaVersion': schemaVersion,
            'type': 'version',
            'name': cliName,
            'version': version,
            'exitCode': successExitCode,
          })
        : _success('$cliName $version\n'),
  RejectUsage(:final problem, :final topic, :final json) => _usageError(
    problem,
    topic,
    json: json,
  ),
};

_Help _helpOf(HelpTopic topic) => switch (topic) {
  HelpTopic.root => _rootHelp,
  HelpTopic.init => _initHelp,
};

CliResponse _usageError(String problem, HelpTopic topic, {required bool json}) {
  if (json) {
    return jsonResponse(invalidUsageExitCode, {
      'schemaVersion': schemaVersion,
      'type': errorResponseType,
      'code': 'invalid_usage',
      'message': problem,
      'exitCode': invalidUsageExitCode,
    });
  }
  final hint = topic == HelpTopic.init
      ? 'shipflow init --help'
      : 'shipflow --help';
  return CliResponse(
    exitCode: invalidUsageExitCode,
    channel: CliOutputChannel.stderr,
    payload: "$cliName: $problem\nUsa '$hint'.\n",
  );
}

CliResponse _help(_Help help, {required bool json}) => json
    ? jsonResponse(successExitCode, {
        'schemaVersion': schemaVersion,
        'type': 'help',
        'name': cliName,
        if (help.command != null) 'command': help.command!,
        'usage': help.usage,
        if (help.command == null)
          'commands': [
            for (final c in _commands) {'name': c.name, 'description': c.text},
          ],
        'options': [
          for (final o in help.options)
            {'flags': o.flags, 'description': o.text},
        ],
        'exitCode': successExitCode,
      })
    : _success(_humanHelp(help));

String _humanHelp(_Help help) {
  final lines = [
    help.summary,
    '',
    'Uso:',
    for (final usage in help.usage) '  $usage',
    if (help.command == null) ...[
      '',
      'Comandos:',
      for (final c in _commands) '  ${c.name.padRight(10)}  ${c.text}',
    ],
    '',
    'Opciones:',
    for (final o in help.options) '  ${o.column.padRight(10)}  ${o.text}',
  ];
  return '${lines.join('\n')}\n';
}

CliResponse _success(String payload) => CliResponse(
  exitCode: successExitCode,
  channel: CliOutputChannel.stdout,
  payload: payload,
);

/// Una única línea JSON en stdout.
CliResponse jsonResponse(int exitCode, Map<String, Object?> body) =>
    CliResponse(
      exitCode: exitCode,
      channel: CliOutputChannel.stdout,
      payload: '${jsonEncode(body)}\n',
    );
