import 'package:core/core.dart';

import '../cli_command.dart';
import '../cli_grammar.dart';

const _valued = {scopeFlag, inputFlag, acceptFlag, discardFlag};
const _operations = {showFlag, inputFlag, acceptFlag, discardFlag, recoverFlag};
const _showOnly = {scopeFlag, historyFlag, draftFlag};
final _digest = RegExp(r'^sha256:[0-9a-f]{64}$');

/// Decide `bootstrap` sólo con sus [options], sin leer el proyecto: cada
/// opción una vez, una sola operación, `--scope`, `--history` y `--draft`
/// sólo con `--show` y excluyentes entre sí, y la ayuda sola. El primer
/// problema en orden es el informado.
CliCommand parseBootstrap(List<String> options, {required bool json}) {
  final seen = <String, String?>{};
  final problem = _read(options, seen) ?? _combination(seen.keys.toList());
  if (problem != null) {
    return RejectUsage(problem, HelpTopic.bootstrap, json: json);
  }
  if (seen.keys.any(helpFlags.contains)) {
    return ShowHelp(HelpTopic.bootstrap, json: json);
  }
  return RunBootstrap(
    json: json,
    operation: _operationOf(seen.keys),
    scope: seen[scopeFlag],
    history: seen.containsKey(historyFlag),
    draft: seen.containsKey(draftFlag),
    input: seen[inputFlag],
    digest: seen[acceptFlag] ?? seen[discardFlag],
    profile: budgetProfileIn(options) == ReportBudgetProfile.extended
        ? BasisProfile.extended
        : BasisProfile.standard,
  );
}

BasisOperation _operationOf(Iterable<String> seen) => seen.contains(showFlag)
    ? BasisOperation.show
    : seen.contains(inputFlag)
    ? BasisOperation.prepare
    : seen.contains(acceptFlag)
    ? BasisOperation.accept
    : seen.contains(discardFlag)
    ? BasisOperation.discard
    : seen.contains(recoverFlag)
    ? BasisOperation.recover
    : BasisOperation.guide;

/// Cada opción con su valor, en orden; el primer problema de forma.
String? _read(List<String> options, Map<String, String?> seen) {
  for (var i = 0; i < options.length; i++) {
    final option = options[i];
    final key = isBudgetOption(option) ? reportBudgetFlag : option;
    if (seen.containsKey(key)) {
      return 'opción repetida: ${reflectArgument(key)}';
    }
    if (isBudgetOption(option)) {
      if (!isValidBudgetOption(option)) return _budgetProblem;
      seen[key] = null;
    } else if (_valued.contains(option)) {
      final value = i + 1 < options.length ? options[i + 1] : null;
      final problem = _value(option, value);
      if (problem != null) return problem;
      seen[option] = value;
      i++;
    } else if (_known(option)) {
      seen[option] = null;
    } else {
      return option.startsWith('-')
          ? 'opción desconocida: ${reflectArgument(option)}'
          : 'argumento inesperado: ${reflectArgument(option)}';
    }
  }
  return null;
}

bool _known(String option) =>
    _operations.contains(option) ||
    _showOnly.contains(option) ||
    helpFlags.contains(option) ||
    option == jsonFlag;

const _budgetProblem =
    'valor no admitido para $reportBudgetFlag: usa '
    '$reportBudgetFlag=standard o $reportBudgetFlag=extended';

/// El valor de una opción que lo exige: presente, no otra opción; para
/// `--scope`, «.» o un prefijo relativo seguro, y para aceptar o descartar,
/// una huella `sha256:<hex>` exacta.
String? _value(String option, String? value) {
  if (value == null || (value.startsWith('-') && value != '-')) {
    return 'falta el valor de ${reflectArgument(option)}';
  }
  if (value == '-' && option != inputFlag) {
    return 'falta el valor de ${reflectArgument(option)}';
  }
  if (option == scopeFlag && value != '.' && !isBasisPrefix(value)) {
    return 'valor no válido para ${reflectArgument(option)}: usa «.» o una '
        'ruta relativa como lib/pagos';
  }
  if ((option == acceptFlag || option == discardFlag) &&
      !_digest.hasMatch(value)) {
    return 'valor no válido para ${reflectArgument(option)}: usa la huella '
        'sha256:<hex> del borrador';
  }
  return null;
}

/// Las combinaciones: una operación, modificadores de consulta sólo con
/// `--show` y sin mezclarse, y la ayuda sin operación ni perfil.
String? _combination(List<String> seen) {
  final operations = seen.where(_operations.contains).toList();
  if (operations.length > 1) return _combined(operations[0], operations[1]);
  final modifiers = seen.where(_showOnly.contains).toList();
  if (modifiers.isNotEmpty && !seen.contains(showFlag)) {
    return '${reflectArgument(modifiers.first)} sólo se usa con '
        '${reflectArgument(showFlag)}';
  }
  if (modifiers.length > 1) return _combined(modifiers[0], modifiers[1]);
  final help = seen.where(helpFlags.contains).firstOrNull;
  final other = seen
      .where((o) => !helpFlags.contains(o) && o != jsonFlag)
      .firstOrNull;
  if (help != null && other != null) return _combined(other, help);
  return null;
}

String _combined(String earlier, String later) =>
    '${reflectArgument(earlier)} y ${reflectArgument(later)} no se pueden '
    'combinar';
