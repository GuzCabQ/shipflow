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
  final report = await s.reader.readSources(sources, s.limits);
  r.sourceStatus.addAll(report.statuses);
  if (!report.complete) r.complete = false;
  _supports(r, selection, report);
  if (selection.reviewTargets.isNotEmpty) {
    r.add('historical_support_not_rechecked');
  }
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
