import 'package:core/core.dart';

import 'cli_command.dart';
import 'cli_grammar.dart';

const _operations = {showFlag, previousFlag, recoverFlag};

/// Decide `assess` sólo con sus [options]: cada opción una vez, `--show` y
/// `--recover` excluyentes, `--previous` sólo con `--show` y la ayuda sin
/// opciones de operación. El primer problema en orden es el informado.
CliCommand parseAssess(List<String> options, {required bool json}) {
  final problem = _problem(options);
  if (problem != null) {
    return RejectUsage(problem, HelpTopic.assess, json: json);
  }
  if (options.any(helpFlags.contains)) {
    return ShowHelp(HelpTopic.assess, json: json);
  }
  return RunAssessment(
    json: json,
    action: options.contains(recoverFlag)
        ? AssessmentOperation.recover
        : options.contains(showFlag)
        ? AssessmentOperation.show
        : AssessmentOperation.observe,
    previous: options.contains(previousFlag),
    budgetProfile: budgetProfileIn(options),
  );
}

String? _problem(List<String> options) {
  final seen = <String>[];
  for (final option in options) {
    final problem = isBudgetOption(option)
        ? _budget(option, seen)
        : _flag(option, seen);
    if (problem != null) return problem;
    seen.add(option);
  }
  if (seen.contains(previousFlag) && !seen.contains(showFlag)) {
    return '${reflectArgument(previousFlag)} sólo se usa con '
        '${reflectArgument(showFlag)}';
  }
  return null;
}

String? _budget(String option, List<String> seen) {
  if (!isValidBudgetOption(option)) {
    return 'valor no admitido para $reportBudgetFlag: usa '
        '$reportBudgetFlag=standard o $reportBudgetFlag=extended';
  }
  if (seen.any(isBudgetOption)) {
    return 'opción repetida: ${reflectArgument(reportBudgetFlag)}';
  }
  return _withHelp(option, seen);
}

String? _flag(String option, List<String> seen) {
  if (!_operations.contains(option) &&
      !helpFlags.contains(option) &&
      option != jsonFlag) {
    return option.startsWith('-')
        ? 'opción desconocida: ${reflectArgument(option)}'
        : 'argumento inesperado: ${reflectArgument(option)}';
  }
  if (seen.contains(option)) {
    return 'opción repetida: ${reflectArgument(option)}';
  }
  final exclusive = {showFlag, recoverFlag};
  final other = seen.where((s) => exclusive.contains(s)).firstOrNull;
  if (exclusive.contains(option) && other != null) {
    return _combined(other, option);
  }
  if (option == recoverFlag && seen.contains(previousFlag)) {
    return _combined(previousFlag, option);
  }
  return _withHelp(option, seen);
}

/// La ayuda no se combina con opciones de operación ni de perfil.
String? _withHelp(String option, List<String> seen) {
  bool operational(String o) => _operations.contains(o) || isBudgetOption(o);
  final help = seen.where(helpFlags.contains).firstOrNull;
  if (help != null && (operational(option) || helpFlags.contains(option))) {
    return _combined(help, option);
  }
  final operation = seen.where(operational).firstOrNull;
  if (helpFlags.contains(option) && operation != null) {
    return _combined(operation, option);
  }
  return null;
}

String _combined(String earlier, String later) =>
    '${reflectArgument(earlier)} y ${reflectArgument(later)} no se pueden '
    'combinar';
