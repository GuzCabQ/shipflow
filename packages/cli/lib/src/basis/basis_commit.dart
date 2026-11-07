import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import 'basis_canonical.dart';
import 'basis_candidate.dart';
import 'basis_catalog.dart';
import 'basis_codec.dart';
import 'basis_reply.dart';
import 'basis_service.dart';
import 'basis_store.dart';

/// El directorio de staging de una operación.
String stagingOf(String operationId) => basisStagingOf(operationId);

/// El journal preparado de la aceptación de [draft]: before/after son las
/// huellas de los bytes de basis.json, y el candidato vive en la ruta que
/// deriva su operación.
BasisTransaction journalFor(
  BasisDraft draft,
  BasisDocument candidate,
  String? before,
  List<int> bytes,
) => sealTransaction(
  BasisTransaction(
    projectId: draft.projectId,
    operationId: draft.operationId,
    phase: BasisTransactionPhase.prepared,
    before: before,
    after: bytesDigest(bytes),
    acceptedDraftDigest: draft.digest,
    acceptedAt: candidate.events.last.acceptedAt,
    actor: draft.input.actor,
    contextProjectDigest: draft.contextProjectDigest,
    sourceReads: draft.sourceReads,
    candidatePath: basisCandidatePath(draft.operationId),
    digest: 'sha256:${'0' * 64}',
  ),
);

/// El rename atómico con CAS sobre before y, ya publicado, la limpieza.
/// El rename hecho demuestra la publicación: si falla su confirmación o
/// algo después, la respuesta conserva que se publicó y la recuperación
/// pendiente; nunca se basa sólo en una relectura que puede fallar.
Future<void> finishPublication(
  BasisService s,
  BasisReply r,
  BasisTransaction journal,
  List<int> bytes,
  String basisDigest,
) async {
  final files = s.files;
  try {
    await files.publish(basisDocumentPath, bytes, journal.before);
  } on ContextStoreFailure catch (failure) {
    if (!failure.replaced && !await _holds(files, journal.after)) rethrow;
    _published(r, basisDigest);
    _pending(r, failure);
    return;
  }
  _published(r, basisDigest);
  try {
    await settle(s, r, journal);
  } on ContextStoreFailure catch (failure) {
    _pending(r, failure);
  }
}

void _published(BasisReply r, String basisDigest) => r
  ..published = true
  ..outcome = BasisOutcome.published
  ..basisDigest = basisDigest
  ..basis = BasisIntegrity.valid
  ..changedFiles.add(basisDocumentPath);

void _pending(BasisReply r, ContextStoreFailure failure) => r
  ..add(failure.code == 'busy' ? 'busy' : 'io_error')
  ..add('recovery_required', path: basisTransactionPath)
  ..addAction(recoverAction);

/// Si basis.json tiene [digest] ahora; una relectura fallida no lo prueba.
Future<bool> _holds(BasisStore files, String digest) async {
  try {
    return await files.digestOf(
          basisDocumentPath,
          files.limits.maxBasisBytes,
        ) ==
        digest;
  } on ContextStoreFailure {
    return false;
  }
}

/// Tras publicar: el journal en fase publicada y después sólo lo propio
/// comprobado: el candidato con la huella after, su staging, el borrador
/// aceptado (nunca uno que otro proceso cambió) y el journal.
Future<void> settle(
  BasisService s,
  BasisReply r,
  BasisTransaction journal,
) async {
  final files = s.files;
  final current = await files.digestOf(
    basisTransactionPath,
    s.limits.maxDraftBytes,
  );
  if (journal.phase == BasisTransactionPhase.prepared && current != null) {
    final published = sealTransaction(_phase(journal));
    await files.publish(
      basisTransactionPath,
      encodeBasisTransaction(published),
      current,
    );
  }
  await _removeOwn(s, r, journal, removeDraft: true);
}

BasisTransaction _phase(BasisTransaction j) => BasisTransaction(
  projectId: j.projectId,
  operationId: j.operationId,
  phase: BasisTransactionPhase.published,
  before: j.before,
  after: j.after,
  acceptedDraftDigest: j.acceptedDraftDigest,
  acceptedAt: j.acceptedAt,
  actor: j.actor,
  contextProjectDigest: j.contextProjectDigest,
  sourceReads: j.sourceReads,
  candidatePath: j.candidatePath,
  digest: j.digest,
);

/// Antes de publicar: retira el candidato, su staging y el journal
/// propios. La base y el borrador quedan como estaban.
Future<void> abortOwn(
  BasisService s,
  BasisTransaction journal, {
  BasisReply? reply,
  bool removeDraft = false,
}) => _removeOwn(s, reply, journal, removeDraft: removeDraft);

Future<void> _removeOwn(
  BasisService s,
  BasisReply? r,
  BasisTransaction journal, {
  required bool removeDraft,
}) async {
  final files = s.files;
  final candidate = await files.digestOf(
    journal.candidatePath,
    s.limits.maxBasisBytes,
  );
  if (candidate == journal.after) {
    await files.remove(journal.candidatePath, candidate!);
  }
  if (candidate == null || candidate == journal.after) {
    await files.store.removeDirectory(stagingOf(journal.operationId));
  }
  if (removeDraft) await _removeDraft(s, r, journal.acceptedDraftDigest);
  final current = await files.digestOf(
    basisTransactionPath,
    s.limits.maxDraftBytes,
  );
  if (current != null) await files.remove(basisTransactionPath, current);
}

/// Retira el borrador sólo si es exactamente el aceptado.
Future<void> _removeDraft(BasisService s, BasisReply? r, String digest) async {
  final draft = await s.files.draft();
  if (draft.value?.digest != digest) return;
  await s.files.remove(basisDraftPath, draft.bytesDigest!);
  r?.changedFiles.add(basisDraftPath);
}
