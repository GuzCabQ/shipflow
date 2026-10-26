import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_assessment.dart';
import 'context_decisions.dart';
import 'context_observation.dart';
import 'context_recovery_targets.dart';
import 'context_result.dart';
import 'context_transaction_runner.dart';
import 'secure_context_store.dart';
import 'state_layout.dart';

/// `init --recover`: termina o deshace sólo una transacción propia
/// demostrable. Compara los bytes reales de cada destino con sus huellas;
/// lo que no coincide con ninguna es un conflicto que no se sobrescribe.
Future<ContextOperationResult> recoverContext({
  required ObservedContext o,
  required ContextStore store,
  required GitContextAdapter git,
  required GitBudget budget,
  required Future<ContextStore> Function(Directory) openAdministration,
}) async {
  final effects = EffectsLog();
  final parts = _parts(o);
  final journal = o.journal.value;
  if (journal == null) {
    _withoutJournal(o, parts);
    return resultOf(parts, effects.freeze(budget.started));
  }
  final targets = RecoveryTargets(
    o: o,
    journal: journal,
    store: store,
    openAdministration: openAdministration,
    effects: effects,
  );
  try {
    await targets.acquire();
    await _recover(targets, o, git, budget, parts);
  } on ContextStoreFailure catch (failure) {
    parts.diagnostics.add(storeDiagnostic(failure));
  } finally {
    await targets.release();
  }
  return resultOf(parts, effects.freeze(budget.started));
}

ResultParts _parts(ObservedContext o) => ResultParts(
  command: ContextCommand.init,
  operation: ContextOperation.recover,
  state: o.journal.present
      ? ContextState.recoveryRequired
      : ContextState.absent,
  freshness: ContextFreshness.notApplicable,
  sharing: ContextSharing(
    choice: o.choice,
    gitState: o.git.state,
    effective: SharingEffective.unverified,
  ),
  success: ContextOutcome.recovered,
);

void _withoutJournal(ObservedContext o, ResultParts parts) {
  final (:state, :diagnostics) = stateOf(o);
  if (o.journal.present) {
    parts.diagnostics.add(
      diagnostic(
        'journal_invalid',
        'El registro de la operación no cumple su formato; se conserva para '
            'reconciliarlo a mano.',
        transactionPath,
      ),
    );
    return;
  }
  parts.diagnostics.addAll(diagnostics);
  if (state == ContextState.absent && diagnostics.isEmpty) {
    parts.diagnostics.add(
      diagnostic('not_initialized', 'No hay una operación ni un contexto.'),
    );
    parts.actions.add(firstInitAction);
  }
}

Future<void> _recover(
  RecoveryTargets t,
  ObservedContext o,
  GitContextAdapter git,
  GitBudget budget,
  ResultParts parts,
) async {
  final conflict = await t.conflicting();
  if (conflict != null) {
    parts.diagnostics.add(
      diagnostic(
        'recovery_conflict',
        'Un archivo no coincide con la versión anterior ni con la preparada; '
            'se conserva todo para reconciliarlo a mano.',
        conflict,
      ),
    );
    return;
  }
  if (await t.projectPublished()) {
    return _finishPublished(t, o, git, budget, parts);
  }
  final candidate = t.candidate();
  if (candidate == null ||
      digestOf(candidate.recognition) != _currentDigest(o)) {
    await t.revert();
    await t.cleanup();
    return _aborted(t, parts);
  }
  await _finishPending(t, o, git, budget, parts, candidate);
}

String? _currentDigest(ObservedContext o) =>
    o.current == null ? null : digestOf(o.current!);

/// El contexto ya se publicó: se completan los efectos propios y, si las
/// fuentes cambiaron, se conserva como desactualizado.
Future<void> _finishPublished(
  RecoveryTargets t,
  ObservedContext o,
  GitContextAdapter git,
  GitBudget budget,
  ResultParts parts,
) async {
  if (!await t.applyRemaining()) return _conflict(parts);
  await t.cleanup();
  final published = t.publishedProject();
  _present(
    parts,
    published,
    git: await _verify(t, o, git, budget),
    choice: t.choice,
  );
  if (published != null && published.observationDigest != _currentDigest(o)) {
    parts.diagnostics.add(
      diagnostic('context_stale', 'Lo observado cambió durante la operación.'),
    );
    parts.actions.add(refreshAction);
  }
}

Future<void> _finishPending(
  RecoveryTargets t,
  ObservedContext o,
  GitContextAdapter git,
  GitBudget budget,
  ResultParts parts,
  ProjectContext candidate,
) async {
  if (!await t.applyExclude()) return _conflict(parts);
  final check = await _verify(t, o, git, budget);
  if (check.effective == SharingEffective.conflict) {
    await t.revert();
    await t.cleanup();
    parts.diagnostics.add(sharingConflict(check));
    return;
  }
  if (!await t.applyRemaining()) return _conflict(parts);
  await t.cleanup();
  _present(parts, candidate, git: check, choice: t.choice);
}

Future<SharingCheck> _verify(
  RecoveryTargets t,
  ObservedContext o,
  GitContextAdapter git,
  GitBudget budget,
) => t.choice == SharingChoice.pending
    ? Future.value(const SharingCheck(SharingEffective.pending))
    : git.verifySharing(o.git, t.choice, budget: budget);

void _present(
  ResultParts parts,
  ProjectContext? context, {
  required SharingCheck git,
  required SharingChoice choice,
}) {
  parts
    ..state = context == null ? ContextState.absent : ContextState.present
    ..freshness = context == null
        ? ContextFreshness.notApplicable
        : ContextFreshness.current
    ..context = context?.recognition
    ..sharing = ContextSharing(
      choice: choice,
      gitState: parts.sharing.gitState,
      effective: git.effective,
    );
}

void _aborted(RecoveryTargets t, ResultParts parts) {
  final hadContext = t.journal.targets.any(
    (TransactionTarget x) =>
        x.resource == TransactionResource.project && x.before != null,
  );
  parts
    ..state = hadContext ? ContextState.present : ContextState.absent
    ..diagnostics.add(
      diagnostic(
        'recovery_aborted',
        'Las fuentes cambiaron antes de publicar: se deshicieron los efectos '
            'propios y se conservó lo que había.',
      ),
    )
    ..actions.add(hadContext ? refreshAction : firstInitAction);
}

void _conflict(ResultParts parts) => parts.diagnostics.add(
  diagnostic(
    'recovery_conflict',
    'El exclude cambió desde la operación; se conserva para reconciliarlo.',
  ),
);
