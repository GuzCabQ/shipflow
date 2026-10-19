import 'dart:convert';

import 'package:core/core.dart';
import 'package:pub_semver/pub_semver.dart';

import 'derived_observation_budget.dart';
import 'evidence_draft.dart';
import 'project_scanner.dart';
import 'recognition_codes.dart';

/// Una versión exacta declarada por un marcador de la raíz.
final class ToolchainMarker {
  const ToolchainMarker(this.evidence, this.version);

  final EvidenceDraft evidence;
  final Version version;
}

/// Una restricción de manifiesto ya parseada.
final class ConstraintEvidence {
  const ConstraintEvidence(this.evidence, this.constraint);

  final EvidenceDraft evidence;
  final VersionConstraint constraint;
}

({ToolchainMarker? marker, RecognitionLimitation? limitation})
observeToolchainMarker(ScannedSource source, DerivedObservationBudget budget) {
  final declared = _declaredVersion(source);
  final version = declared == null ? null : _exactVersion(declared);
  if (declared == null || version == null) {
    return (
      marker: null,
      limitation: _blocking(
        budget,
        LimitationCode.invalidToolchainMarker,
        'el marcador no declara una única versión exacta',
        source.path,
      ),
    );
  }
  final kind = source.kind == SourceKind.fvmConfig
      ? EvidenceKind.fvm
      : EvidenceKind.flutterVersionFile;
  budget.row([kind, source.path, declared, source.read.fingerprint]);
  final evidence = EvidenceDraft(
    kind: kind,
    path: source.path,
    value: declared,
    fingerprint: source.read.fingerprint,
  );
  return (marker: ToolchainMarker(evidence, version), limitation: null);
}

/// El texto de la versión: el string `flutter` de `.fvmrc`, o la única línea
/// no vacía de `flutter-version.txt`.
String? _declaredVersion(ScannedSource source) {
  try {
    final text = utf8.decode(source.read.bytes);
    if (source.kind == SourceKind.fvmConfig) {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> && decoded['flutter'] is String
          ? decoded['flutter']! as String
          : null;
    }
    final lines = text.trim().split('\n');
    return lines.length == 1 && lines.single.trim().isNotEmpty
        ? lines.single.trim()
        : null;
  } on FormatException {
    return null;
  }
}

Version? _exactVersion(String text) {
  try {
    return Version.parse(text);
  } on FormatException {
    return null;
  }
}

({ConstraintEvidence? constraint, RecognitionLimitation? limitation})
parseConstraint(EvidenceDraft evidence, DerivedObservationBudget budget) {
  try {
    final parsed = VersionConstraint.parse(evidence.value);
    return (constraint: ConstraintEvidence(evidence, parsed), limitation: null);
  } on FormatException {
    return (
      constraint: null,
      limitation: _blocking(
        budget,
        LimitationCode.invalidConstraint,
        '«${evidence.value}» no es una restricción de versión válida',
        evidence.path,
      ),
    );
  }
}

/// Las incompatibilidades entre marcadores y restricciones, sin elegir
/// ninguna: cada conflicto conserva todas sus evidencias y se cobra a
/// [budget] antes de construirse, uno por uno.
List<ConflictDraft> toolchainConflicts({
  required List<ToolchainMarker> markers,
  required List<ConstraintEvidence> flutterConstraints,
  required List<ConstraintEvidence> sdkConstraints,
  required DerivedObservationBudget budget,
}) => [
  if (markers.map((m) => m.version).toSet().length > 1)
    _versionsDisagree(budget, markers),
  for (final marker in markers)
    for (final constraint in flutterConstraints)
      if (!constraint.constraint.allows(marker.version))
        _outsideConstraint(budget, marker, constraint),
  ?_disjoint(
    budget,
    ConflictCode.flutterConstraintsDisjoint,
    flutterConstraints,
  ),
  ?_disjoint(budget, ConflictCode.sdkConstraintsDisjoint, sdkConstraints),
];

ConflictDraft _versionsDisagree(
  DerivedObservationBudget budget,
  List<ToolchainMarker> markers,
) => conflictDraft(
  budget,
  ConflictCode.toolchainVersionsDisagree,
  [
    'los marcadores declaran versiones exactas distintas: ',
    ..._listed([for (final m in markers) '${m.evidence.path} ${m.version}']),
  ],
  [for (final m in markers) m.evidence],
);

ConflictDraft _outsideConstraint(
  DerivedObservationBudget budget,
  ToolchainMarker marker,
  ConstraintEvidence constraint,
) => conflictDraft(
  budget,
  ConflictCode.toolchainOutsideConstraint,
  [
    'la versión ${marker.version} de ${marker.evidence.path} no ',
    'cumple ${constraint.constraint} de ${constraint.evidence.path}',
  ],
  [marker.evidence, constraint.evidence],
);

ConflictDraft? _disjoint(
  DerivedObservationBudget budget,
  String code,
  List<ConstraintEvidence> constraints,
) {
  if (constraints.isEmpty) return null;
  final common = constraints
      .map((c) => c.constraint)
      .reduce((a, b) => a.intersect(b));
  if (!common.isEmpty) return null;
  return conflictDraft(
    budget,
    code,
    [
      'las restricciones no tienen ninguna versión en común: ',
      ..._listed([
        for (final c in constraints) '${c.constraint} (${c.evidence.path})',
      ]),
    ],
    [for (final c in constraints) c.evidence],
  );
}

/// [items] separados por `, `, como partes sueltas que se cobran antes de
/// unirse.
List<String> _listed(List<String> items) => [
  for (final (index, item) in items.indexed) ...[if (index > 0) ', ', item],
];

RecognitionLimitation _blocking(
  DerivedObservationBudget budget,
  String code,
  String message,
  String path,
) {
  budget.row([code, message, path]);
  return RecognitionLimitation(
    code: code,
    message: message,
    path: path,
    blocking: true,
  );
}
