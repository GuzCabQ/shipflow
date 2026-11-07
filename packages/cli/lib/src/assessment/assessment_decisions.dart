import 'package:core/core.dart';

/// Cada diagnóstico de assess: precedencia (gana el menor), código de
/// salida, consecuencia y acción estables. Uso, raíz, inesperado e I/O,
/// concurrencia y recuperación, integridad y compatibilidad, y después
/// preflight, vigencia y cobertura; 9 es un aviso que no cambia el código.
const _catalog = <String, (int, int, String, String)>{
  'invalid_root': (0, 66, 'cannot_observe', 'fix_root'),
  'unexpected': (1, 70, 'operation_failed', 'report_defect'),
  'io_failure': (1, 74, 'operation_failed', 'check_permissions'),
  'busy': (2, 75, 'not_published', 'retry_later'),
  'concurrent_change': (2, 75, 'not_published', 'retry_assess'),
  'source_changed': (2, 75, 'not_published', 'retry_assess'),
  'assessment_recovery_pending': (
    2,
    75,
    'publication_incomplete',
    'run_assess_recover',
  ),
  'context_recovery_pending': (2, 75, 'context_incomplete', 'run_init_recover'),
  'basis_recovery_pending': (
    2,
    75,
    'basis_incomplete',
    'run_bootstrap_recover',
  ),
  'recovery_conflict': (2, 75, 'manual_reconciliation', 'reconcile_manually'),
  'assessment_invalid': (3, 65, 'assessment_not_used', 'keep_backup'),
  'assessment_context_mismatch': (
    3,
    65,
    'assessment_not_current',
    'run_assess',
  ),
  'project_identity': (3, 65, 'assessment_not_used', 'keep_backup'),
  'context_invalid': (3, 65, 'cannot_observe', 'run_init'),
  'context_incompatible': (3, 65, 'cannot_observe', 'run_init_refresh'),
  'state_occupied': (3, 65, 'cannot_observe', 'move_foreign_state'),
  'state_invalid': (3, 65, 'cannot_observe', 'keep_backup'),
  'context_absent': (4, 65, 'cannot_observe', 'run_init'),
  'context_stale': (4, 65, 'cannot_observe', 'run_init_refresh'),
  'context_unverified': (4, 65, 'cannot_observe', 'widen_budget'),
  'choice_required': (4, 65, 'cannot_observe', 'choose_sharing'),
  'sharing_conflict': (4, 65, 'cannot_observe', 'run_init'),
  'git_unavailable': (4, 65, 'cannot_observe', 'check_git'),
  'assessment_absent': (4, 65, 'nothing_saved', 'run_assess'),
  'previous_absent': (4, 65, 'nothing_saved', 'none'),
  'assessment_stale': (4, 65, 'assessment_not_current', 'run_assess'),
  'assessment_unverified': (4, 65, 'freshness_unknown', 'widen_budget'),
  'coverage_partial': (4, 65, 'references_incomplete', 'review_gaps'),
  'assessment_limit': (4, 65, 'not_published', 'widen_budget'),
  'git_absent': (9, 0, 'not_versioned', 'none'),
  'comparison_unavailable': (9, 0, 'no_mechanical_diff', 'none'),
  'context_basis_unavailable': (9, 0, 'historical_link_unchecked', 'none'),
  'revision_retired': (9, 0, 'history_needs_backup', 'keep_backup'),
  'recovery_aborted': (9, 0, 'previous_kept', 'run_assess'),
};

/// El diagnóstico de [code] con su cuenta y hasta cinco rutas de ejemplo;
/// la raíz no es una ruta de ejemplo.
AssessmentDiagnostic assessmentDiagnostic(
  String code, {
  List<String> examples = const [],
  int? count,
}) {
  final (_, _, consequence, action) = _catalog[code]!;
  final sorted = ({
    ...examples.where(isAssessmentPath),
  }.toList()..sort()).take(5).toList();
  return AssessmentDiagnostic(
    code: code,
    path: null,
    consequence: consequence,
    actionCode: action,
    count: count ?? (examples.isEmpty ? 1 : examples.length),
    examples: sorted,
  );
}

/// El código de salida de [diagnostics]: el del de mayor precedencia.
int assessmentExitCode(Iterable<AssessmentDiagnostic> diagnostics) {
  var best = (99, 0);
  for (final d in diagnostics) {
    final (precedence, exit, _, _) = _catalog[d.code] ?? (1, 70, '', '');
    if (precedence < best.$1) best = (precedence, exit);
  }
  return best.$2;
}

/// [diagnostics] en orden de precedencia y después de código.
List<AssessmentDiagnostic> byPrecedence(
  List<AssessmentDiagnostic> diagnostics,
) => [...diagnostics]
  ..sort((a, b) {
    final first = _catalog[a.code]!.$1.compareTo(_catalog[b.code]!.$1);
    return first != 0 ? first : a.code.compareTo(b.code);
  });

/// Si [code] es un aviso que no cambia el código de salida.
bool isAssessmentWarning(String code) => _catalog[code]!.$1 == 9;

AssessmentNextAction _action(
  List<String> argv,
  String purpose,
  AssessmentActionEffect effect,
) => AssessmentNextAction(
  argv: ['shipflow', ...argv],
  purpose: purpose,
  effect: effect,
);

final showAction = _action(
  ['assess', '--show'],
  'inspect_saved',
  AssessmentActionEffect.readOnly,
);
final showDetailAction = _action(
  ['assess', '--show', '--json'],
  'inspect_saved_detail',
  AssessmentActionEffect.readOnly,
);
final observeAction = _action(
  ['assess'],
  'observe_again',
  AssessmentActionEffect.writeOwnState,
);
final recoverAction = _action(
  ['assess', '--recover'],
  'recover_publication',
  AssessmentActionEffect.writeOwnState,
);

/// La acción que propone cada consecuencia, si existe un comando para ella.
final _byAction = <String, List<AssessmentNextAction>>{
  'run_init': [
    _action(
      ['init'],
      'initialize_context',
      AssessmentActionEffect.userDecision,
    ),
  ],
  'run_init_refresh': [
    _action(
      ['init', '--refresh'],
      'refresh_context',
      AssessmentActionEffect.writeOwnState,
    ),
  ],
  'run_init_recover': [
    _action(
      ['init', '--recover'],
      'recover_context',
      AssessmentActionEffect.writeOwnState,
    ),
  ],
  'choose_sharing': [
    for (final choice in ['share', 'local'])
      _action(
        ['init', '--sharing=$choice'],
        'choose_sharing',
        AssessmentActionEffect.userDecision,
      ),
  ],
  'run_bootstrap_recover': [
    _action(
      ['bootstrap', '--recover'],
      'recover_basis',
      AssessmentActionEffect.writeOwnState,
    ),
  ],
  'run_assess': [observeAction],
  'run_assess_recover': [recoverAction],
  'widen_budget': [
    _action(
      ['assess', '--report-budget=extended'],
      'widen_budget',
      AssessmentActionEffect.writeOwnState,
    ),
  ],
  'widen_budget_show': [
    _action(
      ['assess', '--show', '--report-budget=extended'],
      'widen_budget',
      AssessmentActionEffect.readOnly,
    ),
  ],
  'review_gaps': [showDetailAction],
};

/// Las acciones de [actionCode]; al consultar, ampliar el perfil también
/// sólo consulta.
List<AssessmentNextAction> actionsFor(
  String actionCode, {
  required bool show,
}) =>
    _byAction[show && actionCode == 'widen_budget'
        ? 'widen_budget_show'
        : actionCode] ??
    const [];
