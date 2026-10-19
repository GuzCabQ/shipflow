import 'dart:io';

import 'package:core/core.dart';

import 'derived_observation_budget.dart';
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
/// Lo que retiene se cobra a un único presupuesto de [reportLimits] antes de
/// construirse; si no cabe, lanza [ReportLimitExceeded] y no devuelve nada.
Future<RecognitionContribution> recognizeDartProject(
  Directory root, {
  ScanLimits limits = const ScanLimits(),
  ReportLimits reportLimits = const ReportLimits(),
}) => recognizeListing(root, limits: limits, reportLimits: reportLimits);

/// [recognizeDartProject] con el listado de directorios inyectable, para que
/// las pruebas comprueben que el orden del sistema no cambia el resultado.
Future<RecognitionContribution> recognizeListing(
  Directory root, {
  ScanLimits limits = const ScanLimits(),
  ReportLimits reportLimits = const ReportLimits(),
  DirectoryLister list = listWithoutFollowing,
}) async {
  final budget = DerivedObservationBudget(reportLimits);
  final scan = await scanProject(
    root,
    limits: limits,
    list: list,
    budget: budget,
  );
  final observed = _Observations(root, budget)
    ..limitations.addAll(scan.limitations);
  scan.sources.forEach(observed.add);
  return observed.contribution();
}

final class _Observations {
  _Observations(this.root, this.budget);

  final Directory root;
  final DerivedObservationBudget budget;
  final manifests = <ManifestEvidence>[];
  final markers = <ToolchainMarker>[];
  final limitations = <RecognitionLimitation>[];
  final flutterConstraints = <ConstraintEvidence>[];
  final sdkConstraints = <ConstraintEvidence>[];

  void add(ScannedSource source) {
    if (source.kind != SourceKind.manifest) {
      final (:marker, :limitation) = observeToolchainMarker(source, budget);
      if (marker != null) markers.add(marker);
      if (limitation != null) limitations.add(limitation);
      return;
    }
    final observation = observeManifest(source, budget: budget);
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
      final problem = _placementProblem(placement, dependency.evidenceValue);
      if (problem case (final code, final message)?) {
        budget.row([code, message, facts.source.path]);
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
    final (:constraint, :limitation) = parseConstraint(draft, budget);
    if (constraint != null) into.add(constraint);
    if (limitation != null) limitations.add(limitation);
  }

  RecognitionContribution contribution() {
    final ids = assignEvidenceIds([
      for (final m in manifests) ...m.all,
      for (final m in markers) m.evidence,
    ], budget);
    // Cada posición de referencia es un elemento más, con los bytes del ID.
    List<String> idsOf(Iterable<EvidenceDraft> drafts) => budget
        .admitEach(drafts, textsOf: (d) => [ids[d]!], build: (d) => ids[d]!)
        .toList();
    return RecognitionContribution(
      candidates: [?_candidate(idsOf)],
      units: _units(idsOf),
      evidence: [
        for (final MapEntry(key: d, value: id) in ids.entries)
          RecognitionEvidence(
            id: id,
            kind: d.kind,
            role: evidenceRoleOf(d.kind),
            label: evidenceLabelOf(d.kind),
            path: d.path,
            value: d.value,
            fingerprint: d.fingerprint,
          ),
      ],
      conflicts: _conflicts(ids),
      limitations: limitations,
    );
  }

  /// Las posiciones de referencia ya se cobraron con cada borrador; aquí
  /// sólo los bytes de los IDs, que recién existen.
  List<RecognitionConflict> _conflicts(Map<EvidenceDraft, String> ids) => [
    for (final c in [
      ..._duplicateNames(),
      ...toolchainConflicts(
        markers: markers,
        flutterConstraints: flutterConstraints,
        sdkConstraints: sdkConstraints,
        budget: budget,
      ),
    ])
      RecognitionConflict(
        code: c.code,
        message: c.message,
        evidenceIds: [for (final d in c.evidence) _chargedId(ids[d]!)],
      ),
  ];

  String _chargedId(String id) {
    budget.charge(texts: [id]);
    return id;
  }

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
          admitConflict(
            budget,
            ConflictCode.duplicatePackageName,
            'el nombre de paquete «$name» aparece en ${drafts.length} '
            'manifiestos',
            drafts,
            evidenceOf: (d) => d,
          ),
    ];
  }

  /// Flutter si algo lo señala; si no, Dart si hay al menos un paquete.
  StackCandidate? _candidate(
    List<String> Function(Iterable<EvidenceDraft>) idsOf,
  ) {
    // Perezosas: cada referencia se admite antes de recorrer la siguiente.
    final flutter = manifests
        .expand((m) => m.flutterSignals)
        .followedBy(markers.map((m) => m.evidence));
    if (flutter.isNotEmpty) {
      budget.row(const ['flutter', 'Flutter', _pluginId]);
      return StackCandidate(
        id: 'flutter',
        displayName: 'Flutter',
        pluginId: _pluginId,
        evidenceIds: idsOf(flutter),
      );
    }
    final names = manifests.map((m) => m.name).nonNulls;
    if (names.isEmpty) return null;
    budget.row(const ['dart', 'Dart', _pluginId]);
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
    return [for (final (index, m) in named.indexed) _unit(index, m, idsOf)];
  }

  ProjectUnit _unit(
    int index,
    ManifestEvidence m,
    List<String> Function(Iterable<EvidenceDraft>) idsOf,
  ) {
    final id = 'u${(index + 1).toString().padLeft(4, '0')}';
    final kind = m.flutterSignals.isEmpty ? _dartPackage : _flutterPackage;
    budget.row([id, m.name!.value, kind, m.unitPath]);
    return ProjectUnit(
      id: id,
      name: m.name!.value,
      kind: kind,
      path: m.unitPath,
      evidenceIds: idsOf(m.all),
    );
  }
}

/// Por qué la dependencia local [declared] no se atraviesa, o null si queda
/// dentro. [declared] es su evidencia, `<sección>.<nombre>: <ruta>`, entera.
(String, String)? _placementProblem(
  PathDependencyPlacement placement,
  String declared,
) => switch (placement) {
  PathDependencyPlacement.inside => null,
  PathDependencyPlacement.outside => (
    LimitationCode.pathDependencyOutsideRoot,
    'la dependencia local «$declared» sale de la raíz y no se atraviesa',
  ),
  PathDependencyPlacement.unresolved => (
    LimitationCode.pathDependencyUnresolved,
    'la dependencia local «$declared» no se pudo resolver y no se atraviesa',
  ),
};
