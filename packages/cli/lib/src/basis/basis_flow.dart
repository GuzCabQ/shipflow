import 'package:core/core.dart';
import 'package:rules/rules.dart';

import '../context/state_layout.dart';
import 'basis_catalog.dart';
import 'basis_reply.dart';
import 'basis_service.dart';
import 'basis_store.dart';

/// Las piezas comunes a los flujos de bootstrap.

/// Si el proyecto V2 permite operar: sin init ni assess a medio terminar y
/// con un contexto disponible y válido.
bool contextReady(BasisEnvironment env, BasisReply r) {
  if (env.contextRecoveryPending || env.assessmentRecoveryPending) {
    r.add(
      'recovery_required',
      path: env.contextRecoveryPending
          ? transactionPath
          : assessmentTransactionPath,
      message: 'Hay una operación de init o de assess sin terminar.',
    );
    return false;
  }
  if (env.context != BasisIntegrity.valid || env.projectId == null) {
    r.add('context_required', path: projectPath);
    return false;
  }
  return true;
}

/// Sólo se presenta lo de este proyecto, con su contexto listo: una base o
/// un borrador de otra copia nunca se entregan como aplicables.
Future<bool> boundToProject(
  BasisService s,
  BasisReply r,
  BasisDocument? basis,
  BasisDraft? draft,
) async {
  final env = await s.readProject();
  if (!contextReady(env, r)) return false;
  for (final (projectId, path) in [
    (basis?.projectId, basisDocumentPath),
    (draft?.projectId, basisDraftPath),
  ]) {
    if (projectId != null && projectId != env.projectId) {
      if (path == basisDocumentPath) {
        r.basis = BasisIntegrity.invalid;
      } else {
        r.draft = BasisIntegrity.invalid;
      }
      r.add(
        'invalid_reference',
        path: path,
        message: 'Es de otro proyecto: no se usa.',
      );
      return false;
    }
  }
  return true;
}

/// Si [file] se puede usar: ausente o válido. Si no, anota su código y lo
/// conserva: un archivo propio dañado nunca se sobrescribe.
bool usable<T>(BasisReply r, BasisFile<T> file, String path) {
  if (file.code == null) return true;
  r.add(file.code!, path: path);
  return false;
}

/// La historia de [basis], o vacía si no existe.
BasisLedger ledgerOf(BasisDocument? basis) =>
    basis == null ? BasisLedger() : replayBasisLedger(basis);

/// La selección de [ledger] para [path], su cobertura y, sólo para las
/// reglas vigentes seleccionadas, la vigencia de sus soportes. Un target
/// de revisión no revalida sus fuentes.
Future<void> present(
  BasisService s,
  BasisReply r,
  BasisLedger ledger, {
  String? path,
}) async {
  final selection = selectBasisLedger(ledger, path: path);
  r
    ..selection = selection
    ..coverage = basisCoverage(ledger.current);
  final sources = [
    for (final v in selection.selected)
      if (v.payload is BasisSource) v,
  ];
  final report = await s.sources.read(sources);
  r.sourceStatus.addAll(report.statuses);
  if (!report.complete) _sourceBudget(s, r);
  _supports(r, selection, report);
  if (selection.reviewTargets.isNotEmpty) {
    r.add('historical_support_not_rechecked');
  }
}

/// Las reglas activas sustentadas que [changes] agregan o revisan
/// necesitan todas sus fuentes vigentes antes de publicar [candidate], sea
/// al aceptar o al recuperar; una regla ya aceptada que perdió su soporte
/// no bloquea cambios ajenos. Lee con la sesión de la operación, así que
/// usa las lecturas de la misma revalidación.
Future<bool> supported(
  BasisService s,
  BasisReply r,
  List<BasisRecordVersion> changes,
  BasisDocument candidate,
) async {
  final ledger = replayBasisLedger(candidate);
  final cited = <BasisRecordVersion>[];
  for (final change in changes) {
    final rule = change.payload;
    if (rule is BasisRule &&
        rule.lifecycle == BasisRuleLifecycle.active &&
        rule.support == BasisSupport.sourceSupported) {
      for (final ref in rule.sourceRefs) {
        cited.add(ledger.versionOf(ref.ref, ref.version)!);
      }
    }
  }
  final report = await s.sources.read(cited);
  final unverified = [
    for (final st in report.statuses)
      if (st.status != BasisSourceState.current) st,
  ];
  if (unverified.isEmpty) return true;
  r.sourceStatus.addAll(report.statuses);
  r.add('source_unverified', path: unverified.first.sourceId);
  return false;
}

/// Lo que no se pudo leer por presupuesto deja la consulta no concluyente,
/// nunca un éxito: se dice por qué y, en standard, cómo ampliarlo.
void _sourceBudget(BasisService s, BasisReply r) {
  final widen = s.limits.profile == BasisProfile.standard
      ? ' Repite con --report-budget=extended.'
      : '';
  r
    ..complete = false
    ..add(
      'budget_exceeded',
      message:
          'Se agotó el presupuesto de lectura de fuentes: la consulta no es '
          'concluyente.$widen',
    );
}

/// Una regla activa sustentada en fuentes exige todas sus versiones
/// citadas vigentes; si no, el soporte no está verificado. La regla no
/// cambia de ciclo de vida por eso.
void _supports(
  BasisReply r,
  BasisSelection selection,
  BasisSourceReport report,
) {
  final states = {
    for (final s in report.statuses) '${s.sourceId}@${s.sourceVersion}': s,
  };
  for (final record in selection.selected) {
    final rule = record.payload;
    if (rule is! BasisRule ||
        rule.lifecycle != BasisRuleLifecycle.active ||
        rule.support != BasisSupport.sourceSupported) {
      continue;
    }
    for (final ref in rule.sourceRefs) {
      final status = states['${ref.ref}@${ref.version}'];
      if (status?.status != BasisSourceState.current) {
        r.add('source_unverified', path: record.id);
      }
    }
  }
}

/// Las acciones para revisar un borrador preparado.
void draftActions(BasisReply r, String digest) => r
  ..addAction(showDraftAction)
  ..addAction(acceptAction(digest))
  ..addAction(discardAction(digest));
