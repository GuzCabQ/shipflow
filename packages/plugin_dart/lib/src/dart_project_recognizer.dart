import 'dart:io';

import 'package:core/core.dart';

import 'evidence_draft.dart';
import 'manifest_evidence.dart';
import 'observed_value.dart';
import 'path_dependency_boundary.dart';
import 'project_scanner.dart';
import 'pubspec_observer.dart';
import 'recognition_codes.dart';
import 'scan_limits.dart';
import 'toolchain_observer.dart';

const _pluginId = 'plugin_dart';
const _dartPackage = 'dart_package';
const _flutterPackage = 'flutter_package';

/// Reconoce la topología Dart/Flutter de [root], que tiene que ser canónica.
///
/// Sólo lee manifiestos y marcadores dentro de [limits]; no ejecuta
/// herramientas, no resuelve dependencias y no consulta el SDK instalado.
Future<RecognitionContribution> recognizeDartProject(
  Directory root, {
  ScanLimits limits = const ScanLimits(),
}) async {
  final scan = await scanProject(root, limits: limits);
  final observed = _Observations(root)..limitations.addAll(scan.limitations);
  scan.sources.forEach(observed.add);
  return observed.contribution();
}

final class _Observations {
  _Observations(this.root);

  final Directory root;
  final manifests = <ManifestEvidence>[];
  final markers = <ToolchainMarker>[];
  final limitations = <RecognitionLimitation>[];
  final flutterConstraints = <ConstraintEvidence>[];
  final sdkConstraints = <ConstraintEvidence>[];

  void add(ScannedSource source) {
    if (source.kind != SourceKind.manifest) {
      final (:marker, :limitation) = observeToolchainMarker(source);
      if (marker != null) markers.add(marker);
      if (limitation != null) limitations.add(limitation);
      return;
    }
    final observation = observeManifest(source);
    limitations.addAll(observation.limitations);
    if (observation.facts case final facts?) _addManifest(facts);
  }

  void _addManifest(ManifestFacts facts) {
    final evidence = ManifestEvidence(facts);
    manifests.add(evidence);
    _addConstraint(evidence.sdkConstraint, facts.sdkConstraint, sdkConstraints);
    _addConstraint(
      evidence.flutterConstraint,
      facts.flutterConstraint,
      flutterConstraints,
    );
    for (final dependency in facts.pathDependencies) {
      if (dependency.truncated) continue;
      final placement = placePathDependency(root, facts, dependency);
      if (_placementProblem(placement) case (final code, final message)?) {
        limitations.add(
          RecognitionLimitation(
            code: code,
            message: message,
            path: facts.source.path,
            blocking: true,
          ),
        );
      }
    }
  }

  /// Un adelanto truncado ya bloquea por sí mismo y no se parsea.
  void _addConstraint(
    EvidenceDraft? draft,
    ObservedValue? observed,
    List<ConstraintEvidence> into,
  ) {
    if (draft == null || observed!.truncated) return;
    final (:constraint, :limitation) = parseConstraint(draft);
    if (constraint != null) into.add(constraint);
    if (limitation != null) limitations.add(limitation);
  }

  RecognitionContribution contribution() {
    final ids = assignEvidenceIds([
      for (final m in manifests) ...m.all,
      for (final m in markers) m.evidence,
    ]);
    List<String> idsOf(Iterable<EvidenceDraft> drafts) => [
      for (final d in drafts) ids[d]!,
    ];
    return RecognitionContribution(
      candidates: [?_candidate(idsOf)],
      units: _units(idsOf),
      evidence: [
        for (final MapEntry(key: d, value: id) in ids.entries)
          RecognitionEvidence(
            id: id,
            kind: d.kind,
            path: d.path,
            value: d.value,
            fingerprint: d.fingerprint,
          ),
      ],
      conflicts: _conflicts(idsOf),
      limitations: limitations,
    );
  }

  List<RecognitionConflict> _conflicts(
    List<String> Function(Iterable<EvidenceDraft>) idsOf,
  ) => [
    for (final c in [
      ..._duplicateNames(),
      ...toolchainConflicts(
        markers: markers,
        flutterConstraints: flutterConstraints,
        sdkConstraints: sdkConstraints,
      ),
    ])
      RecognitionConflict(
        code: c.code,
        message: c.message,
        evidenceIds: idsOf(c.evidence),
      ),
  ];

  List<ConflictDraft> _duplicateNames() {
    final byName = <String, List<EvidenceDraft>>{};
    for (final manifest in manifests) {
      if (manifest.name case final name?) {
        byName.putIfAbsent(name.value, () => []).add(name);
      }
    }
    return [
      for (final MapEntry(key: name, value: drafts) in byName.entries)
        if (drafts.length > 1)
          ConflictDraft(
            ConflictCode.duplicatePackageName,
            'el nombre de paquete «$name» aparece en ${drafts.length} '
            'manifiestos',
            drafts,
          ),
    ];
  }

  /// Flutter si algo lo señala; si no, Dart si hay al menos un paquete.
  StackCandidate? _candidate(
    List<String> Function(Iterable<EvidenceDraft>) idsOf,
  ) {
    final flutter = [
      for (final m in manifests) ...m.flutterSignals,
      for (final m in markers) m.evidence,
    ];
    if (flutter.isNotEmpty) {
      return StackCandidate(
        id: 'flutter',
        displayName: 'Flutter',
        pluginId: _pluginId,
        evidenceIds: idsOf(flutter),
      );
    }
    final names = [for (final m in manifests) ?m.name];
    if (names.isEmpty) return null;
    return StackCandidate(
      id: 'dart',
      displayName: 'Dart',
      pluginId: _pluginId,
      evidenceIds: idsOf(names),
    );
  }

  List<ProjectUnit> _units(
    List<String> Function(Iterable<EvidenceDraft>) idsOf,
  ) {
    final named = [
      for (final m in manifests)
        if (m.name != null) m,
    ]..sort((a, b) => a.unitPath.compareTo(b.unitPath));
    return [
      for (final (index, m) in named.indexed)
        ProjectUnit(
          id: 'u${(index + 1).toString().padLeft(4, '0')}',
          name: m.name!.value,
          kind: m.flutterSignals.isEmpty ? _dartPackage : _flutterPackage,
          path: m.unitPath,
          evidenceIds: idsOf(m.all),
        ),
    ];
  }
}

/// Por qué una dependencia local no se atraviesa, o null si queda dentro.
(String, String)? _placementProblem(PathDependencyPlacement placement) =>
    switch (placement) {
      PathDependencyPlacement.inside => null,
      PathDependencyPlacement.outside => (
        LimitationCode.pathDependencyOutsideRoot,
        'una dependencia local sale de la raíz y no se atraviesa',
      ),
      PathDependencyPlacement.unresolved => (
        LimitationCode.pathDependencyUnresolved,
        'una dependencia local no se pudo resolver y no se atraviesa',
      ),
    };
