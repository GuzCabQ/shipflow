import 'dart:io';

import 'package:core/core.dart';

import 'derived_observation_budget.dart';
import 'evidence_draft.dart';
import 'manifest_evidence.dart';
import 'observed_value.dart';
import 'local_relation_resolver.dart';
import 'project_scanner.dart';
import 'context_source_rule.dart';
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
///
/// [contextSources] es el catálogo de fuentes candidatas que la raíz de
/// composición entrega: sólo se consultan sus metadatos.
Future<RecognitionContribution> recognizeDartProject(
  Directory root, {
  ScanLimits limits = const ScanLimits(),
  ReportLimits reportLimits = const ReportLimits(),
  List<ContextSourceRule> contextSources = const [],
}) => recognizeListing(
  root,
  limits: limits,
  reportLimits: reportLimits,
  contextSources: contextSources,
);

/// [recognizeDartProject] con el listado de directorios inyectable, para que
/// las pruebas comprueben que el orden del sistema no cambia el resultado.
Future<RecognitionContribution> recognizeListing(
  Directory root, {
  ScanLimits limits = const ScanLimits(),
  ReportLimits reportLimits = const ReportLimits(),
  DirectoryLister list = listWithoutFollowing,
  List<ContextSourceRule> contextSources = const [],
}) async {
  final budget = DerivedObservationBudget(reportLimits);
  final scan = await scanProject(
    root,
    limits: limits,
    list: list,
    budget: budget,
    contextSources: contextSources,
  );
  final observed = _Observations(root, budget, scan)
    ..limitations.addAll(scan.limitations)
    ..limitations.addAll(scan.manifestLimitations);
  scan.manifests.forEach(observed.addManifest);
  scan.sources
      .where((s) => s.kind != SourceKind.manifest)
      .forEach(observed.addMarker);
  return observed.contribution();
}

final class _Observations {
  _Observations(this.root, this.budget, this.scan);

  final Directory root;
  final DerivedObservationBudget budget;
  final ScanResult scan;
  final manifests = <ManifestEvidence>[];
  final markers = <ToolchainMarker>[];
  final limitations = <RecognitionLimitation>[];
  final flutterConstraints = <ConstraintEvidence>[];
  final sdkConstraints = <ConstraintEvidence>[];

  void addMarker(ScannedSource source) {
    final (:marker, :limitation) = observeToolchainMarker(source, budget);
    if (marker != null) markers.add(marker);
    if (limitation != null) limitations.add(limitation);
  }

  /// Un manifiesto que el escáner ya analizó y cobró: aquí sólo se usan
  /// sus hechos.
  void addManifest(ManifestEvidence evidence) {
    final facts = evidence.facts;
    manifests.add(evidence);
    _addConstraint(evidence.sdkConstraint, facts.sdkConstraint, sdkConstraints);
    _addConstraint(
      evidence.flutterConstraint,
      facts.flutterConstraint,
      flutterConstraints,
    );
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
    final units = _units(idsOf);
    final local = _localRelations(units, ids);
    return RecognitionContribution(
      candidates: [?_candidate(idsOf)],
      units: units,
      evidence: [
        for (final MapEntry(key: d, value: id) in ids.entries) _evidence(d, id),
      ],
      conflicts: _conflicts(ids, local.conflicts),
      limitations: [...limitations, ...local.limitations],
      relations: local.relations,
      contextSources: scan.contextSources,
      omissions: _omissions(idsOf),
    );
  }

  /// Las relaciones locales, sobre lo ya recorrido y con los IDs asignados.
  ({
    List<RecognitionRelation> relations,
    List<RecognitionLimitation> limitations,
    List<ConflictDraft> conflicts,
  })
  _localRelations(List<ProjectUnit> units, Map<EvidenceDraft, String> ids) =>
      resolveLocalRelations(
        root: root,
        manifests: manifests,
        units: units,
        omissions: scan.omissions,
        ids: ids,
        budget: budget,
      );

  /// Las referencias de cada omisión se admiten al proyectarla; su fila ya
  /// se cobró al encontrarla.
  List<RecognitionOmission> _omissions(
    List<String> Function(Iterable<EvidenceDraft>) idsOf,
  ) => [
    for (final o in scan.omissions)
      RecognitionOmission(
        path: o.path,
        rule: o.rule,
        evidenceIds: idsOf(o.evidence),
      ),
  ];

  /// Las posiciones de referencia ya se cobraron con cada borrador; aquí
  /// sólo los bytes de los IDs, que recién existen.
  List<RecognitionConflict> _conflicts(
    Map<EvidenceDraft, String> ids,
    List<ConflictDraft> relations,
  ) => [
    for (final c in [
      ...relations,
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

/// Una evidencia ya cobrada, con el ID que recién se le asignó.
RecognitionEvidence _evidence(EvidenceDraft d, String id) =>
    RecognitionEvidence(
      id: id,
      kind: d.kind,
      role: evidenceRoleOf(d.kind),
      label: evidenceLabelOf(d.kind),
      path: d.path,
      value: d.value,
      fingerprint: d.fingerprint,
    );
