import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'init_process_support.dart';
import 'support/assessment_fixtures.dart';

/// Dónde vive, en el producto, cada prueba que la matriz del paquete asigna
/// por su papel: archivo relativo a `packages/` y título real.
const _implemented = {
  'additionsEditsDeletionsAndUnreadable': (
    'cli/test/assessment_freshness_test.dart',
    'deletedSourceInvalidatesWithoutHeadChange',
  ),
  'beforeAfterMismatchPreservesBytes': (
    'cli/test/assessment_recovery_test.dart',
    'a document that is neither before nor after is a conflict',
  ),
  'candidateSnapshotMismatch': (
    'cli/test/assessment_recovery_test.dart',
    'a corrupted candidate is preserved, never published',
  ),
  'claimFieldsChangeProjectionOrReject': (
    'core/test/assessment_contract_test.dart',
    'a dangling local target is rejected',
  ),
  'contextChangedBeforeRecovery': (
    'cli/test/assessment_recover_flow_test.dart',
    'contextChangedBeforeRecovery aborts and keeps the previous',
  ),
  'contextLinksMatchOriginAndKind': (
    'plugin_dart/test/assessment_context_projection_test.dart',
    'a candidate source key derives from scope, path and kind',
  ),
  'crashBeforeAfterRename': (
    'cli/test/assessment_recovery_test.dart',
    'an interrupted publication before the rename is finished',
  ),
  'currentPreviousRemainExact': (
    'cli/test/assessment_store_test.dart',
    'a new revision replaces current and keeps it as previous',
  ),
  'diagnosticFieldsRemainVisible': (
    'cli/test/assessment_presenter_test.dart',
    'publishedPartialExit65IsNotComplete',
  ),
  'expectedUnitsExactlyMatch': (
    'core/test/assessment_context_test.dart',
    'a foreign unit with the right digest is rejected',
  ),
  'fileOwnershipAndParsingEligibility': (
    'core/test/assessment_contract_test.dart',
    'a file names its own source input and its deepest unit',
  ),
  'foreignProjectIsBlocked': (
    'cli/test/assessment_preflight_test.dart',
    'foreignProjectIsBlocked',
  ),
  'freshnessNotDerivedFromExitCode': (
    'cli/test/assessment_presenter_test.dart',
    'historicalPartialExitZeroIsStillHistoricalPartial',
  ),
  'historicalPartialExitZeroIsStillHistoricalPartial': (
    'cli/test/assessment_presenter_test.dart',
    'historicalPartialExitZeroIsStillHistoricalPartial',
  ),
  'nextActionsAreImplementedArgv': (
    'cli/test/assessment_grammar_test.dart',
    'nextActionsAreImplementedArgv',
  ),
  'operationsHaveDistinctEffects': (
    'cli/test/assessment_freshness_test.dart',
    'show reads, checks and never runs the detector nor writes',
  ),
  'outcomeDoesNotOverrideCoverage': (
    'cli/test/assessment_presenter_test.dart',
    'publishedPartialExit65IsNotComplete',
  ),
  'outputFailureAfterCommitPreservesEffects': (
    'cli/test/assessment_presenter_test.dart',
    'an oversized JSON is compact with its true effects',
  ),
  'partialReobservationHasNoDisappearanceCounts': (
    'cli/test/assessment_service_test.dart',
    'S2: partialReobservationHasNoDisappearanceCounts',
  ),
  'publishedPartialExit65IsNotComplete': (
    'cli/test/assessment_presenter_test.dart',
    'publishedPartialExit65IsNotComplete',
  ),
  'responseDiscriminants': (
    'cli/test/assessment_presenter_test.dart',
    'both views come from the same result',
  ),
  'revisionChangesOnlyOnPublication': (
    'cli/test/assessment_freshness_test.dart',
    'returning without changes keeps snapshot and time',
  ),
  'roundTripPreservesEvidenceAndLimits': (
    'cli/test/assessment_presenter_test.dart',
    'roundTripPreservesEvidenceAndLimits',
  ),
  'snapshotHeaderAndContractValidation': (
    'cli/test/assessment_codec_test.dart',
    'an altered snapshotId is rejected',
  ),
  'thirdPublicationReportsRetiredRevision': (
    'cli/test/assessment_service_test.dart',
    'a third revision retires the oldest one visibly',
  ),
  'transactionIdentityAndPaths': (
    'cli/test/assessment_codec_test.dart',
    'every package fixture is accepted or rejected as indexed',
  ),
  'unknownVersionRejected': (
    'cli/test/assessment_codec_test.dart',
    'another version or kind is not this document',
  ),
  'witnessCountsAndStateAreConsistent': (
    'core/test/assessment_contract_test.dart',
    'witness counts must follow the collections',
  ),
  'wrongKindRejected': (
    'cli/test/assessment_codec_test.dart',
    'another version or kind is not this document',
  ),
};

/// Las hojas de [schema] con el mismo recorrido que el validador del
/// paquete: propiedades, ítems y definiciones; un `$ref` no es hoja.
Iterable<String> _leaves(Map<String, Object?> schema, String path) sync* {
  final properties = schema['properties'] as Map<String, Object?>?;
  final items = schema['items'] as Map<String, Object?>?;
  if (properties != null) {
    for (final MapEntry(:key, :value) in properties.entries) {
      yield* _leaves(value! as Map<String, Object?>, '$path/$key');
    }
  } else if (items != null) {
    yield* _leaves(items, '$path/*');
  } else if (!schema.containsKey(r'$ref')) {
    yield path;
  }
}

Future<Set<String>> _schemaFields() async {
  final fields = <String>{};
  for (final name in [
    'assessment.schema.json',
    'assessment-response.schema.json',
    'assessment-transaction.schema.json',
  ]) {
    final schema = (await v3Json('schemas/$name'))! as Map<String, Object?>;
    fields.addAll(_leaves(schema, '').map((p) => '$name#$p'));
    final defs = (schema[r'$defs'] as Map<String, Object?>?) ?? {};
    for (final MapEntry(:key, :value) in defs.entries) {
      fields.addAll(
        _leaves(
          value! as Map<String, Object?>,
          '',
        ).map((p) => '$name#/\$defs/$key$p'),
      );
    }
  }
  return fields;
}

void main() {
  test('every schema leaf has exactly one consumer row', () async {
    final rows = ((await v3Json('field-consumers.json'))! as List<Object?>)
        .cast<Map<String, Object?>>();
    final keys = [for (final r in rows) r['field']! as String];
    expect(keys.toSet(), hasLength(keys.length));
    expect(keys.toSet(), await _schemaFields());
  });

  test('every assigned test exists in the product by its real title', () async {
    final rows = ((await v3Json('field-consumers.json'))! as List<Object?>)
        .cast<Map<String, Object?>>();
    final packages = (await cliRoot()).parent.path;
    for (final row in rows) {
      final name = (row['test']! as String).split(': ').last;
      final (file, title) = _implemented[name]!;
      final source = File('$packages/$file').readAsStringSync();
      expect(
        source,
        contains(jsonEncode(title).replaceAll('"', "'")),
        reason: '$name → $file',
      );
    }
  });
}
