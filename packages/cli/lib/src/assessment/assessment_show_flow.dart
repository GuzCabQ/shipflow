import 'package:core/core.dart';

import '../context/state_ownership.dart';
import 'assessment_decisions.dart';
import 'assessment_draft.dart';
import 'assessment_freshness.dart';
import 'assessment_observe_flow.dart';
import 'assessment_preflight.dart';
import 'assessment_service.dart';

/// `assess --show`: muestra el levantamiento guardado y comprueba su
/// vigencia volviendo a sellar sus insumos, sin detector ni escrituras. Con
/// `--previous`, la revisión anterior como historia, sin certificarla pero
/// con su correspondencia al contexto cuando cita el mismo. Un estado
/// propio que no se puede acreditar se muestra junto a la evidencia, nunca
/// como una consulta limpia.
Future<AssessmentResult> showAssessmentFlow(
  AssessmentService s,
  AssessmentRequest r,
) async {
  final draft = AssessmentDraft(AssessmentOperation.show);
  final ownership = await inspectStateOwnership(s.root);
  if (ownership.kind == StateOwnershipKind.foreign) {
    draft.add('state_occupied', examples: ownership.findings);
    return draft.build();
  }
  final cited = await readCitedContext(s.store, draft);
  if (cited == null) return draft.build();
  final read = await readExisting(s, cited, draft);
  final document = read?.document;
  if (draft.stopped) return draft.build();
  if (document == null) {
    draft.add('assessment_absent');
    return draft.build();
  }
  if (ownership.kind == StateOwnershipKind.invalid) {
    draft.add('state_invalid', examples: ownership.findings);
  }
  if (ownership.assessmentJournal) draft.add('assessment_recovery_pending');
  return r.previous
      ? _previous(s, cited, draft, document)
      : _current(s, r, cited, document.current, draft);
}

/// Con la misma huella, la correspondencia exacta con el contexto citado;
/// con otra, la base histórica no se vuelve a comprobar. False si la
/// correspondencia falla: un mapa ajeno nunca es vigente.
bool _bound(
  AssessmentService s,
  CitedContext cited,
  AssessmentSnapshot snapshot,
  AssessmentDraft draft,
) {
  if (snapshot.contextDigest != cited.digest) {
    draft.add('context_basis_unavailable');
    return true;
  }
  try {
    validateAssessmentContext(snapshot, s.basisOf(cited.context));
    return true;
  } on ContextFormatException {
    draft.add('assessment_context_mismatch', examples: [assessmentContextPath]);
    return false;
  }
}

AssessmentResult _previous(
  AssessmentService s,
  CitedContext cited,
  AssessmentDraft draft,
  AssessmentDocument doc,
) {
  final previous = doc.previous;
  if (previous == null) {
    draft.add('previous_absent');
    return draft.build();
  }
  if (!_bound(s, cited, previous, draft)) return draft.build();
  draft
    ..outcome = AssessmentOutcome.shown
    ..present(previous)
    ..freshness = AssessmentFreshness.historical
    ..actions.add(showAction);
  return draft.build();
}

/// La revisión vigente: su vínculo exacto con el contexto citado si la
/// huella coincide, o su base no disponible si cambió; y después la
/// vigencia de sus insumos.
Future<AssessmentResult> _current(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  AssessmentSnapshot snapshot,
  AssessmentDraft draft,
) async {
  if (!_bound(s, cited, snapshot, draft)) return draft.build();
  final limits = s.limits(r.profile);
  final check = await checkAssessmentFreshness(
    s.root,
    snapshot,
    limits,
    contextDigest: cited.digest,
    reobserveInputs: () => s.observeInputs(s.root, cited.context, limits),
  );
  draft
    ..outcome = AssessmentOutcome.shown
    ..present(snapshot)
    ..freshness = check.freshness
    ..diagnostics.addAll(check.diagnostics);
  if (snapshot.coverage != AssessmentCoverage.complete) {
    draft.add('coverage_partial');
  }
  if (check.freshness == AssessmentFreshness.unverified &&
      hasUnsealedInputs(snapshot)) {
    draft.actions.add(observeAction);
  }
  return draft.build();
}
