import 'recognition_context.dart';
import 'recognition_evidence.dart';
import 'recognition_findings.dart';
import 'recognition_json.dart';
import 'recognition_omissions.dart';
import 'recognition_relations.dart';
import 'recognition_topology.dart';

/// Lo que un plugin observó en la raíz, sin decidir el resultado global.
/// Un plugin que no observa relaciones, contexto u omisiones las omite.
final class RecognitionContribution {
  RecognitionContribution({
    required List<StackCandidate> candidates,
    required List<ProjectUnit> units,
    required List<RecognitionEvidence> evidence,
    required List<RecognitionConflict> conflicts,
    required List<RecognitionLimitation> limitations,
    List<RecognitionRelation> relations = const [],
    List<ContextSource> contextSources = const [],
    List<RecognitionOmission> omissions = const [],
  }) : candidates = List.unmodifiable(candidates),
       units = List.unmodifiable(units),
       evidence = List.unmodifiable(evidence),
       conflicts = List.unmodifiable(conflicts),
       limitations = List.unmodifiable(limitations),
       relations = List.unmodifiable(relations),
       contextSources = List.unmodifiable(contextSources),
       omissions = List.unmodifiable(omissions);

  factory RecognitionContribution.fromJson(Map<String, Object?> json) =>
      RecognitionContribution(
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
      );

  final List<StackCandidate> candidates;
  final List<ProjectUnit> units;
  final List<RecognitionEvidence> evidence;
  final List<RecognitionConflict> conflicts;
  final List<RecognitionLimitation> limitations;
  final List<RecognitionRelation> relations;
  final List<ContextSource> contextSources;
  final List<RecognitionOmission> omissions;

  Map<String, Object?> toJson() => {
    'candidates': [for (final c in candidates) c.toJson()],
    'units': [for (final u in units) u.toJson()],
    'evidence': [for (final e in evidence) e.toJson()],
    'conflicts': [for (final c in conflicts) c.toJson()],
    'limitations': [for (final l in limitations) l.toJson()],
    'relations': [for (final r in relations) r.toJson()],
    'contextSources': [for (final s in contextSources) s.toJson()],
    'omissions': [for (final o in omissions) o.toJson()],
  };
}
