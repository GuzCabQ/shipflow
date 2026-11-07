import 'dart:convert';

import 'package:core/core.dart';
import 'package:rules/rules.dart';

import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import 'basis_canonical.dart';
import 'basis_candidate.dart';
import 'basis_catalog.dart';
import 'basis_codec.dart';
import 'basis_flow.dart';
import 'basis_reply.dart';
import 'basis_service.dart';
import 'basis_store.dart';

/// Prepara [input] como borrador: valida contexto, base, journal y
/// referencias antes de leer fuentes; asigna IDs y versiones; observa las
/// fuentes nuevas y sella el borrador. Nunca cambia la base. Con
/// [expectedDraftDigest] reemplaza ese borrador exacto; sin él, nunca
/// reemplaza otro distinto.
Future<void> prepareBasis(
  BasisService s,
  BasisReply r,
  BasisInput input, {
  required String? expectedDraftDigest,
}) async {
  final env = await s.readProject();
  final state = await _state(s, r, env, input);
  if (state == null) return;
  final (basis, current) = state;
  if (basis.value != null && input.changes.isEmpty) {
    r
      ..outcome = BasisOutcome.noChanges
      ..addAction(showAction);
    return;
  }
  final issues = validateBasisChangeSet(input, basis.value);
  if (issues.isNotEmpty) {
    r.add(issues.first.code, path: issues.first.at);
    return;
  }
  if (!await _mayWrite(s, r, current, input, env, expectedDraftDigest)) return;
  final draft = await _draft(s, input, basis.value, env);
  final candidate = _candidate(s, r, basis.value, draft);
  if (candidate == null) return;
  await s.files.locked(() => _write(s, r, draft, current.bytesDigest));
  if (r.stopped) return;
  await _presentDraft(s, r, draft, candidate);
}

/// La base y el borrador actuales, si contexto, base, journal y entrada
/// permiten preparar; si no, null con su diagnóstico.
Future<(BasisFile<BasisDocument>, BasisFile<BasisDraft>)?> _state(
  BasisService s,
  BasisReply r,
  BasisEnvironment env,
  BasisInput input,
) async {
  if (!contextReady(env, r)) return null;
  final files = s.files;
  final basis = await files.basis();
  r.basis = basis.integrity;
  if (!usable(r, basis, basisDocumentPath)) return null;
  if (!await _noJournal(files, r)) return null;
  if (!_sameBase(r, env, input, basis.value)) return null;
  final current = await files.draft();
  r.draft = current.integrity;
  if (!usable(r, current, basisDraftPath)) return null;
  return (basis, current);
}

Future<bool> _noJournal(BasisStore files, BasisReply r) async {
  final journal = await files.journal();
  r.transaction = journal.integrity;
  if (journal.absent) return true;
  r
    ..add('recovery_required', path: basisTransactionPath)
    ..addAction(recoverAction);
  return false;
}

/// La entrada es del mismo proyecto que el contexto y la base, y espera
/// exactamente la base vigente.
bool _sameBase(
  BasisReply r,
  BasisEnvironment env,
  BasisInput input,
  BasisDocument? basis,
) {
  if (input.projectId != env.projectId ||
      (basis != null && basis.projectId != env.projectId)) {
    r.add('invalid_reference', path: 'projectId');
    return false;
  }
  if (input.expectedBasisDigest != basis?.digest) {
    r.add('base_changed', path: basisDocumentPath);
    return false;
  }
  return true;
}

/// Si se puede escribir el borrador: no hay otro, o se revisa exactamente
/// el esperado. Repetir la misma entrada sobre la misma base devuelve el
/// guardado, sin renovar IDs ni escribir.
Future<bool> _mayWrite(
  BasisService s,
  BasisReply r,
  BasisFile<BasisDraft> current,
  BasisInput input,
  BasisEnvironment env,
  String? expectedDraftDigest,
) async {
  final existing = current.value;
  if (expectedDraftDigest == null) {
    if (existing == null) return true;
    if (_same(existing, input, env)) {
      await _presentDraft(s, r, existing, null);
      return false;
    }
  } else if (existing?.digest == expectedDraftDigest) {
    return true;
  }
  r
    ..add('draft_conflict', path: basisDraftPath)
    ..addAction(showDraftAction);
  if (existing != null) r.addAction(discardAction(existing.digest));
  return false;
}

bool _same(BasisDraft draft, BasisInput input, BasisEnvironment env) =>
    draft.contextProjectDigest == env.contextDigest &&
    utf8.decode(canonicalBasisJson(draft.input.toJson())) ==
        utf8.decode(canonicalBasisJson(input.toJson()));

/// El borrador sellado: IDs y versiones asignados, `new:` resueltos y las
/// fuentes nuevas observadas por el coordinador.
Future<BasisDraft> _draft(
  BasisService s,
  BasisInput input,
  BasisDocument? basis,
  BasisEnvironment env,
) async {
  final resolved = resolveBasisChanges(input, basis, s.newId);
  final report = await s.sources.read(_toRead(resolved, basis), observe: true);
  final digests = {for (final r in report.readings) r.path: r.digest};
  final states = {for (final st in report.statuses) st.sourceId: st.status};
  return sealDraft(
    BasisDraft(
      projectId: env.projectId!,
      operationId: s.newId(),
      createdAt: basisTimestamp(s.now()),
      expectedBasisDigest: input.expectedBasisDigest,
      contextProjectDigest: env.contextDigest!,
      input: input,
      preparedChanges: [
        for (final v in resolved) _observed(v, states[v.id], digests),
      ],
      sourceReads: report.readings,
      digest: 'sha256:${'0' * 64}',
    ),
  );
}

/// Las fuentes nuevas del lote y las versiones existentes que citan sus
/// reglas activas sustentadas: se leen ahora para revalidarlas al aceptar.
List<BasisRecordVersion> _toRead(
  List<BasisRecordVersion> resolved,
  BasisDocument? basis,
) {
  final ledger = ledgerOf(basis);
  final batch = {for (final v in resolved) '${v.id}@${v.version}': v};
  return [
    for (final v in resolved)
      if (v.payload is BasisSource) v,
    for (final v in resolved)
      if (v.payload case BasisRule(:final sourceRefs))
        for (final ref in sourceRefs)
          if (!batch.containsKey('${ref.ref}@${ref.version}'))
            ?ledger.versionOf(ref.ref, ref.version),
  ];
}

BasisRecordVersion _observed(
  BasisRecordVersion v,
  BasisSourceState? state,
  Map<String, String> digests,
) {
  final source = v.payload;
  if (source is! BasisSource || source.sourceType != BasisSourceType.local) {
    return v;
  }
  final read = state == BasisSourceState.current;
  return BasisRecordVersion(
    id: v.id,
    version: v.version,
    previousVersion: v.previousVersion,
    payload: BasisSource(
      title: source.title,
      scope: source.scope,
      lifecycle: source.lifecycle,
      sourceType: source.sourceType,
      locator: source.locator,
      purpose: source.purpose,
      contentDigest: read ? digests[source.locator] : null,
      observation: switch (state) {
        BasisSourceState.current => BasisObservation.current,
        BasisSourceState.excluded => BasisObservation.excluded,
        _ => BasisObservation.unverified,
      },
    ),
  );
}

/// La base que resultaría de aceptar, dentro de las cotas del perfil; null
/// y su diagnóstico si no cabe: un borrador que no se podría aceptar con
/// este perfil no se prepara.
BasisDocument? _candidate(
  BasisService s,
  BasisReply r,
  BasisDocument? basis,
  BasisDraft draft,
) {
  final candidate = buildCandidate(
    basis,
    draft,
    acceptedAt: draft.createdAt,
    producer: s.version,
  );
  final fits =
      encodeBasisDraft(draft).length <= s.limits.maxDraftBytes &&
      encodeBasis(candidate).length <= s.limits.maxBasisBytes &&
      candidate.revision <= s.limits.maxEvents &&
      replayBasis(candidate).length <= s.limits.maxCurrentRecords;
  if (fits) return candidate;
  r.add('budget_exceeded', path: basisDraftPath);
  return null;
}

/// Publica el borrador con CAS sobre el que había al leerlo: otro escritor
/// entre medio no se sobrescribe.
Future<void> _write(
  BasisService s,
  BasisReply r,
  BasisDraft draft,
  String? previous,
) async {
  try {
    await s.files.publish(basisDraftPath, encodeBasisDraft(draft), previous);
  } on ContextStoreFailure catch (failure) {
    if (failure.code != 'concurrent_change') rethrow;
    r
      ..add('draft_conflict', path: basisDraftPath)
      ..addAction(showDraftAction);
    return;
  }
  r
    ..changedFiles.add(basisDraftPath)
    ..draft = BasisIntegrity.valid;
}

Future<void> _presentDraft(
  BasisService s,
  BasisReply r,
  BasisDraft draft,
  BasisDocument? candidate,
) async {
  final basis = (await s.files.basis()).value;
  final document =
      candidate ??
      buildCandidate(
        basis,
        draft,
        acceptedAt: draft.createdAt,
        producer: s.version,
      );
  await present(s, r, replayBasisLedger(document));
  r
    ..outcome = BasisOutcome.draftPrepared
    ..draftDigest = draft.digest
    ..draft = BasisIntegrity.valid
    ..actor = draft.input.actor
    ..reason = draft.input.reason
    ..propose(draft)
    ..add('draft_prepared', path: basisDraftPath);
  draftActions(r, draft.digest);
}
