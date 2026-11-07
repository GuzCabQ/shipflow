import 'dart:convert';

import 'package:core/core.dart';

import '../context/state_layout.dart';
import 'basis_catalog.dart';
import 'basis_commit.dart';
import 'basis_flow.dart';
import 'basis_preconditions.dart';
import 'basis_reply.dart';
import 'basis_service.dart';

/// `--recover`: completa o aborta sólo una publicación con aceptación ya
/// registrada en su journal. Nunca convierte un borrador en aceptado; un
/// journal presente que no se puede acreditar se conserva y nunca es un
/// no-op.
Future<void> recoverBasis(BasisService s, BasisReply r) =>
    s.files.locked(() async {
      final journal = await s.files.journal();
      r.transaction = journal.integrity;
      if (journal.absent) return _leftovers(s, r);
      if (!usable(r, journal, basisTransactionPath)) return;
      final value = journal.value!;
      if (!await _attributable(s, r, value)) return;
      final now = (await s.files.basis()).bytesDigest;
      if (now == value.after) return _completed(s, r, value);
      if (now == value.before) return _finish(s, r, value);
      _conflict(r, 'La base no es la anterior ni la publicada.');
    });

/// Sin journal: un candidato completo de este proyecto se retira tras
/// identificarlo, nunca se adopta; un temporal o un candidato que no se
/// puede acreditar se conserva y es un conflicto. Sin restos, no-op.
Future<void> _leftovers(BasisService s, BasisReply r) async {
  final observed = await s.observeLayout?.call();
  if (observed is! ObservedLayout) {
    r.outcome = BasisOutcome.noChanges;
    return;
  }
  if (observed.basisTemporaries.isNotEmpty) {
    return _conflict(r, 'Hay temporales de una publicación sin journal.');
  }
  final projectId = (await s.readProject()).projectId;
  for (final path in observed.basisCandidates) {
    final candidate = await s.files.candidate(path);
    if (candidate.value == null || candidate.value!.projectId != projectId) {
      return _conflict(r, 'Hay un candidato sin journal que no se acredita.');
    }
    await s.files.remove(path, candidate.bytesDigest!);
    await s.store.removeDirectory(path.substring(0, path.lastIndexOf('/')));
    r.changedFiles.add(path);
  }
  r.outcome = r.changedFiles.isEmpty
      ? BasisOutcome.noChanges
      : BasisOutcome.recovered;
}

/// El journal es de este proyecto y no hay otra transacción activa: dos
/// journals no se ordenan adivinando.
Future<bool> _attributable(
  BasisService s,
  BasisReply r,
  BasisTransaction journal,
) async {
  final env = await s.readProject();
  if (env.contextRecoveryPending || env.assessmentRecoveryPending) {
    _conflict(r, 'Hay otra transacción de init o de assess activa.');
    return false;
  }
  if (env.projectId != journal.projectId) {
    _conflict(r, 'El journal es de otro proyecto.');
    return false;
  }
  return true;
}

void _conflict(BasisReply r, String message) =>
    r.add('recovery_required', path: basisTransactionPath, message: message);

/// La base ya es la publicada: sólo se completa la limpieza comprobada y
/// se informa la vigencia actual de sus soportes.
Future<void> _completed(
  BasisService s,
  BasisReply r,
  BasisTransaction journal,
) async {
  await settle(s, r, journal);
  r
    ..outcome = BasisOutcome.recovered
    ..changedFiles.add(basisTransactionPath);
  final basis = await s.files.basis();
  r
    ..basis = basis.integrity
    ..basisDigest = basis.value?.digest;
  if (basis.value != null) await present(s, r, replayBasisLedger(basis.value!));
}

/// La base sigue en before: se publica el candidato si es exactamente el
/// aceptado y sus precondiciones siguen; si cambiaron, se conserva todo.
Future<void> _finish(
  BasisService s,
  BasisReply r,
  BasisTransaction journal,
) async {
  final candidate = await s.files.candidate(journal.candidatePath);
  final document = candidate.value;
  if (candidate.bytesDigest != journal.after ||
      document == null ||
      !_matches(document, journal)) {
    _conflict(r, 'El candidato no corresponde a la aceptación registrada.');
    return;
  }
  final failure = await _unchanged(s, journal);
  if (failure != null) {
    r
      ..add('recovery_preconditions_changed', path: failure.path)
      ..addAction(discardAction(journal.acceptedDraftDigest));
    return;
  }
  await finishPublication(s, r, journal, candidate.bytes!, document.digest);
  r.outcome = BasisOutcome.recovered;
  if (r.published) await present(s, r, replayBasisLedger(document));
}

/// Las precondiciones que registró el journal; la base ya se comprobó por
/// sus bytes: sigue en before.
Future<BasisDiagnostic?> _unchanged(
  BasisService s,
  BasisTransaction journal,
) async => checkBasisPreconditions(
  BasisPreconditions(
    state: await s.readProject(),
    projectId: journal.projectId,
    currentBasisDigest: null,
    expectedBasisDigest: null,
    contextProjectDigest: journal.contextProjectDigest,
    sourceReads: journal.sourceReads,
    reader: s.reader,
    limits: s.limits,
  ),
);

/// El último evento del candidato es exactamente la aceptación del journal.
bool _matches(BasisDocument candidate, BasisTransaction journal) {
  final event = candidate.events.last;
  return candidate.projectId == journal.projectId &&
      event.operationId == journal.operationId &&
      event.draftDigest == journal.acceptedDraftDigest &&
      event.acceptedAt == journal.acceptedAt &&
      jsonEncode(event.actor.toJson()) == jsonEncode(journal.actor.toJson());
}

/// `--discard <huella>`: descarta ese borrador propio o, con un journal
/// válido de esa huella y la base todavía en before, aborta su
/// publicación. Nunca retira decisiones ni historia aceptada.
Future<void> discardBasis(BasisService s, BasisReply r, String digest) =>
    s.files.locked(() async {
      final journal = await s.files.journal();
      r.transaction = journal.integrity;
      if (!journal.absent) {
        return _abort(s, r, journal.value, journal.code, digest);
      }
      final draft = await s.files.draft();
      r.draft = draft.integrity;
      if (!usable(r, draft, basisDraftPath)) return;
      final value = draft.value;
      if (value == null) {
        r.add(
          'invalid_reference',
          path: basisDraftPath,
          message: 'No hay un borrador con esa huella.',
        );
        return;
      }
      if (value.digest != digest) {
        r.add('draft_conflict', path: basisDraftPath);
        return;
      }
      await s.files.remove(basisDraftPath, draft.bytesDigest!);
      r
        ..outcome = BasisOutcome.discarded
        ..draft = BasisIntegrity.absent
        ..changedFiles.add(basisDraftPath);
    });

Future<void> _abort(
  BasisService s,
  BasisReply r,
  BasisTransaction? journal,
  String? code,
  String digest,
) async {
  if (journal == null) {
    r.add(code!, path: basisTransactionPath);
    return;
  }
  if (journal.acceptedDraftDigest != digest) {
    r.add('draft_conflict', path: basisTransactionPath);
    return;
  }
  final now = (await s.files.basis()).bytesDigest;
  if (now != journal.before) {
    r
      ..add('recovery_required', path: basisTransactionPath)
      ..addAction(recoverAction);
    return;
  }
  await abortOwn(s, journal, reply: r, removeDraft: true);
  r
    ..outcome = BasisOutcome.abortedBeforePublication
    ..changedFiles.add(basisTransactionPath);
}
