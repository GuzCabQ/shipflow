import 'package:core/core.dart';

import 'basis_catalog.dart';

/// La respuesta de una operación en construcción: cada paso agrega lo que
/// sabe, y [build] deriva el código de los diagnósticos. Los efectos se
/// anotan al ocurrir y nunca se deducen del código.
final class BasisReply {
  BasisReply(this.operation);

  final BasisOperation operation;
  BasisOutcome? outcome;
  var basis = BasisIntegrity.unverified;
  var draft = BasisIntegrity.unverified;
  var transaction = BasisIntegrity.unverified;
  String? basisDigest;
  String? draftDigest;
  var published = false;
  final changedFiles = <String>[];
  var coverage = BasisCoverage.notEstablished;
  BasisSelection? selection;
  BasisScope? scope;
  var complete = true;
  final sourceStatus = <BasisSourceStatus>[];
  BasisActor? actor;
  String? reason;
  final history = <BasisEvent>[];
  final proposed = <BasisProposedChange>[];
  final diagnostics = <BasisDiagnostic>[];
  final actions = <BasisAction>[];

  /// Agrega [code] una sola vez por ruta.
  void add(String code, {String? path, String? message}) {
    if (diagnostics.any((d) => d.code == code && d.path == path)) return;
    diagnostics.add(basisDiagnostic(code, path: path, message: message));
  }

  /// Los cambios exactos de [draft], con el efecto de cada versión: los
  /// que se aceptarían con su huella, sin regenerar identidades.
  void propose(BasisDraft draft) => proposed
    ..clear()
    ..addAll(draft.preparedChanges.map(BasisProposedChange.of));

  bool has(String code) => diagnostics.any((d) => d.code == code);

  /// Si algo ya impide seguir: cualquier diagnóstico que no sea aviso.
  bool get stopped => diagnostics.any((d) => !isBasisWarning(d.code));

  void addAction(BasisAction action) {
    final key = action.arguments.join('\u0000');
    if (actions.any((a) => a.arguments.join('\u0000') == key)) return;
    actions.add(action);
  }

  BasisResponse build() {
    final exit = basisExitCode(diagnostics);
    return BasisResponse(
      operation: operation,
      exitCode: exit,
      outcome: outcome ?? _fallback(exit),
      storageIntegrity: _integrity(),
      basisDigest: basisDigest,
      draftDigest: draftDigest,
      published: published,
      changedFiles: changedFiles.toSet().toList()..sort(),
      normativeCoverage: coverage,
      selected: selection?.selected ?? const [],
      reviewTargets: history.isEmpty
          ? selection?.reviewTargets ?? const []
          : const [],
      proposedChanges: proposed,
      pending: selection?.pending ?? const [],
      sourceStatus: sourceStatus,
      actor: actor,
      reason: reason,
      history: history,
      selection: _summary(),
      diagnostics: basisByPrecedence(diagnostics),
      nextActions: actions,
    );
  }

  BasisStorageIntegrity _integrity() => BasisStorageIntegrity(
    basis: basis,
    draft: draft,
    transaction: transaction,
  );

  BasisSelectionSummary _summary() => BasisSelectionSummary(
    scope: scope,
    complete: complete,
    excludedCount: selection?.excludedCount ?? 0,
  );

  BasisOutcome _fallback(int exit) => switch (exit) {
    0 => BasisOutcome.shown,
    75 => BasisOutcome.blocked,
    130 => BasisOutcome.cancelled,
    _ => published ? BasisOutcome.published : BasisOutcome.failed,
  };
}
