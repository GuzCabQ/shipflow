import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import '../context/state_ownership.dart';
import 'assessment_codec.dart';
import 'assessment_decisions.dart';
import 'assessment_draft.dart';
import 'assessment_observe_flow.dart';
import 'assessment_preflight.dart';
import 'assessment_recovery.dart';
import 'assessment_revalidation.dart';
import 'assessment_service.dart';
import 'assessment_store.dart';

/// `assess --recover`: termina o aborta sólo una publicación propia
/// demostrable. Una operación de init sin terminar la remite a
/// `init --recover`; las dos activas son un conflicto que no se resuelve
/// adivinando su orden.
Future<AssessmentResult> recoverAssessmentFlow(
  AssessmentService s,
  AssessmentRequest r,
) async {
  final draft = AssessmentDraft(AssessmentOperation.recover);
  final ownership = await inspectStateOwnership(s.root);
  if (await _contextJournal(s.store)) {
    draft.add(
      ownership.assessmentJournal
          ? 'recovery_conflict'
          : 'context_recovery_pending',
    );
    return draft.build();
  }
  final cited = await readCitedContext(s.store, draft);
  if (cited == null) return draft.build();
  final layout = await observeStateLayout(s.root);
  final recovery = await _run(s, r, cited, layout, draft);
  if (recovery == null) return draft.build();
  await _report(s, recovery, draft);
  return draft.build();
}

Future<bool> _contextJournal(ContextStore store) async =>
    await store.readRelative(transactionPath, maxBytes: 1) != null;

Future<AssessmentRecovery?> _run(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  Object layout,
  AssessmentDraft draft,
) async {
  try {
    return await recoverAssessment(
      AssessmentStore(s.store),
      projectId: cited.context.projectId,
      candidates: layout is ObservedLayout ? layout.assessmentCandidates : [],
      temporaries: layout is ObservedLayout
          ? layout.assessmentTemporaries
          : const [],
      revalidate: (candidate) => _stillValid(s, r, cited, candidate.current),
    );
  } on AssessmentCommitFailure catch (failure) {
    await reportCommitFailure(s.store, draft, failure);
  } on ContextFormatException {
    draft.add('recovery_conflict', examples: [assessmentJournalPath]);
  } on ContextStoreFailure catch (failure) {
    await reportStoreFailure(s.store, draft, failure);
  }
  return null;
}

/// Bajo el lock: el candidato cita este contexto, que se vuelve a leer, le
/// corresponde exactamente (si no, no es propio: conflicto) y sus fuentes
/// se confirman ahora.
Future<void> _stillValid(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  AssessmentSnapshot candidate,
) async {
  if (candidate.contextDigest != cited.digest) {
    throw const AssessmentAbort('source_changed');
  }
  validateAssessmentContext(candidate, s.basisOf(cited.context));
  await unchangedSources(s, r, cited, candidate);
}

/// El resultado de [recovery]: efectos verdaderos y, si queda un
/// levantamiento, el vigente; una publicación parcial recuperada no es 0.
Future<void> _report(
  AssessmentService s,
  AssessmentRecovery recovery,
  AssessmentDraft draft,
) async {
  draft
    ..created.addAll(recovery.created)
    ..removed.addAll(recovery.removed)
    ..replaced.addAll(recovery.replaced)
    ..published = recovery.published;
  switch (recovery.outcome) {
    case AssessmentRecoveryOutcome.conflict:
      draft.add('recovery_conflict', examples: recovery.kept);
      return;
    case AssessmentRecoveryOutcome.nothing:
      // Nada que recuperar no hereda el código del levantamiento guardado.
      draft
        ..outcome = AssessmentOutcome.unchanged
        ..actions.add(showAction);
      return;
    case AssessmentRecoveryOutcome.aborted:
      draft
        ..outcome = AssessmentOutcome.recovered
        ..add('recovery_aborted');
    case _:
      draft.outcome = AssessmentOutcome.recovered;
  }
  await _presentCurrent(s, draft);
}

/// El levantamiento que quedó tras recuperar; uno parcial no es 0.
Future<void> _presentCurrent(AssessmentService s, AssessmentDraft draft) async {
  final current = (await AssessmentStore(s.store).read()).document?.current;
  if (current == null) return;
  draft
    ..present(current)
    ..actions.add(showAction);
  if (current.coverage != AssessmentCoverage.complete) {
    draft.add('coverage_partial');
  }
}
