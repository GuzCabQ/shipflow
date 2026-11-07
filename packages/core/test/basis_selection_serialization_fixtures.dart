import 'package:core/core.dart';

import 'assessment_serialization_fixtures.dart' show SerializationCase;
import 'basis_fixtures.dart';

SerializationCase _case(
  Map<String, Object?> json,
  Map<String, Object?> Function(Map<String, Object?>) rebuild,
) => (json, rebuild);

/// Las clases de selección y de observación de fuentes, con las mismas
/// versiones de registro que el resto de las fixtures de la base.
Map<String, SerializationCase> basisSelectionCases({
  required BasisRecordVersion version,
  required BasisSourceStatus status,
  required BasisSourceReading reading,
}) => {
  ..._observationCases(status, reading),
  'BasisSelection': _case(
    BasisSelection(
      selected: [version],
      pending: [version],
      reviewTargets: [version],
      excludedCount: 4,
    ).toJson(),
    (j) => BasisSelection.fromJson(j).toJson(),
  ),
  'BasisValidationIssue': _case(
    BasisValidationIssue(code: 'invalid_reference', at: 'changes/1').toJson(),
    (j) => BasisValidationIssue.fromJson(j).toJson(),
  ),
};

Map<String, SerializationCase> _observationCases(
  BasisSourceStatus status,
  BasisSourceReading reading,
) => {
  'BasisSourceReport': _case(
    BasisSourceReport(
      statuses: [status],
      readings: [reading],
      complete: false,
    ).toJson(),
    (j) => BasisSourceReport.fromJson(j).toJson(),
  ),
  'BasisEnvironment': _case(
    BasisEnvironment(
      context: BasisIntegrity.valid,
      projectId: basisProject,
      contextDigest: digestOf(15),
      contextRecoveryPending: true,
      assessmentRecoveryPending: true,
    ).toJson(),
    (j) => BasisEnvironment.fromJson(j).toJson(),
  ),
};
