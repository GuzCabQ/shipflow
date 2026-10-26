import 'package:core/core.dart';
import 'package:test/test.dart';

import 'context_fixtures.dart';

void main() {
  group('projectRecognition keeps only the portable subset', () {
    test('an eligible report becomes portable without execution data', () {
      final portable = projectRecognition(eligibleReport());
      final json = portable.toJson();
      expect(json.containsKey('resolvedRoot'), isFalse);
      expect(json.containsKey('requestedRoot'), isFalse);
      expect(json.containsKey('repository'), isFalse);
      expect(json.containsKey('proposal'), isFalse);
      expect(json.containsKey('effects'), isFalse);
      expect(json['status'], 'recognized');
      expect(portable.units.single.path, '.');
    });

    test('a report that is not eligible is rejected', () {
      expect(
        () => projectRecognition(eligibleReport(eligible: false)),
        throwsA(isA<ContextFormatException>()),
      );
    });

    test('a report without the tool state omission is rejected', () {
      expect(
        () => projectRecognition(eligibleReport(toolState: false)),
        throwsA(_semantic('tool_state_omission')),
      );
    });
  });

  group('a saved recognition must be complete and unblocked', () {
    for (final (name, change, code) in [
      ('a repeated ID', (PortableParts p) => p.duplicateEvidence(), 'ids'),
      ('a missing reference', (PortableParts p) => p.danglingUnit(), 'refs'),
      ('no candidate', (PortableParts p) => p.candidates.clear(), 'empty'),
      ('no unit', (PortableParts p) => p.noUnits(), 'empty'),
      ('a conflict', (PortableParts p) => p.addConflict(), 'blocked'),
      ('a blocking limit', (PortableParts p) => p.addBlocking(), 'blocked'),
      ('two tool states', (PortableParts p) => p.twoToolStates(), 'ids'),
      ('a lone surrogate', (PortableParts p) => p.loneSurrogate(), 'text'),
    ]) {
      test('$name is rejected', () {
        final parts = PortableParts();
        change(parts);
        expect(parts.build, throwsA(_semantic(_codes[code]!)));
      });
    }

    test('a corroborated relation must point at its unit path', () {
      final parts = PortableParts()..misplacedRelation();
      expect(parts.build, throwsA(_semantic('relation_target')));
    });

    test('a non blocking limitation is kept', () {
      final parts = PortableParts()..addWarning();
      expect(parts.build().limitations.single.blocking, isFalse);
    });
  });

  group('the project document', () {
    test('accepts the fixture values and is immutable', () {
      final context = projectContext();
      expect(context.root, '.');
      expect(context.schemaVersion, 1);
      expect(() => context.producer.pluginIds.add('x'), throwsUnsupportedError);
      expect(
        () => context.recognition.units.add(context.recognition.units.first),
        throwsUnsupportedError,
      );
    });

    for (final (name, build, code) in [
      (
        'an impossible date',
        () => projectContext(at: '2026-02-30T00:00:00Z'),
        'observed_at',
      ),
      (
        'a non v4 id',
        () => projectContext(
          id:
              '12345678-1234-1234-8234-1234'
              '56789abc',
        ),
        'project_id',
      ),
      ('revision zero', () => projectContext(revision: 0), 'revision'),
      (
        'plugins that do not match the candidates',
        () => projectContext(pluginIds: ['other']),
        'producer_plugins',
      ),
    ]) {
      test('rejects $name', () {
        expect(build, throwsA(_semantic(code)));
      });
    }

    test('round trips through its own JSON', () {
      final context = projectContext();
      final again = ProjectContext.fromJson(context.toJson());
      expect(again.toJson(), context.toJson());
    });
  });

  group('local settings', () {
    test('pending never claims an application', () {
      expect(
        () => LocalSettings(
          projectId: fixtureProjectId,
          choice: SharingChoice.pending,
          binding: null,
          applied: true,
          managedExclude: null,
        ),
        throwsA(_semantic('settings_pending')),
      );
    });

    test('an applied local choice needs its binding and block', () {
      expect(
        () => LocalSettings(
          projectId: fixtureProjectId,
          choice: SharingChoice.local,
          binding: null,
          applied: true,
          managedExclude: null,
        ),
        throwsA(_semantic('settings_local')),
      );
    });

    test('a binding is absolute and its prefix relative', () {
      expect(
        () => GitBinding(
          repositoryRoot: 'repo',
          gitDir: '/repo/.git',
          commonDir: '/repo/.git',
          prefix: '',
        ),
        throwsA(_semantic('binding')),
      );
      expect(
        () => GitBinding(
          repositoryRoot: '/repo',
          gitDir: '/repo/.git',
          commonDir: '/repo/.git',
          prefix: '/abs/',
        ),
        throwsA(_semantic('binding')),
      );
    });
  });

  group('a transaction names only its own staging', () {
    test('the fixture shape is accepted', () {
      expect(transaction().staging.project, stagedProject);
    });

    test('a staging file of another operation is rejected', () {
      expect(
        () => transaction(
          project: 'local/staging/$fixtureProjectId/project.json',
        ),
        throwsA(_semantic('staging')),
      );
    });

    test('a repeated resource is rejected', () {
      expect(
        () => transaction(repeatTarget: true),
        throwsA(_semantic('targets')),
      );
    });
  });

  group('an operation result is consistent', () {
    test('doctor never reports writes', () {
      expect(
        () => doctorResult(created: ['shipflow/project.json']),
        throwsA(_semantic('doctor_effects')),
      );
    });

    test('doctor only runs the doctor operation', () {
      expect(
        () => doctorResult(operation: ContextOperation.refresh),
        throwsA(_semantic('command_operation')),
      );
    });

    test('a check appears at most once', () {
      expect(
        () => doctorResult(repeatCheck: true),
        throwsA(_semantic('checks')),
      );
    });

    test('the exit code matches the outcome', () {
      expect(() => doctorResult(exitCode: 65), throwsA(_semantic('exit_code')));
    });

    test('the fixture result is accepted', () {
      expect(doctorResult().outcome, ContextOutcome.available);
    });
  });
}

const _codes = {
  'ids': 'duplicate_id',
  'refs': 'missing_reference',
  'empty': 'empty_recognition',
  'blocked': 'not_eligible',
  'text': 'invalid_text',
};

Matcher _semantic(String code) => isA<ContextFormatException>()
    .having((e) => e.layer, 'layer', ContextFormatLayer.semantic)
    .having((e) => e.code, 'code', code);
