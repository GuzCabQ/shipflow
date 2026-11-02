import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import '../context/state_ownership.dart';
import 'assessment_codec.dart';
import 'assessment_decisions.dart';
import 'assessment_draft.dart';
import 'assessment_freshness.dart';
import 'assessment_observe_flow.dart';
import 'assessment_preflight.dart';
import 'assessment_revalidation.dart';
import 'assessment_service.dart';
import 'assessment_store.dart';

/// `assess --show`: muestra el levantamiento guardado y comprueba su
/// vigencia volviendo a sellar sus insumos, sin detector ni escrituras. Con
/// `--previous`, la revisión anterior como historia, sin certificarla pero
/// con su correspondencia al contexto cuando cita el mismo. Un estado
/// propio que no se puede acreditar se muestra junto a la evidencia, nunca
/// como una consulta limpia. Al terminar vuelve a comprobar el contexto y
/// el documento consultados; si cambiaron, consulta una vez más, y si
/// siguen cambiando es `concurrent_change`, nunca current.
Future<AssessmentResult> showAssessmentFlow(
  AssessmentService s,
  AssessmentRequest r,
) async {
  for (var attempt = 0; ; attempt++) {
    final shown = await _showOnce(s, r);
    final draft = shown.draft;
    if (await _stable(s, shown.cited, shown.sha256)) return draft.build();
    if (attempt == 1) {
      if (draft.freshness == AssessmentFreshness.current) {
        draft.freshness = AssessmentFreshness.unverified;
      }
      draft.add('concurrent_change');
      return draft.build();
    }
  }
}

/// Una consulta: el draft y, si mostró un documento, el contexto citado y
/// la huella del documento que leyó.
typedef _Shown = ({AssessmentDraft draft, CitedContext? cited, String? sha256});

/// Si el contexto citado y el documento leído siguen con los mismos bytes,
/// sin una operación de init empezada; sin documento mostrado, no hay nada
/// que certificar. No es una instantánea atómica: es la revalidación final.
Future<bool> _stable(
  AssessmentService s,
  CitedContext? cited,
  String? sha256,
) async {
  if (cited == null || sha256 == null) return true;
  try {
    await unchangedContext(s.store, cited);
    return await AssessmentStore(s.store).hashOf(assessmentPath) == sha256;
  } on AssessmentAbort {
    return false;
  } on ContextStoreFailure {
    return false;
  }
}

Future<_Shown> _showOnce(AssessmentService s, AssessmentRequest r) async {
  final draft = AssessmentDraft(AssessmentOperation.show);
  _Shown only() => (draft: draft, cited: null, sha256: null);
  final ownership = await inspectStateOwnership(s.root);
  if (ownership.kind == StateOwnershipKind.foreign) {
    draft.add('state_occupied', examples: ownership.findings);
    return only();
  }
  final cited = await readCitedContext(s.store, draft);
  if (cited == null) return only();
  final read = await readExisting(s, cited, draft);
  final document = read?.document;
  if (draft.stopped) return only();
  if (document == null) {
    draft.add('assessment_absent');
    return only();
  }
  if (ownership.kind == StateOwnershipKind.invalid) {
    draft.add('state_invalid', examples: ownership.findings);
  }
  if (ownership.assessmentJournal) draft.add('assessment_recovery_pending');
  if (r.previous) {
    _previous(s, cited, draft, document);
  } else {
    await _current(s, r, cited, document.current, draft);
  }
  return (draft: draft, cited: cited, sha256: read!.sha256);
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

void _previous(
  AssessmentService s,
  CitedContext cited,
  AssessmentDraft draft,
  AssessmentDocument doc,
) {
  final previous = doc.previous;
  if (previous == null) {
    draft.add('previous_absent');
    return;
  }
  if (!_bound(s, cited, previous, draft)) return;
  draft
    ..outcome = AssessmentOutcome.shown
    ..present(previous)
    ..freshness = AssessmentFreshness.historical
    ..actions.add(showAction);
}

/// La revisión vigente: su vínculo exacto con el contexto citado si la
/// huella coincide, o su base no disponible si cambió; y después la
/// vigencia de sus insumos.
Future<void> _current(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  AssessmentSnapshot snapshot,
  AssessmentDraft draft,
) async {
  if (!_bound(s, cited, snapshot, draft)) return;
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
}
