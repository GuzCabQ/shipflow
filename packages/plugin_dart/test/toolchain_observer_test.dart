import 'dart:convert';

import 'package:plugin_dart/src/evidence_draft.dart';
import 'package:plugin_dart/src/project_scanner.dart';
import 'package:plugin_dart/src/recognition_codes.dart';
import 'package:plugin_dart/src/stable_file_reader.dart';
import 'package:core/core.dart';
import 'package:plugin_dart/src/derived_observation_budget.dart';
import 'package:plugin_dart/src/toolchain_observer.dart'
    hide observeToolchainMarker, parseConstraint, toolchainConflicts;
import 'package:plugin_dart/src/toolchain_observer.dart' as toolchain;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

ScannedSource marker(SourceKind kind, String text) => ScannedSource(
  kind == SourceKind.fvmConfig ? '.fvmrc' : 'flutter-version.txt',
  kind,
  StableSource(utf8.encode(text), 'sha256:${'1' * 64}'),
);

EvidenceDraft constraintDraft(String kind, String value, String path) =>
    EvidenceDraft(
      kind: kind,
      path: path,
      value: value,
      fingerprint: 'sha256:${'2' * 64}',
    );

ConstraintEvidence constraint(String text, {String path = 'pubspec.yaml'}) =>
    parseConstraint(
      constraintDraft(EvidenceKind.flutterConstraint, text, path),
    ).constraint!;

ToolchainMarker version(SourceKind kind, String text) =>
    observeToolchainMarker(marker(kind, text)).marker!;

void main() {
  group('marcadores', () {
    test('.fvmrc con un string flutter', () {
      final observed = observeToolchainMarker(
        marker(SourceKind.fvmConfig, '{"flutter": "3.38.7", "otro": 1}'),
      );
      expect(observed.marker!.version, Version.parse('3.38.7'));
      expect(observed.marker!.evidence.kind, EvidenceKind.fvm);
      expect(observed.marker!.evidence.path, '.fvmrc');
      expect(observed.marker!.evidence.value, '3.38.7');
      expect(observed.limitation, isNull);
    });

    test('flutter-version.txt con una sola versión', () {
      final observed = observeToolchainMarker(
        marker(SourceKind.flutterVersionFile, '3.44.8\n'),
      );
      expect(observed.marker!.version, Version.parse('3.44.8'));
      expect(observed.marker!.evidence.kind, EvidenceKind.flutterVersionFile);
    });

    for (final (kind, text) in [
      (SourceKind.fvmConfig, 'no es json'),
      (SourceKind.fvmConfig, '["3.0.0"]'),
      (SourceKind.fvmConfig, '{"flutter": 3}'),
      (SourceKind.fvmConfig, '{"otro": "3.0.0"}'),
      (SourceKind.fvmConfig, '{"flutter": "estable"}'),
      (SourceKind.flutterVersionFile, ''),
      (SourceKind.flutterVersionFile, '  \n'),
      (SourceKind.flutterVersionFile, '3.0.0\n3.1.0\n'),
      (SourceKind.flutterVersionFile, '^3.0.0'),
    ]) {
      test('${kind.name} malformado «$text» es limitación, no conflicto', () {
        final observed = observeToolchainMarker(marker(kind, text));
        expect(observed.marker, isNull);
        expect(
          observed.limitation!.code,
          LimitationCode.invalidToolchainMarker,
        );
        expect(observed.limitation!.blocking, isTrue);
      });
    }
  });

  group('restricciones', () {
    test('una restricción malformada es limitación', () {
      final parsed = parseConstraint(
        constraintDraft(EvidenceKind.sdkConstraint, '^^3', 'a/pubspec.yaml'),
      );
      expect(parsed.constraint, isNull);
      expect(parsed.limitation!.code, LimitationCode.invalidConstraint);
      expect(parsed.limitation!.path, 'a/pubspec.yaml');
    });
  });

  group('compatibilidad', () {
    List<String> conflictCodes(List<ConflictDraft> conflicts) => [
      for (final c in conflicts) c.code,
    ];

    test('marcadores que coinciden y caben en la restricción', () {
      expect(
        toolchainConflicts(
          markers: [
            version(SourceKind.fvmConfig, '{"flutter": "3.44.8"}'),
            version(SourceKind.flutterVersionFile, '3.44.8'),
          ],
          flutterConstraints: [constraint('^3.44.8')],
          sdkConstraints: const [],
        ),
        isEmpty,
      );
    });

    test('versiones exactas distintas entre marcadores', () {
      final conflicts = toolchainConflicts(
        markers: [
          version(SourceKind.fvmConfig, '{"flutter": "3.44.8"}'),
          version(SourceKind.flutterVersionFile, '3.44.9'),
        ],
        flutterConstraints: const [],
        sdkConstraints: const [],
      );
      expect(conflictCodes(conflicts), [
        ConflictCode.toolchainVersionsDisagree,
      ]);
      expect(conflicts.single.evidence.map((e) => e.path), [
        '.fvmrc',
        'flutter-version.txt',
      ]);
    });

    test('una versión exacta que la restricción no permite', () {
      final conflicts = toolchainConflicts(
        markers: [version(SourceKind.fvmConfig, '{"flutter": "3.38.7"}')],
        flutterConstraints: [constraint('^3.44.8')],
        sdkConstraints: const [],
      );
      expect(conflictCodes(conflicts), [
        ConflictCode.toolchainOutsideConstraint,
      ]);
      expect(conflicts.single.evidence.map((e) => e.value), [
        '3.38.7',
        '^3.44.8',
      ]);
    });

    test('restricciones de flutter sin intersección', () {
      expect(
        conflictCodes(
          toolchainConflicts(
            markers: const [],
            flutterConstraints: [
              constraint('^3.0.0', path: 'a/pubspec.yaml'),
              constraint('^2.0.0', path: 'b/pubspec.yaml'),
            ],
            sdkConstraints: const [],
          ),
        ),
        [ConflictCode.flutterConstraintsDisjoint],
      );
    });

    test('restricciones que se solapan no son conflicto', () {
      expect(
        toolchainConflicts(
          markers: const [],
          flutterConstraints: [constraint('>=3.0.0'), constraint('<3.5.0')],
          sdkConstraints: [constraint('^3.1.0'), constraint('>=3.2.0 <4.0.0')],
        ),
        isEmpty,
      );
    });

    test('restricciones del SDK sin intersección', () {
      expect(
        conflictCodes(
          toolchainConflicts(
            markers: const [],
            flutterConstraints: const [],
            sdkConstraints: [constraint('^3.0.0'), constraint('<2.0.0')],
          ),
        ),
        [ConflictCode.sdkConstraintsDisjoint],
      );
    });
  });
}

/// Cada llamada con un presupuesto propio, holgado: estas pruebas miran la
/// interpretación, no el cobro.
DerivedObservationBudget budget() =>
    DerivedObservationBudget(const ReportLimits());

({ConstraintEvidence? constraint, RecognitionLimitation? limitation})
parseConstraint(EvidenceDraft evidence) =>
    toolchain.parseConstraint(evidence, budget());

({ToolchainMarker? marker, RecognitionLimitation? limitation})
observeToolchainMarker(ScannedSource source) =>
    toolchain.observeToolchainMarker(source, budget());

List<ConflictDraft> toolchainConflicts({
  required List<ToolchainMarker> markers,
  required List<ConstraintEvidence> flutterConstraints,
  required List<ConstraintEvidence> sdkConstraints,
}) => toolchain.toolchainConflicts(
  markers: markers,
  flutterConstraints: flutterConstraints,
  sdkConstraints: sdkConstraints,
  budget: budget(),
);
