import 'package:core/core.dart';

import '../context/state_layout.dart';
import 'basis_candidate.dart';
import 'basis_catalog.dart';
import 'basis_codec.dart';
import 'basis_commit.dart';
import 'basis_flow.dart';
import 'basis_preconditions.dart';
import 'basis_reply.dart';
import 'basis_service.dart';

/// `--accept <huella>`: sólo el borrador exacto, con su actor declarado, si
/// la base, el contexto y las fuentes siguen como al prepararlo. Publica
/// bajo el lock de contexto: staging, journal con la aceptación,
/// revalidación, rename atómico y limpieza de lo propio.
Future<void> acceptBasis(BasisService s, BasisReply r, String digest) async {
  final files = s.files;
  final basis = await files.basis();
  r.basis = basis.integrity;
  if (!usable(r, basis, basisDocumentPath)) return;
  if (!await journalAbsent(s, r)) return;
  final draft = await files.draft();
  r.draft = draft.integrity;
  if (!usable(r, draft, basisDraftPath)) return;
  final value = draft.value;
  if (value == null || value.digest != digest) {
    return _notThisDraft(s, r, basis.value, value, digest);
  }
  if (!contextReady(await s.readProject(), r)) return;
  await files.locked(() => _accept(s, r, value, draft.bytesDigest!));
}

/// Una huella que no es el borrador actual: ya aplicada si la historia de
/// una base de este proyecto, con su contexto listo, la contiene; si no,
/// conflicto con el borrador que hay, o inexistente.
Future<void> _notThisDraft(
  BasisService s,
  BasisReply r,
  BasisDocument? basis,
  BasisDraft? draft,
  String digest,
) async {
  if (basis != null && eventOfDraft(basis, digest) != null) {
    if (!await boundToProject(s, r, basis, null)) return;
    r
      ..outcome = BasisOutcome.alreadyApplied
      ..basisDigest = basis.digest
      ..draftDigest = digest
      ..addAction(showAction);
    await present(s, r, replayBasisLedger(basis));
    return;
  }
  if (draft != null) {
    r
      ..add('draft_conflict', path: basisDraftPath)
      ..addAction(showDraftAction);
    return;
  }
  r.add(
    'invalid_reference',
    path: basisDraftPath,
    message: 'No hay un borrador con esa huella.',
  );
}

/// Las precondiciones que ya no se cumplirán para este borrador: sólo
/// queda descartarlo y preparar otro.
const _stale = {'base_changed', 'source_changed'};

Future<void> _accept(
  BasisService s,
  BasisReply r,
  BasisDraft draft,
  String draftFile,
) async {
  final basis = await s.files.basis();
  if (!usable(r, basis, basisDocumentPath)) return;
  if (!await journalAbsent(s, r)) return;
  if (!await _stillTheDraft(s, r, basis.value, draft, draftFile)) return;
  final failure = await recheck(s, draft, basis.value?.digest, sources: false);
  if (failure != null) return _refused(r, draft, failure);
  final candidate = buildCandidate(
    basis.value,
    draft,
    acceptedAt: basisTimestamp(s.now()),
    producer: s.version,
  );
  if (!_fits(s, r, candidate)) return;
  await stageAndPublish(s, r, draft, candidate, basis.bytesDigest, draftFile);
}

/// Una precondición que ya no se cumple: no se publica y, si no se
/// cumplirá nunca para este borrador, se ofrece descartarlo.
void _refused(BasisReply r, BasisDraft draft, BasisDiagnostic failure) {
  r.add(failure.code, path: failure.path, message: failure.message);
  if (_stale.contains(failure.code)) r.addAction(discardAction(draft.digest));
}

/// Bajo el lock, el borrador sigue siendo exactamente el leído: uno
/// descartado, revisado o ya aceptado entre medio no se publica.
Future<bool> _stillTheDraft(
  BasisService s,
  BasisReply r,
  BasisDocument? basis,
  BasisDraft draft,
  String draftFile,
) async {
  final now = await s.files.draft();
  r.draft = now.integrity;
  if (!usable(r, now, basisDraftPath)) return false;
  if (now.value?.digest == draft.digest && now.bytesDigest == draftFile) {
    return true;
  }
  await _notThisDraft(s, r, basis, now.value, draft.digest);
  return false;
}

/// Si no hay un journal de bootstrap; si lo hay, la publicación pendiente
/// se termina con recover, nunca con otra aceptación.
Future<bool> journalAbsent(BasisService s, BasisReply r) async {
  final journal = await s.files.journal();
  r.transaction = journal.integrity;
  if (journal.absent) return true;
  if (!usable(r, journal, basisTransactionPath)) return false;
  r
    ..add('recovery_required', path: basisTransactionPath)
    ..addAction(recoverAction);
  return false;
}

/// La primera precondición de [draft] que ya no se cumple, con el
/// proyecto releído ahora. Sin [sources] no se leen fuentes: se leen una
/// sola vez, con el journal escrito y bajo el lock.
Future<BasisDiagnostic?> recheck(
  BasisService s,
  BasisDraft draft,
  String? currentBasisDigest, {
  bool sources = true,
}) async => checkBasisPreconditions(
  BasisPreconditions(
    state: await s.readProject(),
    projectId: draft.projectId,
    currentBasisDigest: currentBasisDigest,
    expectedBasisDigest: draft.expectedBasisDigest,
    contextProjectDigest: draft.contextProjectDigest,
    sourceReads: sources ? draft.sourceReads : const [],
    sources: s.sources,
  ),
);

bool _fits(BasisService s, BasisReply r, BasisDocument candidate) {
  final fits =
      encodeBasis(candidate).length <= s.limits.maxBasisBytes &&
      candidate.revision <= s.limits.maxEvents &&
      replayBasis(candidate).length <= s.limits.maxCurrentRecords;
  if (!fits) r.add('budget_exceeded', path: basisDocumentPath);
  return fits;
}

/// Staging completo, journal con la aceptación exacta, revalidación bajo
/// el lock —la única lectura de fuentes antes de publicar— y después el
/// rename. Un cambio entre medio retira sólo lo propio y conserva la base
/// y el borrador.
Future<void> stageAndPublish(
  BasisService s,
  BasisReply r,
  BasisDraft draft,
  BasisDocument candidate,
  String? before,
  String draftFile,
) async {
  final files = s.files;
  final bytes = encodeBasis(candidate);
  final journal = journalFor(draft, candidate, before, bytes);
  await files.store.createDirectory(stagingOf(draft.operationId));
  await files.publish(journal.candidatePath, bytes, null);
  await files.publish(
    basisTransactionPath,
    encodeBasisTransaction(journal),
    null,
  );
  final failure = await recheck(s, draft, (await files.basis()).value?.digest);
  if (failure != null ||
      !await supported(s, r, draft.preparedChanges, candidate)) {
    await abortOwn(s, journal);
    if (failure != null) _refused(r, draft, failure);
    return;
  }
  await finishPublication(s, r, journal, bytes, candidate.digest);
  if (r.published) await present(s, r, replayBasisLedger(candidate));
  r
    ..draftDigest = draft.digest
    ..actor = draft.input.actor
    ..reason = draft.input.reason;
}
