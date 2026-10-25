import 'recognition_context.dart';
import 'recognition_enums.dart';
import 'recognition_evidence.dart';
import 'recognition_findings.dart';
import 'recognition_json.dart';
import 'recognition_omissions.dart';
import 'recognition_proposal.dart';
import 'recognition_relations.dart';
import 'recognition_topology.dart';
import 'repository_context.dart';

/// El único alcance que un reporte puede declarar: lo que el proyecto
/// declara y se observó, no un inventario global ni su salud.
const declaredProjectRecognition = 'declared_project_recognition';

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
    required List<RecognitionRelation> relations,
    required List<ContextSource> contextSources,
    required List<RecognitionOmission> omissions,
    required this.proposal,
    required this.effects,
  }) : candidates = List.unmodifiable(candidates),
       units = List.unmodifiable(units),
       evidence = List.unmodifiable(evidence),
       conflicts = List.unmodifiable(conflicts),
       limitations = List.unmodifiable(limitations),
       relations = List.unmodifiable(relations),
       contextSources = List.unmodifiable(contextSources),
       omissions = List.unmodifiable(omissions) {
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
    relations: const [],
    contextSources: const [],
    omissions: const [],
    proposal: RecognitionProposal(
      eligible: false,
      pluginIds: const [],
      actions: const [],
    ),
    effects: RecognitionEffects.none,
  );

  /// Rechaza un alcance distinto del único que esta versión declara.
  factory RecognitionReport.fromJson(Map<String, Object?> json) {
    _requireScope(json['recognitionScope']);
    return RecognitionReport(
      status: RecognitionStatus.fromWireName(json['status']! as String),
      requestedRoot: json['requestedRoot']! as String,
      resolvedRoot: json['resolvedRoot'] as String?,
      repository: readObject(json['repository'], RepositoryContext.fromJson),
      candidates: readObjects(json['candidates'], StackCandidate.fromJson),
      units: readObjects(json['units'], ProjectUnit.fromJson),
      evidence: readObjects(json['evidence'], RecognitionEvidence.fromJson),
      conflicts: readObjects(json['conflicts'], RecognitionConflict.fromJson),
      limitations: readObjects(
        json['limitations'],
        RecognitionLimitation.fromJson,
      ),
      relations: readObjects(json['relations'], RecognitionRelation.fromJson),
      contextSources: readObjects(
        json['contextSources'],
        ContextSource.fromJson,
      ),
      omissions: readObjects(json['omissions'], RecognitionOmission.fromJson),
      proposal: readObject(json['proposal'], RecognitionProposal.fromJson),
      effects: readObject(json['effects'], RecognitionEffects.fromJson),
    );
  }

  final RecognitionStatus status;
  final String requestedRoot;
  final String? resolvedRoot;
  final RepositoryContext repository;
  final List<StackCandidate> candidates;
  final List<ProjectUnit> units;
  final List<RecognitionEvidence> evidence;
  final List<RecognitionConflict> conflicts;
  final List<RecognitionLimitation> limitations;
  final List<RecognitionRelation> relations;
  final List<ContextSource> contextSources;
  final List<RecognitionOmission> omissions;
  final RecognitionProposal proposal;
  final RecognitionEffects effects;

  /// Siempre [declaredProjectRecognition]: no un inventario global.
  final String recognitionScope = declaredProjectRecognition;

  Map<String, Object?> toJson() => {
    'status': status.toWireName(),
    'requestedRoot': requestedRoot,
    'resolvedRoot': resolvedRoot,
    'repository': repository.toJson(),
    'recognitionScope': recognitionScope,
    'candidates': [for (final c in candidates) c.toJson()],
    'units': [for (final u in units) u.toJson()],
    'evidence': [for (final e in evidence) e.toJson()],
    'conflicts': [for (final c in conflicts) c.toJson()],
    'limitations': [for (final l in limitations) l.toJson()],
    'relations': [for (final r in relations) r.toJson()],
    'contextSources': [for (final s in contextSources) s.toJson()],
    'omissions': [for (final o in omissions) o.toJson()],
    'proposal': proposal.toJson(),
    'effects': effects.toJson(),
  };
}

void _requireScope(Object? scope) {
  if (scope != declaredProjectRecognition) {
    throw FormatException('alcance de reconocimiento desconocido', scope);
  }
}
