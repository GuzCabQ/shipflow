import 'recognition_enums.dart';
import 'recognition_evidence.dart';
import 'recognition_findings.dart';
import 'recognition_json.dart';
import 'recognition_proposal.dart';
import 'recognition_topology.dart';
import 'repository_context.dart';

/// El resultado completo de reconocer una raíz.
///
/// Sólo una raíz que no pudo inspeccionarse carece de raíz resuelta, y es la
/// única con estado `invalidRoot`.
final class RecognitionReport {
  RecognitionReport({
    required this.status,
    required this.requestedRoot,
    required this.resolvedRoot,
    required this.repository,
    required List<StackCandidate> candidates,
    required List<ProjectUnit> units,
    required List<RecognitionEvidence> evidence,
    required List<RecognitionConflict> conflicts,
    required List<RecognitionLimitation> limitations,
    required this.proposal,
    required this.effects,
  }) : candidates = List.unmodifiable(candidates),
       units = List.unmodifiable(units),
       evidence = List.unmodifiable(evidence),
       conflicts = List.unmodifiable(conflicts),
       limitations = List.unmodifiable(limitations) {
    if ((status == RecognitionStatus.invalidRoot) != (resolvedRoot == null)) {
      throw ArgumentError.value(
        resolvedRoot,
        'resolvedRoot',
        'sólo un reporte invalidRoot carece de raíz resuelta',
      );
    }
  }

  /// Una raíz que no se pudo inspeccionar: ningún plugin la miró y no hay
  /// repositorio que informar.
  factory RecognitionReport.invalidRoot({
    required String requestedRoot,
    required RecognitionLimitation reason,
  }) => RecognitionReport(
    status: RecognitionStatus.invalidRoot,
    requestedRoot: requestedRoot,
    resolvedRoot: null,
    repository: const RepositoryContext(
      status: RepositoryStatus.indeterminate,
      root: null,
      relation: RepositoryRelation.none,
    ),
    candidates: const [],
    units: const [],
    evidence: const [],
    conflicts: const [],
    limitations: [reason],
    proposal: RecognitionProposal(
      eligible: false,
      pluginIds: const [],
      actions: const [],
    ),
    effects: RecognitionEffects.none,
  );

  factory RecognitionReport.fromJson(Map<String, Object?> json) =>
      RecognitionReport(
        status: RecognitionStatus.fromWireName(json['status']! as String),
        requestedRoot: json['requestedRoot']! as String,
        resolvedRoot: json['resolvedRoot'] as String?,
        repository: RepositoryContext.fromJson(
          json['repository']! as Map<String, Object?>,
        ),
        candidates: readObjects(json['candidates'], StackCandidate.fromJson),
        units: readObjects(json['units'], ProjectUnit.fromJson),
        evidence: readObjects(json['evidence'], RecognitionEvidence.fromJson),
        conflicts: readObjects(json['conflicts'], RecognitionConflict.fromJson),
        limitations: readObjects(
          json['limitations'],
          RecognitionLimitation.fromJson,
        ),
        proposal: RecognitionProposal.fromJson(
          json['proposal']! as Map<String, Object?>,
        ),
        effects: RecognitionEffects.fromJson(
          json['effects']! as Map<String, Object?>,
        ),
      );

  final RecognitionStatus status;
  final String requestedRoot;
  final String? resolvedRoot;
  final RepositoryContext repository;
  final List<StackCandidate> candidates;
  final List<ProjectUnit> units;
  final List<RecognitionEvidence> evidence;
  final List<RecognitionConflict> conflicts;
  final List<RecognitionLimitation> limitations;
  final RecognitionProposal proposal;
  final RecognitionEffects effects;

  Map<String, Object?> toJson() => {
    'status': status.toWireName(),
    'requestedRoot': requestedRoot,
    'resolvedRoot': resolvedRoot,
    'repository': repository.toJson(),
    'candidates': [for (final c in candidates) c.toJson()],
    'units': [for (final u in units) u.toJson()],
    'evidence': [for (final e in evidence) e.toJson()],
    'conflicts': [for (final c in conflicts) c.toJson()],
    'limitations': [for (final l in limitations) l.toJson()],
    'proposal': proposal.toJson(),
    'effects': effects.toJson(),
  };
}
