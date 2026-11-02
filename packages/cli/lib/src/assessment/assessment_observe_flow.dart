import 'dart:convert';

import 'package:core/core.dart';

import '../context/context_codec.dart';
import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import '../context/state_ownership.dart';
import 'assessment_codec.dart';
import 'assessment_decisions.dart';
import 'assessment_draft.dart';
import 'assessment_freshness.dart';
import 'assessment_preflight.dart';
import 'assessment_service.dart';
import 'assessment_snapshot_builder.dart';
import 'assessment_store.dart';

/// `assess`: preflight V2, observación con el detector, admisión del
/// snapshot y publicación revalidada. Sin cambios de snapshot no escribe ni
/// rota; un cambio antes del commit cancela con 75 y conserva lo anterior.
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
    _present(draft, saved, AssessmentOutcome.unchanged);
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
    validateAssessmentContext(snapshot, s.basisOf(cited.context));
  } on ContextFormatException {
    draft.add('unexpected');
    return null;
  }
  final size = utf8.encode(canonicalAssessmentJson(snapshot.toJson())).length;
  if (size > limits.maxSnapshotBytes) {
    draft.add('assessment_limit');
    return null;
  }
  return snapshot;
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
  if (publication == null) return;
  draft
    ..created.addAll(publication.created)
    ..replaced.addAll(publication.replaced)
    ..published = publication.published;
  _present(draft, snapshot, AssessmentOutcome.saved);
  _history(draft, previous, snapshot);
}

/// [publish], con cada aborto o fallo del almacén como su diagnóstico; un
/// journal que quedó se informa como recuperación pendiente.
Future<AssessmentPublication?> _attempt(
  AssessmentService s,
  AssessmentDraft draft,
  Future<AssessmentPublication> Function() publish,
) async {
  try {
    return await publish();
  } on AssessmentAbort catch (abort) {
    draft.add(abortCode(abort.code));
  } on ContextFormatException {
    draft.add('assessment_limit');
  } on ContextStoreFailure catch (failure) {
    draft.add(storeCode(failure));
    if (await _journalLeft(s.store)) draft.add('assessment_recovery_pending');
  }
  return null;
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

/// El contexto citado sigue con sus bytes y no hay una operación de init
/// sin terminar.
Future<void> unchangedContext(ContextStore store, CitedContext cited) async {
  final bytes = await store.readRelative(
    projectPath,
    maxBytes: maxProjectBytes,
  );
  if (bytes == null || sha256Of(bytes) != cited.digest) {
    throw const AssessmentAbort('concurrent_change');
  }
  if (await store.readRelative(transactionPath, maxBytes: 1) != null) {
    throw const AssessmentAbort('context_recovery_pending');
  }
}

/// Las fuentes vuelven a sellarse igual que en [snapshot]; si no, el
/// origen cambió durante la operación.
Future<void> unchangedSources(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  AssessmentSnapshot snapshot,
) async {
  await unchangedContext(s.store, cited);
  final now = await s.observeInputs(s.root, cited.context, s.limits(r.profile));
  final before = [
    for (final i in snapshot.inputs)
      if (i.kind != AssessmentInputKind.context) i,
  ];
  if (changedInputs(before, now).isNotEmpty) {
    throw const AssessmentAbort('source_changed');
  }
}

String abortCode(String code) => switch (code) {
  'recovery_pending' => 'assessment_recovery_pending',
  final other => other,
};

String storeCode(ContextStoreFailure failure) => switch (failure.code) {
  'busy' => 'busy',
  'concurrent_change' => 'concurrent_change',
  _ => 'io_failure',
};
