import 'dart:convert';

import 'cli_command.dart';
import 'cli_help.dart';
import 'cli_response.dart';

const cliName = 'shipflow';
const schemaVersion = 1;
const successExitCode = 0;
const invalidUsageExitCode = 64;
const errorResponseType = 'error';

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

Help _helpOf(HelpTopic topic) => switch (topic) {
  HelpTopic.root => rootHelp,
  HelpTopic.init => initHelp,
  HelpTopic.doctor => doctorHelp,
  HelpTopic.assess => assessHelp,
  HelpTopic.bootstrap => bootstrapHelp,
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
  final hint = switch (topic) {
    HelpTopic.init => 'shipflow init --help',
    HelpTopic.doctor => 'shipflow doctor --help',
    HelpTopic.assess => 'shipflow assess --help',
    HelpTopic.bootstrap => 'shipflow bootstrap --help',
    HelpTopic.root => 'shipflow --help',
  };
  return CliResponse(
    exitCode: invalidUsageExitCode,
    channel: CliOutputChannel.stderr,
    payload: "$cliName: $problem\nUsa '$hint'.\n",
  );
}

CliResponse _help(Help help, {required bool json}) => json
    ? jsonResponse(successExitCode, {
        'schemaVersion': schemaVersion,
        'type': 'help',
        'name': cliName,
        if (help.command != null) 'command': help.command!,
        'usage': help.usage,
        if (help.command == null)
          'commands': [
            for (final c in helpCommands)
              {'name': c.name, 'description': c.text},
          ],
        'options': [
          for (final o in help.options)
            {'flags': o.flags, 'description': o.text},
        ],
        'exitCode': successExitCode,
      })
    : _success(_humanHelp(help));

String _humanHelp(Help help) {
  final lines = [
    help.summary,
    '',
    'Uso:',
    for (final usage in help.usage) '  $usage',
    if (help.command == null) ...[
      '',
      'Comandos:',
      for (final c in helpCommands) '  ${c.name.padRight(10)}  ${c.text}',
    ],
    '',
    'Opciones:',
    for (final o in help.options) ..._optionLines(o),
  ];
  return '${lines.join('\n')}\n';
}

/// Una opción y su texto en la misma línea; si la opción no cabe en la
/// columna, el texto va debajo, alineado con los demás.
List<String> _optionLines(HelpOption option) => option.column.length <= 10
    ? ['  ${option.column.padRight(10)}  ${option.text}']
    : ['  ${option.column}', '              ${option.text}'];

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
