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

/// El resultado de [recovery]: efectos verdaderos, también si algo falló
/// después del rename, y el levantamiento que quedó; una publicación
/// parcial recuperada no es 0.
Future<void> _report(
  AssessmentService s,
  AssessmentRecovery recovery,
  AssessmentDraft draft,
) async {
  final failure = recovery.failure;
  await _effects(s, recovery, draft);
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
      if (failure == null) draft.outcome = AssessmentOutcome.recovered;
  }
  final document = recovery.document;
  if (document == null) return _presentCurrent(s, draft);
  _present(draft, document.current);
  _retired(draft, document);
}

/// Los efectos de [recovery]; con un fallo tras el rename, los del commit,
/// su diagnóstico y la recuperación pendiente.
Future<void> _effects(
  AssessmentService s,
  AssessmentRecovery recovery,
  AssessmentDraft draft,
) async {
  final failure = recovery.failure;
  if (failure != null) return reportCommitFailure(s.store, draft, failure);
  draft
    ..created.addAll(recovery.created)
    ..removed.addAll(recovery.removed)
    ..replaced.addAll(recovery.replaced)
    ..published = recovery.published;
}

/// La revisión que [published] dejó de conservar. Assess siempre guarda
/// previous desde la revisión 2, así que la tercera en adelante retira la
/// de dos atrás. La informa también una limpieza: quien hizo el rename
/// pudo morir sin informarla.
void _retired(AssessmentDraft draft, AssessmentDocument published) {
  if (published.revision < 3) return;
  draft
    ..retiredRevision = published.revision - 2
    ..add('revision_retired');
}

/// El levantamiento que quedó tras abortar o retirar restos, leído de
/// nuevo; si esa lectura falla, el diagnóstico conserva los efectos.
Future<void> _presentCurrent(AssessmentService s, AssessmentDraft draft) async {
  final AssessmentDocument? document;
  try {
    document = (await AssessmentStore(s.store).read()).document;
  } on ContextFormatException {
    draft.add('assessment_invalid', examples: [assessmentDocumentPath]);
    return;
  } on AssessmentAbort catch (abort) {
    draft.add(abortCode(abort.code));
    return;
  } on ContextStoreFailure catch (failure) {
    draft.add(storeCode(failure));
    return;
  }
  if (document != null) _present(draft, document.current);
}

void _present(AssessmentDraft draft, AssessmentSnapshot current) {
  draft
    ..present(current)
    ..actions.add(showAction);
  if (current.coverage != AssessmentCoverage.complete) {
    draft.add('coverage_partial');
  }
}
