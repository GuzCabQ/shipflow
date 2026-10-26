import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_decisions.dart';
import 'context_observation.dart';
import 'state_layout.dart';

/// El estado del contexto guardado y por qué.
({ContextState state, List<ContextDiagnostic> diagnostics}) stateOf(
  ObservedContext o,
) {
  if (_unsettled(o) case final unsettled?) return unsettled;
  return switch (o.ownership.kind) {
    StateOwnershipKind.foreign => (
      state: ContextState.absent,
      diagnostics: [_occupied(o.ownership)],
    ),
    StateOwnershipKind.invalid => (
      state: ContextState.invalid,
      diagnostics: [_invalid(o)],
    ),
    _ => _documentState(o),
  };
}

/// Una lectura inestable o una operación pendiente, que deciden antes que
/// el contenido.
({ContextState state, List<ContextDiagnostic> diagnostics})? _unsettled(
  ObservedContext o,
) {
  if (!o.stable) {
    return (
      state: ContextState.absent,
      diagnostics: [
        diagnostic(
          'concurrent_change',
          'El contexto cambió mientras se leía, dos veces; no se afirma una '
              'vista de dos generaciones.',
          projectPath,
        ),
      ],
    );
  }
  if (!o.journal.present) return null;
  return (
    state: ContextState.recoveryRequired,
    diagnostics: [
      diagnostic(
        o.journal.error == null ? 'recovery_pending' : 'journal_invalid',
        'Hay una operación de Shipflow sin terminar.',
        transactionPath,
      ),
    ],
  );
}

({ContextState state, List<ContextDiagnostic> diagnostics}) _documentState(
  ObservedContext o,
) {
  final saved = o.project.value;
  if (!o.project.present) return (state: ContextState.absent, diagnostics: []);
  if (saved == null) {
    return (
      state: ContextState.invalid,
      diagnostics: [
        diagnostic(
          'context_invalid',
          'El contexto guardado no cumple su formato; se conserva sin usarlo.',
          projectPath,
        ),
      ],
    );
  }
  if (saved.producer.recognitionContract != recognitionContract) {
    return (
      state: ContextState.incompatible,
      diagnostics: [
        diagnostic(
          'context_incompatible',
          'Lo produjo otro contrato de reconocimiento; esta versión no lo '
              'compara.',
          projectPath,
        ),
      ],
    );
  }
  return (state: ContextState.present, diagnostics: []);
}

ContextDiagnostic _occupied(StateOwnership ownership) => diagnostic(
  'state_occupied',
  'La carpeta shipflow tiene contenido que no es de Shipflow; no se usa ni '
      'se sobrescribe.',
  ownership.findings.isEmpty ? stateDirectory : ownership.findings.first,
);

ContextDiagnostic _invalid(ObservedContext o) {
  final leftovers = !o.project.present && !o.journal.present;
  return diagnostic(
    leftovers ? 'bootstrap_unverified' : 'state_invalid',
    leftovers
        ? 'Quedaron restos de una inicialización que no se pueden acreditar. '
              'Conserva o mueve la carpeta shipflow como respaldo y vuelve a '
              'ejecutar init.'
        : 'Un archivo de shipflow no cumple su formato; se conserva.',
    o.ownership.findings.isEmpty ? stateDirectory : o.ownership.findings.first,
  );
}

/// Si el contexto guardado coincide con lo observado ahora.
({ContextFreshness freshness, List<ContextDiagnostic> diagnostics}) freshnessOf(
  ObservedContext o,
  ContextState state,
) {
  if (state != ContextState.present) {
    return (
      freshness: state == ContextState.incompatible
          ? ContextFreshness.unverified
          : ContextFreshness.notApplicable,
      diagnostics: [],
    );
  }
  final current = o.current;
  if (current == null) {
    final limit = reachedReportLimit(o.report);
    return (
      freshness: ContextFreshness.unverified,
      diagnostics: [
        diagnostic(
          limit ? 'recognition_unverified' : 'not_eligible',
          limit
              ? 'El reconocimiento actual no cabe en el perfil pedido; no se '
                    'pudo comprobar la vigencia.'
              : 'El reconocimiento actual no es elegible; el contexto guardado '
                    'se conserva.',
        ),
      ],
    );
  }
  return _compared(o, current);
}

({ContextFreshness freshness, List<ContextDiagnostic> diagnostics}) _compared(
  ObservedContext o,
  PortableRecognition current,
) {
  final same = o.project.value!.observationDigest == digestOf(current);
  return (
    freshness: same ? ContextFreshness.current : ContextFreshness.stale,
    diagnostics: [
      if (!same)
        diagnostic(
          'context_stale',
          'Lo observado ahora difiere del contexto guardado.',
          projectPath,
        ),
    ],
  );
}

/// La modalidad guardada contra lo que Git dice ahora; sólo lee.
Future<({ContextSharing sharing, List<ContextDiagnostic> diagnostics})>
sharingOf(ObservedContext o, GitContextAdapter git, GitBudget budget) async {
  final choice = o.choice;
  ContextSharing sharing(SharingEffective effective) => ContextSharing(
    choice: choice,
    gitState: o.git.state,
    effective: effective,
  );
  switch (o.git.state) {
    case GitState.notInstalled || GitState.notRepository || GitState.notChecked:
      return (
        sharing: sharing(
          choice == SharingChoice.pending
              ? SharingEffective.pending
              : SharingEffective.unverified,
        ),
        diagnostics: [_absentGit()],
      );
    case GitState.unavailable:
      return (
        sharing: sharing(SharingEffective.unverified),
        diagnostics: [_unavailableGit(o.git)],
      );
    case GitState.available:
      return _verified(o, git, budget, sharing);
  }
}

Future<({ContextSharing sharing, List<ContextDiagnostic> diagnostics})>
_verified(
  ObservedContext o,
  GitContextAdapter git,
  GitBudget budget,
  ContextSharing Function(SharingEffective) sharing,
) async {
  if (o.choice == SharingChoice.pending) {
    return (
      sharing: sharing(SharingEffective.pending),
      diagnostics: [
        diagnostic(
          'choice_pending',
          'Todavía no se eligió cómo conservar el contexto en este repositorio.',
        ),
      ],
    );
  }
  if (reboundSettings(o)) {
    return (
      sharing: sharing(SharingEffective.conflict),
      diagnostics: [bindingChanged()],
    );
  }
  final check = await git.verifySharing(o.git, o.choice, budget: budget);
  return (
    sharing: sharing(check.effective),
    diagnostics: [
      if (check.effective == SharingEffective.conflict) sharingConflict(check),
    ],
  );
}

/// Si la elección guardada se vinculó a otro repositorio o prefijo.
bool reboundSettings(ObservedContext o) {
  final saved = o.settings.value?.binding;
  final now = o.git.binding;
  return saved != null &&
      now != null &&
      (saved.commonDir != now.commonDir ||
          saved.repositoryRoot != now.repositoryRoot ||
          saved.prefix != now.prefix);
}

ContextDiagnostic bindingChanged() => diagnostic(
  'binding_changed',
  'La elección se tomó para otro repositorio o ubicación; hay que '
      'confirmarla y el repositorio anterior no se edita.',
  settingsPath,
);

ContextDiagnostic _absentGit() => diagnostic(
  'git_absent',
  'Sin Git o sin repositorio: el contexto sirve en esta copia, pero Shipflow '
      'no lo versiona ni lo comparte; recuperarlo tras perder la copia '
      'requiere respaldo.',
);

ContextDiagnostic _unavailableGit(GitObservation git) => diagnostic(
  'git_unavailable',
  'No se pudo consultar Git (${git.code ?? 'error'}); no se afirma que la '
      'elección esté aplicada.',
);

/// El conflicto de modalidad con la regla responsable, saneada al mostrar.
ContextDiagnostic sharingConflict(SharingCheck check) => diagnostic(
  check.code == 'already_tracked' ? 'already_tracked' : 'sharing_conflict',
  switch (check.code) {
    'already_tracked' =>
      'Git ya sigue el contexto: elegir local no deshace la compartición '
          'anterior; decídelo en el proyecto.',
    'not_excluded' =>
      'Una regla con más precedencia impide excluir el contexto.',
    _ => 'Una regla de ignore impide versionar el contexto.',
  },
  check.rule == null
      ? null
      : '${check.rule!.source}:${check.rule!.line}: ${check.rule!.pattern}',
);
