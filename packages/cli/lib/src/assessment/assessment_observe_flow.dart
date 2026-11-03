import 'dart:convert';

import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import '../context/state_ownership.dart';
import 'assessment_codec.dart';
import 'assessment_decisions.dart';
import 'assessment_draft.dart';
import 'assessment_preflight.dart';
import 'assessment_revalidation.dart';
import 'assessment_service.dart';
import 'assessment_snapshot_builder.dart';
import 'assessment_store.dart';

/// `assess`: preflight V2, observación con el detector, admisión del
/// snapshot y publicación revalidada. Sin cambios de snapshot no escribe ni
/// rota, pero tampoco afirma vigencia sin revalidar; un cambio antes del
/// commit cancela con 75 y conserva lo anterior.
Future<AssessmentResult> observeAssessmentFlow(
  AssessmentService s,
  AssessmentRequest r,
) async {
  final draft = AssessmentDraft(AssessmentOperation.observe);
  final cited = await preflightObserve(
    await s.doctor(r.profile),
    await inspectStateOwnership(s.root),
    s.store,
    draft,
  );
  if (cited == null) return draft.build();
  final existing = await readExisting(s, cited, draft);
  if (draft.stopped) return draft.build();
  final snapshot = await _observe(s, r, cited, draft);
  if (snapshot == null) return draft.build();
  final saved = existing?.document?.current;
  if (saved != null && saved.snapshotId == snapshot.snapshotId) {
    await _attempt(s, draft, () => unchangedSources(s, r, cited, snapshot));
    if (!draft.stopped) _present(draft, saved, AssessmentOutcome.unchanged);
    return draft.build();
  }
  await _publish(s, r, cited, existing, snapshot, draft);
  return draft.build();
}

/// El documento vigente, si lo hay y es del proyecto citado.
Future<AssessmentRead?> readExisting(
  AssessmentService s,
  CitedContext cited,
  AssessmentDraft draft,
) async {
  final AssessmentRead read;
  try {
    read = await AssessmentStore(s.store).read();
  } on ContextFormatException {
    draft.add('assessment_invalid', examples: [assessmentDocumentPath]);
    return null;
  } on AssessmentAbort catch (abort) {
    draft.add(abort.code);
    return null;
  } on ContextStoreFailure catch (failure) {
    draft.add(storeCode(failure));
    return null;
  }
  final document = read.document;
  if (document != null && document.projectId != cited.context.projectId) {
    draft.add('project_identity', examples: [assessmentDocumentPath]);
  }
  return read;
}

/// El snapshot de esta observación, si el detector produjo uno coherente
/// con el contexto citado y cabe entero.
Future<AssessmentSnapshot?> _observe(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  AssessmentDraft draft,
) async {
  final limits = s.limits(r.profile);
  final observation = await s.observe(s.root, cited.context, limits);
  if (observation.files.length > maxAssessmentFiles) {
    draft.add('assessment_limit');
    return null;
  }
  final AssessmentSnapshot snapshot;
  try {
    snapshot = assembleSnapshot(
      observation: observation,
      contextDigest: cited.digest,
      profile: r.profile,
      producer: _producer(s),
      observedAt: observedAtOf(s.now()),
    );
    verifyIdentities(snapshot);
  } on ContextFormatException {
    draft.add('unexpected');
    return null;
  }
  if (!_corresponds(s, cited, snapshot, draft)) return null;
  final size = utf8.encode(canonicalAssessmentJson(snapshot.toJson())).length;
  if (size > limits.maxSnapshotBytes) {
    draft.add('assessment_limit');
    return null;
  }
  return snapshot;
}

/// Si lo sellado corresponde al contexto citado; si no, algo cambió
/// después del preflight, que no es un defecto de Shipflow.
bool _corresponds(
  AssessmentService s,
  CitedContext cited,
  AssessmentSnapshot snapshot,
  AssessmentDraft draft,
) {
  try {
    validateAssessmentContext(snapshot, s.basisOf(cited.context));
    return true;
  } on ContextFormatException {
    draft.add('source_changed');
    return false;
  }
}

AssessmentProducer _producer(AssessmentService s) => AssessmentProducer(
  version: s.version,
  contract: s.producer.contract,
  pluginId: s.producer.pluginId,
  parserVersion: s.producer.parserVersion,
);

Future<void> _publish(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  AssessmentRead? existing,
  AssessmentSnapshot snapshot,
  AssessmentDraft draft,
) async {
  final previous = existing?.document;
  final document = AssessmentDocument(
    projectId: cited.context.projectId,
    revision: (previous?.revision ?? 0) + 1,
    current: snapshot,
    previous: previous?.current,
  );
  final publication = await _attempt(s, draft, () {
    return AssessmentStore(s.store).publish(
      document,
      operationId: s.newId(),
      expectedSha256: existing?.sha256,
      baseContextDigest: cited.digest,
      preconditions: () => unchangedContext(s.store, cited),
      revalidate: () => unchangedSources(s, r, cited, snapshot),
    );
  });
  if (publication == null) {
    // Publicado aunque algo falló después: también se informa lo retirado.
    if (draft.published) _history(draft, previous, snapshot);
    return;
  }
  draft
    ..created.addAll(publication.created)
    ..replaced.addAll(publication.replaced)
    ..published = publication.published;
  _present(draft, snapshot, AssessmentOutcome.saved);
  _history(draft, previous, snapshot);
}

/// [run] (una publicación o una revalidación), con cada aborto o fallo
/// del almacén como su diagnóstico.
Future<T?> _attempt<T>(
  AssessmentService s,
  AssessmentDraft draft,
  Future<T> Function() run,
) async {
  try {
    return await run();
  } on AssessmentAbort catch (abort) {
    draft.add(abortCode(abort.code));
  } on AssessmentCommitFailure catch (failure) {
    await reportCommitFailure(s.store, draft, failure);
  } on ContextFormatException catch (rejected) {
    draft.add(rejected.code == 'too_large' ? 'assessment_limit' : 'unexpected');
  } on ContextStoreFailure catch (failure) {
    await reportStoreFailure(s.store, draft, failure);
  }
  return null;
}

/// Publicado aunque falló después: los efectos son verdaderos y el journal
/// que quedó es una recuperación pendiente.
Future<void> reportCommitFailure(
  ContextStore store,
  AssessmentDraft draft,
  AssessmentCommitFailure failure,
) async {
  draft
    ..outcome = AssessmentOutcome.failed
    ..created.addAll(failure.publication.created)
    ..replaced.addAll(failure.publication.replaced)
    ..published = failure.publication.published
    ..add(failure.code == 'busy' ? 'busy' : 'io_failure');
  if (await _journalLeft(store)) draft.add('assessment_recovery_pending');
}

/// Un fallo del almacén sin publicación; el journal que quedó es una
/// recuperación pendiente.
Future<void> reportStoreFailure(
  ContextStore store,
  AssessmentDraft draft,
  ContextStoreFailure failure,
) async {
  draft.add(storeCode(failure));
  if (await _journalLeft(store)) draft.add('assessment_recovery_pending');
}

Future<bool> _journalLeft(ContextStore store) async {
  try {
    return await store.readRelative(assessmentJournalPath, maxBytes: 1) != null;
  } on ContextStoreFailure {
    return true;
  }
}

/// La comparación con la revisión anterior y la revisión que deja de
/// conservarse; ninguna retira significado.
void _history(
  AssessmentDraft draft,
  AssessmentDocument? previous,
  AssessmentSnapshot snapshot,
) {
  if (previous == null) return;
  draft.comparison = compareAssessments(previous.current, snapshot);
  if (draft.comparison == null) draft.add('comparison_unavailable');
  if (previous.previous != null) {
    draft.retiredRevision = previous.revision - 1;
    draft.add('revision_retired');
  }
}

/// [snapshot] como resultado de [outcome]: vigente salvo que tenga entradas
/// que no se sellaron, y con su cobertura.
void _present(
  AssessmentDraft draft,
  AssessmentSnapshot snapshot,
  AssessmentOutcome outcome,
) {
  draft
    ..outcome = outcome
    ..present(snapshot)
    ..freshness = hasUnsealedInputs(snapshot)
        ? AssessmentFreshness.unverified
        : AssessmentFreshness.current
    ..actions.add(showAction);
  if (draft.freshness == AssessmentFreshness.unverified) {
    draft.add('assessment_unverified');
  }
  if (snapshot.coverage != AssessmentCoverage.complete) {
    draft.add('coverage_partial');
  }
}

/// Si alguna entrada no se pudo sellar: entonces nunca es current.
bool hasUnsealedInputs(AssessmentSnapshot snapshot) => snapshot.inputs.any(
  (i) =>
      i.state == AssessmentInputState.unreadable ||
      i.state == AssessmentInputState.limit,
);

String abortCode(String code) => switch (code) {
  'recovery_pending' => 'assessment_recovery_pending',
  final other => other,
};

String storeCode(ContextStoreFailure failure) => switch (failure.code) {
  'busy' => 'busy',
  'concurrent_change' => 'concurrent_change',
  _ => 'io_failure',
};
