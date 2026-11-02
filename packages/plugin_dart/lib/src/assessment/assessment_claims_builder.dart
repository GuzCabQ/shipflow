import 'package:core/core.dart';

import 'assessment_context_projection.dart';
import 'assessment_diagnostics.dart';
import 'assessment_ids.dart';
import 'directive_extractor.dart';
import 'local_reference_resolver.dart';
import 'source_inventory.dart';

/// Convierte las directivas de cada archivo en afirmaciones con evidencia y
/// las admite enteras o ninguna: nunca un prefijo presentado como completo.
final class ClaimsBuilder {
  ClaimsBuilder(this.resolver, this.diagnostics);

  final LocalReferenceResolver resolver;
  final DiagnosticGroups diagnostics;
  final claims = <AssessmentClaim>[];

  /// Admite las afirmaciones de [directives] si caben en [maxClaims]; false
  /// si no, sin retener ninguna.
  bool admit(
    InventorySource source,
    List<ExtractedDirective> directives,
    int maxClaims,
  ) {
    final count = directives.fold(0, (n, d) => n + 1 + d.alternatives.length);
    if (claims.length + count > maxClaims) return false;
    final fileId = assessmentId(fileIdPrefix, fileTuple(source.path));
    for (final directive in directives) {
      claims.addAll(_claimsOf(source, fileId, directive));
    }
    return true;
  }

  List<AssessmentClaim> _claimsOf(
    InventorySource source,
    String fileId,
    ExtractedDirective d,
  ) {
    final group = assessmentId(
      groupIdPrefix,
      groupTuple(source.path, d.offset),
    );
    final conditional = d.alternatives.isNotEmpty;
    return [
      _claim(source, fileId, group, d, (
        uri: d.uri,
        location: (d.offset, d.length, d.line, d.column),
        condition: conditional
            ? AssessmentCondition.fallback
            : AssessmentCondition.always,
        conditionText: null,
      )),
      for (final a in d.alternatives)
        _claim(source, fileId, group, d, (
          uri: a.uri,
          location: (a.offset, a.length, a.line, a.column),
          condition: a.conditionText == null
              ? AssessmentCondition.unknown
              : AssessmentCondition.conditional,
          conditionText: a.conditionText,
        )),
    ];
  }

  AssessmentClaim _claim(
    InventorySource source,
    String fileId,
    String group,
    ExtractedDirective d,
    _Branch branch,
  ) {
    final (target, relation, targetFileId) = _resolve(source, d, branch);
    return AssessmentClaim(
      id: _claimId(source.path, d, relation, target, targetFileId, branch),
      witnessId: AssessmentCapability.sourceReferences.toWireName(),
      sourceFileId: fileId,
      targetFileId: targetFileId,
      targetUnitId: target.path == null
          ? null
          : unitIdOf(resolver.ownerOf(target.path!)),
      targetLabel: target.label,
      relation: relation,
      resolution: target.resolution,
      reason: target.reason,
      condition: branch.condition,
      groupId: group,
      evidence: _evidence(branch.location),
      sourceMetadata: AssessmentSourceMetadata(
        directive: d.directive,
        conditionText: branch.conditionText,
      ),
    );
  }

  /// El destino de una rama, su relación y su archivo; un destino no
  /// resuelto queda también como diagnóstico agrupado.
  (ReferenceTarget, AssessmentRelation, String?) _resolve(
    InventorySource source,
    ExtractedDirective d,
    _Branch branch,
  ) {
    final target = d.ownerName != null
        ? const ReferenceTarget.unresolved('named_owner')
        : resolver.resolve(source.path, source.unitPath, branch.uri);
    if (target.resolution == AssessmentResolution.unresolved) {
      diagnostics.add('reference_unresolved', source.path);
    }
    return (
      target,
      d.directive == 'part_of'
          ? AssessmentRelation.sourceAttachment
          : AssessmentRelation.sourceReference,
      target.path == null
          ? null
          : assessmentId(fileIdPrefix, fileTuple(target.path!)),
    );
  }
}

/// La identidad de la afirmación: ubicación, tipo, destino y condición.
String _claimId(
  String sourcePath,
  ExtractedDirective d,
  AssessmentRelation relation,
  ReferenceTarget target,
  String? targetFileId,
  _Branch branch,
) => assessmentId(
  claimIdPrefix,
  claimTuple(
    sourcePath: sourcePath,
    offset: branch.location.$1,
    relation: relation.toWireName(),
    directive: d.directive,
    targetFileId: targetFileId,
    targetLabel: target.label,
    resolution: target.resolution.toWireName(),
    condition: branch.condition.toWireName(),
    conditionText: branch.conditionText,
  ),
);

AssessmentEvidence _evidence((int, int, int, int) location) {
  final (offset, length, line, column) = location;
  return AssessmentEvidence(
    offset: offset,
    length: length,
    line: line,
    column: column,
  );
}

typedef _Branch = ({
  String? uri,
  (int, int, int, int) location,
  AssessmentCondition condition,
  String? conditionText,
});
