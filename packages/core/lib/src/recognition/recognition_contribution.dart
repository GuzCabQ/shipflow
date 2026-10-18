import 'recognition_evidence.dart';
import 'recognition_findings.dart';
import 'recognition_json.dart';
import 'recognition_topology.dart';

/// Lo que un plugin observó en la raíz, sin decidir el resultado global.
final class RecognitionContribution {
  RecognitionContribution({
    required List<StackCandidate> candidates,
    required List<ProjectUnit> units,
    required List<RecognitionEvidence> evidence,
    required List<RecognitionConflict> conflicts,
    required List<RecognitionLimitation> limitations,
  }) : candidates = List.unmodifiable(candidates),
       units = List.unmodifiable(units),
       evidence = List.unmodifiable(evidence),
       conflicts = List.unmodifiable(conflicts),
       limitations = List.unmodifiable(limitations);

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
      );

  final List<StackCandidate> candidates;
  final List<ProjectUnit> units;
  final List<RecognitionEvidence> evidence;
  final List<RecognitionConflict> conflicts;
  final List<RecognitionLimitation> limitations;

  Map<String, Object?> toJson() => {
    'candidates': [for (final c in candidates) c.toJson()],
    'units': [for (final u in units) u.toJson()],
    'evidence': [for (final e in evidence) e.toJson()],
    'conflicts': [for (final c in conflicts) c.toJson()],
    'limitations': [for (final l in limitations) l.toJson()],
  };
}
