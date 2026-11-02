import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import '../context/state_ownership.dart';
import 'assessment_codec.dart';
import 'assessment_decisions.dart';
import 'assessment_draft.dart';
import 'assessment_freshness.dart';
import 'assessment_observe_flow.dart';
import 'assessment_preflight.dart';
import 'assessment_recovery.dart';
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
      revalidate: (candidate) => _stillValid(s, r, cited, candidate.current),
    );
  } on ContextFormatException {
    draft.add('recovery_conflict', examples: [assessmentJournalPath]);
  } on ContextStoreFailure catch (failure) {
    draft.add(storeCode(failure));
  }
  return null;
}

/// El candidato sigue citando este contexto y sus fuentes no cambiaron.
Future<void> _stillValid(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  AssessmentSnapshot candidate,
) async {
  if (candidate.contextDigest != cited.digest) {
    throw const AssessmentAbort('source_changed');
  }
  final now = await s.observeInputs(s.root, cited.context, s.limits(r.profile));
  final before = [
    for (final i in candidate.inputs)
      if (i.kind != AssessmentInputKind.context) i,
  ];
  if (changedInputs(before, now).isNotEmpty) {
    throw const AssessmentAbort('source_changed');
  }
}

/// El resultado de [recovery]: efectos verdaderos y, si queda un
/// levantamiento, el vigente; una publicación parcial recuperada no es 0.
Future<void> _report(
  AssessmentService s,
  AssessmentRecovery recovery,
  AssessmentDraft draft,
) async {
  draft
    ..removed.addAll(recovery.removed)
    ..replaced.addAll(recovery.replaced)
    ..published = recovery.published;
  switch (recovery.outcome) {
    case AssessmentRecoveryOutcome.conflict:
      draft.add('recovery_conflict', examples: recovery.kept);
      return;
    case AssessmentRecoveryOutcome.nothing:
      draft.outcome = AssessmentOutcome.unchanged;
    case AssessmentRecoveryOutcome.aborted:
      draft
        ..outcome = AssessmentOutcome.recovered
        ..add('recovery_aborted');
    case _:
      draft.outcome = AssessmentOutcome.recovered;
  }
  final current = (await AssessmentStore(s.store).read()).document?.current;
  if (current == null) return;
  draft
    ..present(current)
    ..actions.add(showAction);
  if (current.coverage != AssessmentCoverage.complete) {
    draft.add('coverage_partial');
  }
}
