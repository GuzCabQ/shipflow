import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_assessment.dart';
import 'context_basis.dart';
import 'context_decisions.dart';
import 'context_observation.dart';
import 'context_result.dart';
import 'state_layout.dart';

/// Doctor: sólo lee archivos y consulta Git acotado. No crea `local/`, no
/// toma locks ni repara; si ve una operación pendiente, la informa.
Future<ContextOperationResult> runDoctor(
  ObservedContext o,
  GitContextAdapter git,
  GitBudget budget,
) async {
  final (:state, diagnostics: stateDiagnostics) = stateOf(o);
  final (:freshness, diagnostics: freshDiagnostics) = freshnessOf(o, state);
  final (:sharing, diagnostics: sharingDiagnostics) = await sharingOf(
    o,
    git,
    budget,
  );
  final parts = ResultParts(
    command: ContextCommand.doctor,
    operation: ContextOperation.doctor,
    state: state,
    freshness: freshness,
    sharing: sharing,
    context: o.project.value?.recognition,
    success: ContextOutcome.available,
  );
  parts.diagnostics
    ..addAll(stateDiagnostics)
    ..addAll(freshDiagnostics)
    ..addAll(sharingDiagnostics);
  _withBasis(parts, o.ownership);
  if (state == ContextState.absent && stateDiagnostics.isEmpty) {
    parts.diagnostics.add(
      diagnostic('context_absent', 'Todavía no hay contexto guardado aquí.'),
    );
  }
  parts.actions.addAll(nextActionsFor(parts.diagnostics, o));
  return resultOf(parts, EffectsLog().freeze(budget.started));
}

/// El estado de la base en [parts], con sus diagnósticos.
void _withBasis(ResultParts parts, StateOwnership ownership) => parts
  ..basis = ownership.basis
  ..basisTransaction = ownership.basisTransaction
  ..diagnostics.addAll(basisDiagnostics(ownership));

/// Los comandos existentes que resuelven [diagnostics], sin repetir.
List<ContextNextAction> nextActionsFor(
  List<ContextDiagnostic> diagnostics,
  ObservedContext o,
) {
  final codes = {for (final d in diagnostics) d.code};
  return [
    if (codes.contains('recovery_pending')) recoverAction,
    if (codes.contains('basis_recovery_required')) bootstrapRecoverAction,
    if (codes.contains('context_absent') || codes.contains('not_initialized'))
      firstInitAction,
    if (codes.contains('context_stale') ||
        codes.contains('context_incompatible'))
      refreshAction,
    if (codes.contains('recognition_unverified')) extendedAction,
    if (codes.contains('choice_pending') && o.gitUsable) ...sharingActions(),
  ];
}
