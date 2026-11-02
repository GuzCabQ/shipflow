import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assessment_serialization_fixtures.dart';
import 'context_fixtures.dart' as context;
import 'context_serialization_fixtures.dart';
import 'recognition_fixtures.dart';

void main() {
  group('serializes every status with its specified wire name', () {
    test('estado del reconocimiento', () {
      expect(RecognitionStatus.values.map((s) => s.toWireName()), [
        'recognized',
        'ambiguous',
        'unsupported',
        'invalid_root',
      ]);
      for (final status in RecognitionStatus.values) {
        expect(RecognitionStatus.fromWireName(status.toWireName()), status);
      }
    });

    test('estado y relación del repositorio', () {
      expect(RepositoryStatus.values.map((s) => s.toWireName()), [
        'detected',
        'absent',
        'indeterminate',
      ]);
      expect(RepositoryRelation.values.map((r) => r.toWireName()), [
        'same',
        'ancestor',
        'none',
      ]);
    });

    test('un nombre desconocido se rechaza', () {
      expect(
        () => RecognitionStatus.fromWireName('invalidRoot'),
        throwsFormatException,
      );
      expect(() => RepositoryStatus.fromWireName('x'), throwsFormatException);
      expect(() => RepositoryRelation.fromWireName('x'), throwsFormatException);
    });
  });

  group('round trips every public field without loss', () {
    // Cada caso reconstruye desde el JSON y vuelve a escribir.
    final cases =
        <
          String,
          (
            Map<String, Object?>,
            Map<String, Object?> Function(Map<String, Object?>),
          )
        >{
          'ReportLimits': (
            const ReportLimits.extended().toJson(),
            (j) => ReportLimits.fromJson(j).toJson(),
          ),
          'DerivedUsage': (
            const DerivedUsage(items: 7, textBytes: 11).toJson(),
            (j) => DerivedUsage.fromJson(j).toJson(),
          ),
          'ReportLimitExceeded': (
            const ReportLimitExceeded(ReportLimitDimension.jsonBytes).toJson(),
            (j) => ReportLimitExceeded.fromJson(j).toJson(),
          ),
          'RecognitionEvidence': (
            evidence.toJson(),
            (j) => RecognitionEvidence.fromJson(j).toJson(),
          ),
          'StackCandidate': (
            candidate.toJson(),
            (j) => StackCandidate.fromJson(j).toJson(),
          ),
          'ProjectUnit': (
            unit.toJson(),
            (j) => ProjectUnit.fromJson(j).toJson(),
          ),
          'RecognitionConflict': (
            conflict.toJson(),
            (j) => RecognitionConflict.fromJson(j).toJson(),
          ),
          'RecognitionLimitation': (
            limitation.toJson(),
            (j) => RecognitionLimitation.fromJson(j).toJson(),
          ),
          'RepositoryContext': (
            repository.toJson(),
            (j) => RepositoryContext.fromJson(j).toJson(),
          ),
          'ProposedAction': (
            action.toJson(),
            (j) => ProposedAction.fromJson(j).toJson(),
          ),
          'RecognitionProposal': (
            proposal.toJson(),
            (j) => RecognitionProposal.fromJson(j).toJson(),
          ),
          'RecognitionEffects': (
            effects.toJson(),
            (j) => RecognitionEffects.fromJson(j).toJson(),
          ),
          'RecognitionRelation': (
            relation.toJson(),
            (j) => RecognitionRelation.fromJson(j).toJson(),
          ),
          'ContextSource': (
            contextSource.toJson(),
            (j) => ContextSource.fromJson(j).toJson(),
          ),
          'RecognitionOmission': (
            omission.toJson(),
            (j) => RecognitionOmission.fromJson(j).toJson(),
          ),
          'RecognitionContribution': (
            contribution.toJson(),
            (j) => RecognitionContribution.fromJson(j).toJson(),
          ),
          'RecognitionReport': (
            report.toJson(),
            (j) => RecognitionReport.fromJson(j).toJson(),
          ),
          'AuthorizedOmission': (
            AuthorizedOmission(
              relativePath: 'shipflow',
              rule: OmissionRule.toolState,
            ).toJson(),
            (j) => AuthorizedOmission.fromJson(j).toJson(),
          ),
          'ContextProducer': (
            context.projectContext().producer.toJson(),
            (j) => ContextProducer.fromJson(j).toJson(),
          ),
          'ProjectContext': (
            context.projectContext().toJson(),
            (j) => ProjectContext.fromJson(j).toJson(),
          ),
          'PortableRecognition': (
            context.PortableParts().build().toJson(),
            (j) => PortableRecognition.fromJson(j).toJson(),
          ),
          'GitBinding': (
            binding.toJson(),
            (j) => GitBinding.fromJson(j).toJson(),
          ),
          'ManagedExcludeRecord': (
            managedExclude.toJson(),
            (j) => ManagedExcludeRecord.fromJson(j).toJson(),
          ),
          'LocalSettings': (
            settings.toJson(),
            (j) => LocalSettings.fromJson(j).toJson(),
          ),
          'TransactionTarget': (
            target.toJson(),
            (j) => TransactionTarget.fromJson(j).toJson(),
          ),
          'TransactionStaging': (
            staging.toJson(),
            (j) => TransactionStaging.fromJson(j).toJson(),
          ),
          'TransactionExclude': (
            exclude.toJson(),
            (j) => TransactionExclude.fromJson(j).toJson(),
          ),
          'ContextTransaction': (
            journal.toJson(),
            (j) => ContextTransaction.fromJson(j).toJson(),
          ),
          'ContextSharing': (
            sharing.toJson(),
            (j) => ContextSharing.fromJson(j).toJson(),
          ),
          'ContextCheck': (
            check.toJson(),
            (j) => ContextCheck.fromJson(j).toJson(),
          ),
          'ContextDiagnostic': (
            diagnostic.toJson(),
            (j) => ContextDiagnostic.fromJson(j).toJson(),
          ),
          'ContextEffects': (
            contextEffects.toJson(),
            (j) => ContextEffects.fromJson(j).toJson(),
          ),
          'ContextNextAction': (
            nextAction.toJson(),
            (j) => ContextNextAction.fromJson(j).toJson(),
          ),
          'ContextFormatException': (
            formatError.toJson(),
            (j) => ContextFormatException.fromJson(j).toJson(),
          ),
          'ContextOperationResult': (
            operationResult.toJson(),
            (j) => ContextOperationResult.fromJson(j).toJson(),
          ),
        };
    for (final MapEntry(key: name, value: (json, rebuild)) in cases.entries) {
      test(name, () {
        final encoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
        expect(jsonEncode(rebuild(encoded)), jsonEncode(json));
      });
    }

    // Los nombres van literales: el check de la frontera exige el caso de
    // cada clase serializable de core por su nombre en este archivo.
    final assessment = assessmentSerializationCases();
    const assessmentNames = [
      'AssessmentUnit',
      'AssessmentInput',
      'AssessmentFile',
      'AssessmentProducer',
      'AssessmentEvidence',
      'AssessmentSourceMetadata',
      'AssessmentClaim',
      'AssessmentWitness',
      'AssessmentContextLink',
      'AssessmentDiagnostic',
      'AssessmentSnapshot',
      'AssessmentDocument',
      'AssessmentLimits',
      'AssessmentObservation',
      'AssessmentMetrics',
      'AssessmentConnection',
      'AssessmentComparison',
      'AssessmentRecognitionInput',
      'AssessmentContextBasis',
      'AssessmentTransaction',
      'AssessmentEffects',
      'AssessmentNextAction',
      'AssessmentResult',
    ];
    test('every assessment case has its literal name', () {
      expect(assessment.keys.toSet(), assessmentNames.toSet());
    });
    for (final name in assessmentNames) {
      test(name, () {
        final (json, rebuild) = assessment[name]!;
        final encoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
        expect(jsonEncode(rebuild(encoded)), jsonEncode(json));
      });
    }

    test('los campos nullable viajan presentes como null', () {
      const quiet = RecognitionLimitation(
        code: 'c',
        message: 'm',
        path: null,
        blocking: false,
      );
      const absent = RepositoryContext(
        status: RepositoryStatus.absent,
        root: null,
        relation: RepositoryRelation.none,
      );
      expect(quiet.toJson(), containsPair('path', null));
      expect(absent.toJson(), containsPair('root', null));
      expect(
        RecognitionLimitation.fromJson(quiet.toJson()).toJson(),
        quiet.toJson(),
      );
    });

    test('el reporte escribe sus campos en el orden del protocolo', () {
      expect(report.toJson().keys, [
        'status',
        'requestedRoot',
        'resolvedRoot',
        'repository',
        'recognitionScope',
        'candidates',
        'units',
        'evidence',
        'conflicts',
        'limitations',
        'relations',
        'contextSources',
        'omissions',
        'proposal',
        'effects',
      ]);
      expect(report.toJson()['status'], 'ambiguous');
    });
  });
}
