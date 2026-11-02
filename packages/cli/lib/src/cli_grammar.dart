import 'package:core/core.dart';

import 'cli_command.dart';
import 'terminal_text.dart';

const _maxReflectedRunes = 160;

/// El perfil que nombra [argument] si es `--report-budget=<valor>` con un
/// valor exacto; null si es esa opción con otro valor o sin él.
ReportBudgetProfile? _budgetProfileOf(String argument) => ReportBudgetProfile
    .values
    .where((p) => argument == '$reportBudgetFlag=${p.name}')
    .firstOrNull;

bool _isBudget(String argument) =>
    argument == reportBudgetFlag || argument.startsWith('$reportBudgetFlag=');

/// Si [argument] es la opción de perfil, con cualquier valor.
bool isBudgetOption(String argument) => _isBudget(argument);

/// Si [argument] es la opción de perfil con un valor admitido.
bool isValidBudgetOption(String argument) => _budgetProfileOf(argument) != null;

/// [argument] acotado y entre comillas, para un mensaje de uso.
String reflectArgument(String argument) => _reflect(argument);

/// El perfil de [options], o el de omisión.
ReportBudgetProfile budgetProfileIn(List<String> options) =>
    options.map(_budgetProfileOf).nonNulls.firstOrNull ??
    ReportBudgetProfile.standard;

/// La elección de `--sharing=<share|local>` en [options], o null.
SharingChoice? sharingIn(List<String> options) =>
    options.map(_sharingOf).nonNulls.firstOrNull;

const _choices = [SharingChoice.share, SharingChoice.local];

SharingChoice? _sharingOf(String argument) => _choices
    .where((c) => argument == '$sharingFlag=${c.toWireName()}')
    .firstOrNull;

bool _isSharing(String argument) =>
    argument == sharingFlag || argument.startsWith('$sharingFlag=');

/// Opciones sin valor, cada una una vez, con a lo sumo una acción; el primer
/// problema en el orden de los argumentos es el que se informa. Con
/// [acceptsBudget] admite además una vez `--report-budget=<perfil>`, que no
/// se combina con la ayuda.
final class Grammar {
  const Grammar(
    this.actions, {
    this.acceptsBudget = false,
    this.acceptsSharing = false,
  });

  final Set<String> actions;
  final bool acceptsBudget;
  final bool acceptsSharing;

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
    if (acceptsBudget && _isBudget(argument)) {
      return _budgetProblem(argument, seen);
    }
    if (acceptsSharing && _isSharing(argument)) {
      return _sharingProblem(argument, seen);
    }
    if (acceptsSharing && _excludesSharing(argument)) {
      final sharing = seen.where(_isSharing).firstOrNull;
      if (sharing != null) {
        return '${_reflect(sharing)} y ${_reflect(argument)} no se pueden '
            'combinar';
      }
    }
    return _flagProblem(argument, seen);
  }

  /// Las acciones que no aplican una elección: la inspección, la
  /// recuperación y la ayuda.
  bool _excludesSharing(String argument) =>
      argument == dryRunFlag ||
      argument == recoverFlag ||
      helpFlags.contains(argument);

  String? _sharingProblem(String argument, List<String> seen) {
    if (_sharingOf(argument) == null) {
      return 'valor no admitido para $sharingFlag: usa $sharingFlag=share o '
          '$sharingFlag=local';
    }
    if (seen.any(_isSharing)) return "opción repetida: '$sharingFlag'";
    final excluded = seen.where(_excludesSharing).firstOrNull;
    if (excluded != null) {
      return '${_reflect(excluded)} y ${_reflect(argument)} no se pueden '
          'combinar';
    }
    return null;
  }

  String? _budgetProblem(String argument, List<String> seen) {
    if (_budgetProfileOf(argument) == null) {
      return 'valor no admitido para $reportBudgetFlag: usa '
          '$reportBudgetFlag=standard o $reportBudgetFlag=extended';
    }
    if (seen.any(_isBudget)) return "opción repetida: '$reportBudgetFlag'";
    final help = seen.where(helpFlags.contains).firstOrNull;
    if (help != null) {
      return '${_reflect(help)} y ${_reflect(argument)} no se pueden combinar';
    }
    return null;
  }

  String? _flagProblem(String argument, List<String> seen) {
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
      if (_isBudget(earlier) && helpFlags.contains(argument)) {
        return '${_reflect(earlier)} y ${_reflect(argument)} '
            'no se pueden combinar';
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
