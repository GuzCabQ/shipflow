import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assembler_support.dart';

void main() {
  test('zero candidates without blind spots is unsupported', () {
    final report = assemble([
      contribution(
        limitations: const [
          RecognitionLimitation(
            code: 'note',
            message: 'informativa',
            path: null,
            blocking: false,
          ),
        ],
      ),
    ]);
    expect(report.status, RecognitionStatus.unsupported);
    expect(report.proposal.eligible, isFalse);
    expect(report.proposal.actions, isEmpty);
  });

  test('zero candidates with a blocking limitation is ambiguous', () {
    final report = assemble([
      contribution(
        limitations: const [
          RecognitionLimitation(
            code: 'subtree_unreadable',
            message: 'no se pudo listar',
            path: 'x',
            blocking: true,
          ),
        ],
      ),
    ]);
    expect(report.status, RecognitionStatus.ambiguous);
  });

  test('one candidate and unit is recognized', () {
    final report = assemble([recognizable()]);
    expect(report.status, RecognitionStatus.recognized);
    expect(report.resolvedRoot, '/resuelta');
    expect(report.requestedRoot, '/solicitada');
    expect(report.proposal.eligible, isTrue);
    expect(report.proposal.pluginIds, ['plugin-stack']);
    expect(report.proposal.actions.map((a) => a.code), [
      'record_project_identity',
      'enable_stack_plugin',
    ]);
    expect(report.effects.toJson(), RecognitionEffects.none.toJson());
  });

  test('conflict is ambiguous', () {
    final report = assemble([
      recognizable(
        conflicts: [
          RecognitionConflict(
            code: 'versions_disagree',
            message: 'm',
            evidenceIds: const ['e0001'],
          ),
        ],
      ),
    ]);
    expect(report.status, RecognitionStatus.ambiguous);
    expect(report.proposal.eligible, isFalse);
    expect(report.proposal.pluginIds, isEmpty);
    expect(report.proposal.actions, isEmpty);
  });

  test('blocking limitation is ambiguous', () {
    final report = assemble([
      recognizable(
        limitations: const [
          RecognitionLimitation(
            code: 'symlink_not_followed',
            message: 'm',
            path: 'link',
            blocking: true,
          ),
        ],
      ),
    ]);
    expect(report.status, RecognitionStatus.ambiguous);
  });

  test('a non-blocking limitation keeps it recognized', () {
    final report = assemble([
      recognizable(
        limitations: const [
          RecognitionLimitation(
            code: 'note',
            message: 'm',
            path: null,
            blocking: false,
          ),
        ],
      ),
    ]);
    expect(report.status, RecognitionStatus.recognized);
  });

  test('candidate without unit is ambiguous', () {
    final report = assemble([recognizable(units: const [])]);
    expect(report.status, RecognitionStatus.ambiguous);
  });

  test('two candidates are ambiguous', () {
    final report = assemble([
      recognizable(),
      contribution(
        candidates: [
          candidate('other', ['e0002']),
        ],
        evidence: [evidence('e0002')],
      ),
    ]);
    expect(report.status, RecognitionStatus.ambiguous);
  });
}
