import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_assessment.dart';
import 'context_foreign_journals.dart';
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
  if (o.ownership.basisJournal || o.ownership.assessmentJournal) {
    if (journal == null) _withoutJournal(o, parts);
    remitForeignJournals(o.ownership, parts, bothActive: journal != null);
    return resultOf(parts, effects.freeze(budget.started));
  }
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

ResultParts _parts(ObservedContext o) =>
    ResultParts(
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
      )
      ..basis = o.ownership.basis
      ..basisTransaction = o.ownership.basisTransaction;

void _withoutJournal(ObservedContext o, ResultParts parts) {
  if (o.journal.present) return parts.diagnostics.add(_journalInvalid());
  final (:state, :diagnostics) = stateOf(o);
  parts
    ..state = state
    ..success = ContextOutcome.unchanged
    ..diagnostics.addAll(diagnostics);
  if (state == ContextState.present) {
    final (:freshness, diagnostics: fresh) = freshnessOf(o, state);
    parts
      ..freshness = freshness
      ..context = o.project.value?.recognition
      ..diagnostics.addAll(fresh);
  }
  if (state == ContextState.absent && diagnostics.isEmpty) {
    parts.diagnostics.add(
      diagnostic('not_initialized', 'No hay una operación ni un contexto.'),
    );
    parts.actions.add(firstInitAction);
  }
}

ContextDiagnostic _journalInvalid() => diagnostic(
  'journal_invalid',
  'El registro de la operación no cumple su formato; se conserva para '
      'reconciliarlo a mano.',
  transactionPath,
);

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
  if (!await t.completable()) return _incomplete(t, parts);
  if (await t.projectPublished()) {
    return _finishPublished(t, o, git, budget, parts);
  }
  final candidate = t.candidate();
  if (candidate == null ||
      digestOf(candidate.recognition) != _currentDigest(o)) {
    if (!await t.revert()) return _conflict(parts);
    await t.cleanup();
    return _aborted(t, parts, _sourcesChanged);
  }
  await _finishPending(t, o, git, budget, parts, candidate);
}

const _sourcesChanged =
    'Las fuentes cambiaron antes de publicar: se deshicieron los efectos '
    'propios y se conservó lo que había.';

/// Un destino pendiente sin su versión preparada: la operación no se puede
/// terminar y se deshace. Un contexto ya publicado no se revierte, así que
/// entonces queda para reconciliarlo a mano.
Future<void> _incomplete(RecoveryTargets t, ResultParts parts) async {
  final published = t.journal.targets.any(
    (x) => x.resource == TransactionResource.project,
  );
  if (published && await t.projectPublished()) return _conflict(parts);
  if (!await t.revert()) return _conflict(parts);
  await t.cleanup();
  _aborted(
    t,
    parts,
    'La operación se interrumpió antes de preparar todos sus archivos: se '
    'deshicieron los efectos propios y se conservó lo que había.',
  );
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
  final check = await _verify(t, o, git, budget);
  _present(parts, published, git: check, choice: t.choice);
  parts.diagnostics.addAll(_uncorroborated(check, t.choice));
  if (published == null) return;
  final (:freshness, :diagnostics) = freshnessOf(
    o,
    ContextState.present,
    saved: published,
  );
  parts
    ..freshness = freshness
    ..diagnostics.addAll(diagnostics);
  if (freshness == ContextFreshness.stale) parts.actions.add(refreshAction);
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
  if (_uncorroborated(check, t.choice).isNotEmpty &&
      check.effective != SharingEffective.conflict) {
    parts.diagnostics.addAll(_uncorroborated(check, t.choice));
    return;
  }
  if (check.effective == SharingEffective.conflict) {
    if (!await t.revert()) return _conflict(parts);
    await t.cleanup();
    parts.diagnostics.add(sharingConflict(check));
    return;
  }
  if (!await t.applyRemaining()) return _conflict(parts);
  await t.cleanup();
  _present(parts, candidate, git: check, choice: t.choice);
}

/// Lo que impide afirmar la modalidad del journal: un conflicto, o no poder
/// comprobar una elección que no está pendiente.
List<ContextDiagnostic> _uncorroborated(
  SharingCheck check,
  SharingChoice choice,
) => switch (check.effective) {
  SharingEffective.conflict => [sharingConflict(check)],
  SharingEffective.unverified when choice != SharingChoice.pending => [
    diagnostic(
      'git_unavailable',
      'No se pudo comprobar la elección con Git; la operación queda '
          'pendiente hasta poder corroborarla.',
    ),
  ],
  _ => const [],
};

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

void _aborted(RecoveryTargets t, ResultParts parts, String message) {
  final hadContext =
      t.o.project.present ||
      t.journal.targets.any(
        (TransactionTarget x) =>
            x.resource == TransactionResource.project && x.before != null,
      );
  parts
    ..state = hadContext ? ContextState.present : ContextState.absent
    ..diagnostics.add(diagnostic('recovery_aborted', message))
    ..actions.add(switch (t.journal.operation) {
      TransactionOperation.sharing => _repeatSharing(t.choice),
      _ => hadContext ? refreshAction : firstInitAction,
    });
}

/// La misma elección otra vez, ahora sin la operación interrumpida.
ContextNextAction _repeatSharing(SharingChoice choice) =>
    sharingActions().firstWhere(
      (a) => a.arguments.single == '--sharing=${choice.toWireName()}',
    );

void _conflict(ResultParts parts) => parts.diagnostics.add(
  diagnostic(
    'recovery_conflict',
    'Un archivo propio no se puede llevar exactamente a su versión anterior '
        'ni a la preparada; se conserva todo para reconciliarlo a mano.',
  ),
);
