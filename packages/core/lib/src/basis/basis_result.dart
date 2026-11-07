import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'basis_model.dart';
import 'basis_proposed_change.dart';
import 'basis_response_parts.dart';

/// La respuesta de bootstrap: humano y JSON nacen de ella. Integridad,
/// efectos, selección y vigencia de soportes son dimensiones separadas; un
/// código 0 no prueba cobertura ni cumplimiento.
final class BasisResponse {
  BasisResponse({
    required this.operation,
    required this.exitCode,
    required this.outcome,
    required this.storageIntegrity,
    required this.basisDigest,
    required this.draftDigest,
    required this.published,
    required List<String> changedFiles,
    required this.normativeCoverage,
    required List<BasisRecordVersion> selected,
    required List<BasisRecordVersion> reviewTargets,
    required List<BasisProposedChange> proposedChanges,
    required List<BasisRecordVersion> pending,
    required List<BasisSourceStatus> sourceStatus,
    required this.actor,
    required this.reason,
    required List<BasisEvent> history,
    required this.selection,
    required List<BasisDiagnostic> diagnostics,
    required List<BasisAction> nextActions,
  }) : changedFiles = List.unmodifiable(changedFiles),
       selected = List.unmodifiable(selected),
       reviewTargets = List.unmodifiable(reviewTargets),
       proposedChanges = List.unmodifiable(proposedChanges),
       pending = List.unmodifiable(pending),
       sourceStatus = List.unmodifiable(sourceStatus),
       history = List.unmodifiable(history),
       diagnostics = List.unmodifiable(diagnostics),
       nextActions = List.unmodifiable(nextActions);

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory BasisResponse.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'incompatible_version');
    requireSemantic(json['type'] == 'bootstrap', 'invalid_schema');
    const version = BasisRecordVersion.fromJson;
    const proposed = BasisProposedChange.fromJson;
    return BasisResponse(
      operation: BasisOperation.fromWireName(json['operation']! as String),
      exitCode: json['exitCode']! as int,
      outcome: BasisOutcome.fromWireName(json['outcome']! as String),
      storageIntegrity: _integrity(json['storageIntegrity']),
      basisDigest: json['basisDigest'] as String?,
      draftDigest: json['draftDigest'] as String?,
      published: json['published']! as bool,
      changedFiles: readStrings(json['changedFiles']),
      normativeCoverage: BasisCoverage.fromWireName(
        json['normativeCoverage']! as String,
      ),
      selected: readObjects(json['selected'], version),
      reviewTargets: readObjects(json['reviewTargets'], version),
      proposedChanges: readObjects(json['proposedChanges'], proposed),
      pending: readObjects(json['pending'], version),
      sourceStatus: readObjects(json['sourceStatus'], _status),
      actor: _actor(json['actor']),
      reason: json['reason'] as String?,
      history: readObjects(json['history'], BasisEvent.fromJson),
      selection: readObject(json['selection'], BasisSelectionSummary.fromJson),
      diagnostics: readObjects(json['diagnostics'], BasisDiagnostic.fromJson),
      nextActions: readObjects(json['nextActions'], BasisAction.fromJson),
    );
  }

  static BasisActor? _actor(Object? json) =>
      json == null ? null : readObject(json, BasisActor.fromJson);

  static BasisStorageIntegrity _integrity(Object? json) =>
      readObject(json, BasisStorageIntegrity.fromJson);

  static BasisSourceStatus _status(Map<String, Object?> json) =>
      BasisSourceStatus.fromJson(json);

  final int schemaVersion = 1;
  final String type = 'bootstrap';
  final BasisOperation operation;
  final int exitCode;
  final BasisOutcome outcome;
  final BasisStorageIntegrity storageIntegrity;
  final String? basisDigest;
  final String? draftDigest;
  final bool published;
  final List<String> changedFiles;
  final BasisCoverage normativeCoverage;

  /// Las versiones de reglas y fuentes vigentes que aplican.
  final List<BasisRecordVersion> selected;

  /// Versiones exactas citadas por revisiones abiertas: históricas, no
  /// reglas vigentes por implicación.
  final List<BasisRecordVersion> reviewTargets;

  /// Propuestas y asuntos por resolver.
  /// Los cambios exactos del borrador que se ofrece aceptar, con su
  /// efecto; vacío fuera de un borrador.
  final List<BasisProposedChange> proposedChanges;

  final List<BasisRecordVersion> pending;
  final List<BasisSourceStatus> sourceStatus;
  final BasisActor? actor;
  final String? reason;

  /// Sólo en la consulta de historia: eventos en orden cronológico.
  final List<BasisEvent> history;
  final BasisSelectionSummary selection;
  final List<BasisDiagnostic> diagnostics;
  final List<BasisAction> nextActions;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'type': type,
    'operation': operation.toWireName(),
    'exitCode': exitCode,
    'outcome': outcome.toWireName(),
    'storageIntegrity': storageIntegrity.toJson(),
    'basisDigest': basisDigest,
    'draftDigest': draftDigest,
    'published': published,
    'changedFiles': changedFiles,
    'normativeCoverage': normativeCoverage.toWireName(),
    'selected': [for (final r in selected) r.toJson()],
    'reviewTargets': [for (final r in reviewTargets) r.toJson()],
    'proposedChanges': [for (final c in proposedChanges) c.toJson()],
    'pending': [for (final r in pending) r.toJson()],
    'sourceStatus': [for (final s in sourceStatus) s.toJson()],
    'actor': actor?.toJson(),
    'reason': reason,
    'history': [for (final e in history) e.toJson()],
    'selection': selection.toJson(),
    'diagnostics': [for (final d in diagnostics) d.toJson()],
    'nextActions': [for (final a in nextActions) a.toJson()],
  };
}
