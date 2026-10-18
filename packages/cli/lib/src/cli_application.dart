import 'dart:convert';

import 'cli_response.dart';

const _name = 'shipflow';
const _helpFlags = {'-h', '--help'};
const _versionFlag = '--version';
const _jsonFlag = '--json';
const _maxReflectedRunes = 160;
const _invalidUsageExitCode = 64;

const _summary =
    'Shipflow supervisa cambios de software verificables y recuperables.';
const _usage = ['shipflow [--help] [--json]', 'shipflow --version [--json]'];
const _options = [
  (flags: ['-h', '--help'], column: '-h, --help', text: 'Muestra esta ayuda.'),
  (
    flags: ['--version'],
    column: '--version',
    text: 'Muestra la versión del ejecutable.',
  ),
  (
    flags: ['--json'],
    column: '--json',
    text: 'Emite una única respuesta JSON.',
  ),
];

/// Decide la respuesta completa sólo a partir de [arguments]; no lee nada más.
CliResponse evaluateCli(List<String> arguments, {required String version}) {
  final json = arguments.contains(_jsonFlag);
  final problem = _firstProblem(arguments);
  if (problem != null) {
    return json
        ? _jsonResponse(_invalidUsageExitCode, {
            'schemaVersion': 1,
            'type': 'error',
            'code': 'invalid_usage',
            'message': problem,
            'exitCode': _invalidUsageExitCode,
          })
        : CliResponse(
            exitCode: _invalidUsageExitCode,
            channel: CliOutputChannel.stderr,
            payload: "$_name: $problem\nUsa 'shipflow --help'.\n",
          );
  }
  if (arguments.contains(_versionFlag)) {
    return json
        ? _jsonResponse(0, {
            'schemaVersion': 1,
            'type': 'version',
            'name': _name,
            'version': version,
            'exitCode': 0,
          })
        : _success('$_name $version\n');
  }
  return json
      ? _jsonResponse(0, {
          'schemaVersion': 1,
          'type': 'help',
          'name': _name,
          'usage': _usage,
          'options': [
            for (final option in _options)
              {'flags': option.flags, 'description': option.text},
          ],
          'exitCode': 0,
        })
      : _success(_humanHelp());
}

String? _firstProblem(List<String> arguments) {
  final seen = <String>[];
  for (final argument in arguments) {
    if (!_isKnown(argument)) {
      return argument.startsWith('-')
          ? 'opción desconocida: ${_reflect(argument)}'
          : 'argumento inesperado: ${_reflect(argument)}';
    }
    if (seen.contains(argument)) {
      return 'opción repetida: ${_reflect(argument)}';
    }
    for (final earlier in seen) {
      if (_helpFlags.contains(earlier) && _helpFlags.contains(argument)) {
        return '${_reflect(earlier)} y ${_reflect(argument)} '
            'son la misma opción';
      }
      if (_isAction(earlier) && _isAction(argument)) {
        return '${_reflect(earlier)} y ${_reflect(argument)} '
            'no se pueden combinar';
      }
    }
    seen.add(argument);
  }
  return null;
}

bool _isKnown(String argument) =>
    _helpFlags.contains(argument) ||
    argument == _versionFlag ||
    argument == _jsonFlag;

bool _isAction(String argument) =>
    _helpFlags.contains(argument) || argument == _versionFlag;

/// Cita [argument] de modo que cualquier entrada se muestre en una sola línea
/// acotada.
String _reflect(String argument) {
  final shown = StringBuffer();
  var length = 0;
  var truncated = false;
  for (final rune in argument.runes) {
    final piece = _escape(rune);
    final pieceLength = piece.runes.length;
    if (length + pieceLength > _maxReflectedRunes) {
      truncated = true;
      break;
    }
    shown.write(piece);
    length += pieceLength;
  }
  return "'$shown${truncated ? '…' : ''}'";
}

String _escape(int rune) {
  switch (rune) {
    case 0x0A:
      return r'\n';
    case 0x0D:
      return r'\r';
    case 0x09:
      return r'\t';
    case 0x5C:
      return r'\\';
    case 0x27:
      return r"\'";
  }
  if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
    return '\\x${rune.toRadixString(16).padLeft(2, '0')}';
  }
  if (_isInvisibleControl(rune)) {
    return '\\u{${rune.toRadixString(16)}}';
  }
  return String.fromCharCode(rune);
}

/// Los separadores de línea, los controles bidireccionales y los sustitutos
/// sueltos pueden partir o reordenar una línea de terminal aunque los
/// caracteres de control ya estén escapados.
bool _isInvisibleControl(int rune) =>
    rune == 0x2028 ||
    rune == 0x2029 ||
    (rune >= 0x202A && rune <= 0x202E) ||
    (rune >= 0x2066 && rune <= 0x2069) ||
    (rune >= 0xD800 && rune <= 0xDFFF);

String _humanHelp() {
  final lines = [
    _summary,
    '',
    'Uso:',
    for (final usage in _usage) '  $usage',
    '',
    'Opciones:',
    for (final option in _options)
      '  ${option.column.padRight(10)}  ${option.text}',
  ];
  return '${lines.join('\n')}\n';
}

CliResponse _success(String payload) => CliResponse(
  exitCode: 0,
  channel: CliOutputChannel.stdout,
  payload: payload,
);

CliResponse _jsonResponse(int exitCode, Map<String, Object> body) =>
    CliResponse(
      exitCode: exitCode,
      channel: CliOutputChannel.stdout,
      payload: '${jsonEncode(body)}\n',
    );
