import 'terminal_text.dart';

const initCommand = 'init';
const jsonFlag = '--json';
const versionFlag = '--version';
const dryRunFlag = '--dry-run';
const helpFlags = {'-h', '--help'};
const _maxReflectedRunes = 160;

/// De qué ayuda se trata, y adónde apunta un error de uso.
enum HelpTopic { root, init }

/// Lo que los argumentos piden. El token exacto `--json` elige la respuesta
/// estructurada aunque otro token sea inválido.
sealed class CliCommand {
  const CliCommand({required this.json});

  final bool json;
}

/// Lo que se responde sin mirar el proyecto.
sealed class StaticCommand extends CliCommand {
  const StaticCommand({required super.json});
}

final class ShowHelp extends StaticCommand {
  const ShowHelp(this.topic, {required super.json});

  final HelpTopic topic;
}

final class ShowVersion extends StaticCommand {
  const ShowVersion({required super.json});
}

final class RejectUsage extends StaticCommand {
  const RejectUsage(this.problem, this.topic, {required super.json});

  /// Ya acotado a una línea.
  final String problem;
  final HelpTopic topic;
}

final class RunInitDryRun extends CliCommand {
  const RunInitDryRun({required super.json});
}

const _root = _Grammar({versionFlag, ...helpFlags});
const _init = _Grammar({dryRunFlag, ...helpFlags});

/// Decide el comando sólo a partir de [arguments]: no lee nada más.
CliCommand parseCliCommand(List<String> arguments) {
  final json = arguments.contains(jsonFlag);
  if (arguments.isNotEmpty && arguments.first == initCommand) {
    return _parseInit(arguments.sublist(1), json: json);
  }
  if (_root.firstProblem(arguments) case final problem?) {
    return RejectUsage(problem, HelpTopic.root, json: json);
  }
  if (arguments.contains(versionFlag)) return ShowVersion(json: json);
  return ShowHelp(HelpTopic.root, json: json);
}

CliCommand _parseInit(List<String> options, {required bool json}) {
  if (_init.firstProblem(options) case final problem?) {
    return RejectUsage(problem, HelpTopic.init, json: json);
  }
  if (options.any(helpFlags.contains)) {
    return ShowHelp(HelpTopic.init, json: json);
  }
  if (options.contains(dryRunFlag)) return RunInitDryRun(json: json);
  return RejectUsage(
    'init requiere $dryRunFlag: esta versión sólo reconoce el proyecto, '
    'sin modificarlo',
    HelpTopic.init,
    json: json,
  );
}

/// Opciones sin valor, cada una una vez, con a lo sumo una acción; el primer
/// problema en el orden de los argumentos es el que se informa.
final class _Grammar {
  const _Grammar(this.actions);

  final Set<String> actions;

  String? firstProblem(List<String> arguments) {
    final seen = <String>[];
    for (final argument in arguments) {
      final problem = _problemWith(argument, seen);
      if (problem != null) return problem;
      seen.add(argument);
    }
    return null;
  }

  String? _problemWith(String argument, List<String> seen) {
    if (!actions.contains(argument) && argument != jsonFlag) {
      return argument.startsWith('-')
          ? 'opción desconocida: ${_reflect(argument)}'
          : 'argumento inesperado: ${_reflect(argument)}';
    }
    if (seen.contains(argument)) {
      return 'opción repetida: ${_reflect(argument)}';
    }
    for (final earlier in seen) {
      if (helpFlags.contains(earlier) && helpFlags.contains(argument)) {
        return '${_reflect(earlier)} y ${_reflect(argument)} '
            'son la misma opción';
      }
      if (actions.contains(earlier) && actions.contains(argument)) {
        return '${_reflect(earlier)} y ${_reflect(argument)} '
            'no se pueden combinar';
      }
    }
    return null;
  }
}

String _reflect(String argument) =>
    "'${singleLine(argument, maxRunes: _maxReflectedRunes)}'";
