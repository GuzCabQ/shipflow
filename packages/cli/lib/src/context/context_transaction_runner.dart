import 'dart:convert';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_assessment.dart';
import 'context_codec.dart';
import 'context_decisions.dart';
import 'context_observation.dart';
import 'context_publication_plan.dart';
import 'context_result.dart';
import 'context_transaction_steps.dart';
import 'secure_context_store.dart';
import 'state_layout.dart';

/// Cómo terminó una publicación: sin diagnósticos es éxito.
final class TransactionResult {
  TransactionResult(this.diagnostics, {this.journalLeft = false, this.sharing});

  final List<ContextDiagnostic> diagnostics;
  final bool journalLeft;

  /// La modalidad comprobada después de aplicarla, si se comprobó.
  final SharingEffective? sharing;

  bool get ok => diagnostics.isEmpty;
}

/// Publica [plan] bajo un lease breve: andamiaje, lease, revalidación de
/// huellas e insumos, journal, staging, exclude y su comprobación, settings,
/// copia anterior, contexto y limpieza de lo propio. Un fallo después del
/// journal lo deja, con sus efectos, para `init --recover`.
Future<TransactionResult> runTransaction({
  required PublicationPlan plan,
  required ContextStore store,
  required GitContextAdapter git,
  required GitBudget budget,
  required EffectsLog effects,
  required Future<bool> Function() sourcesUnchanged,
}) async {
  final steps = TransactionSteps(plan, store, effects);
  try {
    await steps.scaffold();
  } on ContextStoreFailure catch (failure) {
    return TransactionResult([storeDiagnostic(failure)]);
  }
  final ContextLease lease;
  try {
    lease = await store.acquirePublication([
      store.contextLock(),
      if (plan.exclude case final exclude?) exclude.admin.directoryLock(),
    ]);
  } on ContextStoreFailure catch (failure) {
    return TransactionResult([storeDiagnostic(failure)]);
  }
  try {
    return await _underLease(steps, plan, git, budget, sourcesUnchanged);
  } on ContextStoreFailure catch (failure) {
    steps.leaveTransient();
    return TransactionResult([
      storeDiagnostic(failure),
      if (steps.journalWritten) _pending(),
    ], journalLeft: steps.journalWritten);
  } finally {
    await lease.release();
  }
}

Future<TransactionResult> _underLease(
  TransactionSteps steps,
  PublicationPlan plan,
  GitContextAdapter git,
  GitBudget budget,
  Future<bool> Function() sourcesUnchanged,
) async {
  if (!await steps.unchangedSince() ||
      (plan.project != null && !await sourcesUnchanged())) {
    return TransactionResult([
      diagnostic(
        'concurrent_change',
        'Cambió algo durante la preparación; no se publicó nada.',
      ),
    ]);
  }
  await steps.writeJournal(TransactionPhase.prepared);
  await steps.stage();
  final sharing = await _applySharing(steps, plan, git, budget);
  if (sharing.effective == SharingEffective.conflict) {
    await steps.revertExclude();
    await steps.cleanup();
    return TransactionResult([sharingConflict(sharing)]);
  }
  await steps.publishSettings();
  await steps.publishPrevious();
  await steps.publishProject();
  await steps.cleanup();
  return TransactionResult(const [], sharing: sharing.effective);
}

Future<SharingCheck> _applySharing(
  TransactionSteps steps,
  PublicationPlan plan,
  GitContextAdapter git,
  GitBudget budget,
) async {
  if (plan.exclude?.patch.changed ?? false) {
    await steps.publishExclude();
    await steps.writeJournal(TransactionPhase.sharingApplied);
  }
  if (plan.choice == SharingChoice.pending) {
    return const SharingCheck(SharingEffective.pending);
  }
  return git.verifySharing(plan.observed.git, plan.choice, budget: budget);
}

ContextDiagnostic _pending() => diagnostic(
  'recovery_pending',
  'La operación quedó a medias; init --recover la termina o la deshace.',
  transactionPath,
);

/// El diagnóstico de un fallo del almacén.
ContextDiagnostic storeDiagnostic(ContextStoreFailure failure) =>
    switch (failure.code) {
      'busy' => diagnostic(
        'busy',
        'Otra operación de Shipflow está publicando; vuelve a intentarlo.',
      ),
      'concurrent_change' => diagnostic(
        'concurrent_change',
        'Un archivo cambió durante la operación; no se sobrescribió.',
      ),
      _ => diagnostic(
        'io_failure',
        'No se pudo leer o escribir un archivo propio (${failure.code}).',
      ),
    };

/// Los bytes de disco de [settings].
List<int> settingsBytes(LocalSettings settings) =>
    const ContextCodec().encodeSettings(settings);

/// Si [bytes] coinciden con lo observado de [read].
bool sameBytes(DocumentRead<Object> read, List<int> bytes) =>
    read.present && utf8.decode(read.bytes!) == utf8.decode(bytes);
