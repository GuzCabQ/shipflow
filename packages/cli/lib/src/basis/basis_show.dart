import 'package:core/core.dart';

import '../context/state_layout.dart';
import 'basis_candidate.dart';
import 'basis_catalog.dart';
import 'basis_flow.dart';
import 'basis_reply.dart';
import 'basis_service.dart';
import 'basis_store.dart';

/// `--show`: la base aceptada sin escribir nada. Con [path], la selección
/// para ese ámbito; con [history], los eventos validados sin releer
/// soportes; con [draft], el candidato que resultaría de aceptar el
/// borrador, identificado como no aceptado. Sin base demostrable no se
/// inventa una selección ni un «sin reglas».
Future<void> showBasis(
  BasisService s,
  BasisReply r, {
  required String? path,
  required bool history,
  required bool draft,
}) async {
  final files = s.files;
  final basis = await files.basis();
  r.basis = basis.integrity;
  final draftFile = await files.draft();
  r.draft = draftFile.integrity;
  await _journal(files, r);
  if (!usable(r, basis, basisDocumentPath)) return;
  if (draft) return _draft(s, r, basis.value, draftFile);
  final document = basis.value;
  if (document == null) {
    r.add('basis_absent', path: basisDocumentPath);
    if (draftFile.value != null) r.addAction(showDraftAction);
    return;
  }
  r.basisDigest = document.digest;
  final ledger = replayBasisLedger(document);
  r.outcome = BasisOutcome.shown;
  if (history) return _history(r, document, ledger);
  await _selected(s, r, ledger, path);
}

/// Lo vigente para [path]; un ámbito inseguro no se consulta ni se
/// presenta como una base vacía.
Future<void> _selected(
  BasisService s,
  BasisReply r,
  BasisLedger ledger,
  String? path,
) async {
  final query = _query(r, path);
  if (r.stopped && r.has('unsafe_path')) {
    r
      ..outcome = BasisOutcome.failed
      ..complete = false;
    return;
  }
  r.scope = query == null
      ? null
      : BasisScope(kind: BasisScopeKind.paths, paths: [query]);
  await present(s, r, ledger, path: query);
}

/// Los eventos en orden, con sus huellas y vínculos ya validados; los
/// soportes no se vuelven a leer ni se afirma su vigencia actual.
void _history(BasisReply r, BasisDocument document, BasisLedger ledger) => r
  ..history.addAll(document.events)
  ..coverage = basisCoverage(ledger.current)
  ..add('history_sources_not_rechecked');

/// Una publicación pendiente se informa en cualquier consulta, con su
/// acción; un journal que no valida se informa sin usarlo.
Future<void> _journal(BasisStore files, BasisReply r) async {
  final journal = await files.journal();
  r.transaction = journal.integrity;
  if (journal.absent) return;
  if (journal.code != null) {
    r.add(journal.code!, path: basisTransactionPath);
    return;
  }
  r
    ..add('recovery_required', path: basisTransactionPath)
    ..addAction(recoverAction);
}

/// `.` es la consulta global; cualquier otra ruta, un prefijo normalizado.
String? _query(BasisReply r, String? path) {
  if (path == null || path == '.') return null;
  if (isBasisPrefix(path)) return path;
  r.add('unsafe_path', path: 'scope');
  return null;
}

Future<void> _draft(
  BasisService s,
  BasisReply r,
  BasisDocument? basis,
  BasisFile<BasisDraft> draftFile,
) async {
  if (!usable(r, draftFile, basisDraftPath)) return;
  final draft = draftFile.value;
  if (draft == null) {
    r.add('invalid_reference', path: basisDraftPath, message: _noDraft);
    return;
  }
  if (draft.expectedBasisDigest != basis?.digest) return _outdated(r, draft);
  final candidate = buildCandidate(
    basis,
    draft,
    acceptedAt: draft.createdAt,
    producer: s.version,
  );
  await present(s, r, replayBasisLedger(candidate));
  r
    ..outcome = BasisOutcome.shown
    ..basisDigest = basis?.digest
    ..draftDigest = draft.digest
    ..actor = draft.input.actor
    ..reason = draft.input.reason
    ..add('draft_not_accepted', path: basisDraftPath);
  draftActions(r, draft.digest);
}

const _noDraft = 'No hay un borrador guardado.';

/// Un borrador preparado sobre otra base no se presenta aplicado a la
/// actual: sólo se puede descartar y preparar de nuevo.
void _outdated(BasisReply r, BasisDraft draft) => r
  ..draftDigest = draft.digest
  ..add(
    'base_changed',
    path: basisDocumentPath,
    message:
        'La base cambió desde que se preparó este borrador: descártalo y '
        'prepara otro sobre la base actual.',
  )
  ..addAction(discardAction(draft.digest));
