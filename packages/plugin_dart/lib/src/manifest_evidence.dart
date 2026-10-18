import 'evidence_draft.dart';
import 'pubspec_observer.dart';
import 'recognition_codes.dart';

/// Las evidencias de un manifiesto, agrupadas por lo que cada una sostiene.
final class ManifestEvidence {
  ManifestEvidence(this.facts)
    : name = _draft(facts, EvidenceKind.packageName, facts.name),
      sdkConstraint = _draft(
        facts,
        EvidenceKind.sdkConstraint,
        facts.sdkConstraint,
      ),
      flutterConstraint = _draft(
        facts,
        EvidenceKind.flutterConstraint,
        facts.flutterConstraint,
      ),
      flutterDependency = facts.flutterDependency
          ? _draft(facts, EvidenceKind.flutterDependency, 'sdk: flutter')
          : null,
      pathDependencies = List.unmodifiable([
        for (final d in facts.pathDependencies)
          _draft(facts, EvidenceKind.pathDependency, d.evidenceValue)!,
      ]),
      workspace = List.unmodifiable([
        for (final member in facts.workspace)
          _draft(facts, EvidenceKind.workspaceMember, member)!,
      ]);

  final ManifestFacts facts;
  final EvidenceDraft? name;
  final EvidenceDraft? sdkConstraint;
  final EvidenceDraft? flutterConstraint;
  final EvidenceDraft? flutterDependency;
  final List<EvidenceDraft> pathDependencies;
  final List<EvidenceDraft> workspace;

  List<EvidenceDraft> get all => [
    ?name,
    ?sdkConstraint,
    ?flutterConstraint,
    ?flutterDependency,
    ...pathDependencies,
    ...workspace,
  ];

  /// Lo que hace de este paquete uno Flutter.
  List<EvidenceDraft> get flutterSignals => [
    ?flutterConstraint,
    ?flutterDependency,
  ];

  /// El directorio del manifiesto, relativo a la raíz; `.` es la raíz.
  String get unitPath {
    final path = facts.source.path;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '.' : path.substring(0, slash);
  }
}

EvidenceDraft? _draft(ManifestFacts facts, String kind, String? value) =>
    value == null
    ? null
    : EvidenceDraft(
        kind: kind,
        path: facts.source.path,
        value: value,
        fingerprint: facts.source.read.fingerprint,
      );
