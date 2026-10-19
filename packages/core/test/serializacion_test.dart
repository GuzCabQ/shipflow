import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

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
        };
    for (final MapEntry(key: name, value: (json, rebuild)) in cases.entries) {
      test(name, () {
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
