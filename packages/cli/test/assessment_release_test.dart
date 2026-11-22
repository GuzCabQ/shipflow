@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/assessment/assessment_human.dart';
import 'package:cli/src/assessment/assessment_presenter.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:cli/src/context/state_layout.dart' show projectPath;
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_release_support.dart';
import 'support/recovery_cleanup_support.dart' show TracedStore;
import 'support/assessment_service_support.dart';

const _headline =
    'Levantamiento guardado, pero la operación terminó con un error';

/// Lo que devuelve o lanza un observe con [posix], sin dejar escapar nada.
typedef _Run = ({AssessmentResult? result, Object? error, List<String> events});

Future<_Run> _observe(AssessServiceBox box, ReleasePosix posix) async {
  box.posix = posix;
  try {
    final result = await box.run(AssessmentOperation.observe);
    return (result: result, error: null, events: posix.events);
  } on Object catch (error) {
    return (result: null, error: error, events: posix.events);
  } finally {
    posix.closeLeaked();
  }
}

/// Lo observable de un resultado, para comparar dos corridas.
Map<String, Object?> _visible(AssessmentResult r) => {
  'outcome': r.outcome.name,
  'exit': r.exitCode,
  'codes': diagnosticCodes(r),
  'effects': r.effects.toJson(),
};

/// El documento publicado, verificable en disco, y ningún journal.
void _published(AssessServiceBox box, int revision) {
  expect(decodeAssessment(box.document.readAsBytesSync()).revision, revision);
  expect(File(box.path(assessmentJournalPath)).existsSync(), isFalse);
}

/// failed/74 con io_failure y los efectos verdaderos de la publicación.
void _savedButFailed(_Run run, {required bool created}) {
  expect(run.error, isNull, reason: '${run.error}');
  final r = run.result!;
  expect((r.outcome, r.exitCode), (AssessmentOutcome.failed, 74));
  expect(diagnosticCodes(r), contains('io_failure'));
  expect(diagnosticCodes(r), isNot(contains('busy')));
  expect(diagnosticCodes(r), isNot(contains('assessment_recovery_pending')));
  expect(r.effects.published, isTrue);
  expect(r.effects.created.contains(assessmentPath), created);
  expect(r.effects.replaced.contains(assessmentPath), !created);
  expect(headlineOf(r), _headline);
}

/// Una liberación, después del último cambio en disco del trabajo.
void _releasedLast(List<String> events) {
  expect(events.where((e) => e == 'lease.unlock'), hasLength(1));
  final last = events.lastIndexWhere(
    (e) => e.startsWith('rename ') || e.startsWith('unlink '),
  );
  expect(last, lessThan(events.indexOf('lease.unlock')), reason: '$events');
}

void main() {
  late AssessServiceBox box;
  setUp(() async => box = await AssessServiceBox.initialized());
  tearDown(() => box.dispose());

  test(
    'a healthy first publication and replacement release once, last',
    () async {
      final first = await _observe(box, ReleasePosix([]));
      expect(first.result!.outcome, AssessmentOutcome.saved);
      expect(first.result!.effects.created, contains(assessmentPath));
      _releasedLast(first.events);
      box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
      final second = await _observe(box, ReleasePosix([]));
      expect(
        (second.result!.outcome, second.result!.exitCode),
        (AssessmentOutcome.saved, 0),
      );
      expect(second.result!.effects.replaced, [assessmentPath]);
      _releasedLast(second.events);
      _published(box, 2);
    },
  );

  test(
    'a failing unlock after publishing keeps the witness and fails',
    () async {
      final error = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
      final run = await _observe(box, ReleasePosix([], unlockFails: error));
      _savedButFailed(run, created: true);
      _published(box, 1);
      _releasedLast(run.events);
      expect(
        run.events,
        contains('lease.close'),
        reason: 'el lease cerró el descriptor',
      );
    },
  );

  for (final mode in LeaseCloseFailure.values) {
    test(
      'a failing lease close (${mode.name}) keeps the witness and fails',
      () async {
        final error = injected(ReleasePosix.eio, 'CLOSE_TRACE');
        final run = await _observe(
          box,
          ReleasePosix([], closeFails: (mode, error.$1, error.$2)),
        );
        _savedButFailed(run, created: true);
        _published(box, 1);
      },
    );
  }

  test(
    'any other error from release is io/74 too, never saved nor busy',
    () async {
      final error = injected(StateError('release'), 'STATE_TRACE');
      final run = await _observe(box, ReleasePosix([], unlockFails: error));
      _savedButFailed(run, created: true);
    },
  );

  test(
    'a replacement with a failing release keeps history and revisions',
    () async {
      await _observe(box, ReleasePosix([]));
      final error = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
      box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
      final second = await _observe(box, ReleasePosix([], unlockFails: error));
      _savedButFailed(second, created: false);
      expect(second.result!.comparison, isNotNull);
      _published(box, 2);
      box.box.file('lib/other.dart', "import 'main.dart';\n// r3\n");
      final third = await _observe(box, ReleasePosix([], unlockFails: error));
      _savedButFailed(third, created: false);
      expect(third.result!.retiredRevision, 1);
      _published(box, 3);
    },
  );

  test(
    'a commit failure of the work is the same with a failing release',
    () async {
      Future<_Run> run(bool releaseFails) async {
        final other = await AssessServiceBox.initialized();
        addTearDown(other.dispose);
        final error = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
        return _observe(
          other,
          ReleasePosix(
            [],
            fsyncAfterRename: true,
            unlockFails: releaseFails ? error : null,
          ),
        );
      }

      final healthy = await run(false);
      final failing = await run(true);
      expect(failing.error, isNull, reason: '${failing.error}');
      expect(healthy.result!.effects.published, isTrue);
      expect(_visible(failing.result!), _visible(healthy.result!));
      expect(failing.events.where((e) => e == 'lease.unlock'), hasLength(1));
    },
  );

  test(
    'an abort before the commit keeps its cause with a failing release',
    () async {
      await _observe(box, ReleasePosix([]));
      final before = box.document.readAsBytesSync();
      box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
      box.inputsWrap = (real) => (root, context, limits) {
        box.box.file('lib/other.dart', "import 'main.dart';\n// r3\n");
        return real(root, context, limits);
      };
      final error = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
      final run = await _observe(box, ReleasePosix([], unlockFails: error));
      expect(run.error, isNull, reason: '${run.error}');
      expect(diagnosticCodes(run.result!), contains('source_changed'));
      expect(run.result!.effects.published, isFalse);
      expect(box.document.readAsBytesSync(), before);
      expect(File(box.path(assessmentJournalPath)).existsSync(), isFalse);
      expect(run.events.where((e) => e == 'lease.unlock'), hasLength(1));
    },
  );

  test(
    'a store failure of the work keeps its diagnostic with a failing release',
    () async {
      final eio = injected(ReleasePosix.eio, 'READ_TRACE');
      final error = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
      final other = await AssessServiceBox.initialized();
      addTearDown(other.dispose);
      final healthy = await _observe(
        other,
        ReleasePosix([], readWhileLocked: eio),
      );
      final run = await _observe(
        box,
        ReleasePosix([], readWhileLocked: eio, unlockFails: error),
      );
      expect(run.error, isNull, reason: '${run.error}');
      expect(diagnosticCodes(run.result!), contains('io_failure'));
      expect(_visible(run.result!), _visible(healthy.result!));
      expect(run.result!.effects.published, isFalse);
      expect(box.document.existsSync(), isFalse);
      expect(headlineOf(run.result!), 'No se guardó un levantamiento');
      expect(run.events.where((e) => e == 'lease.unlock'), hasLength(1));
    },
  );

  test('the borrowed root is never closed and stays usable', () async {
    final events = <String>[];
    var usable = false;
    box.storeWrap = (real) => TracedStore('root', real, events);
    box.beforeClose = (real) async {
      usable = await real.readRelative(projectPath, maxBytes: 1 << 20) != null;
    };
    final error = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
    await _observe(box, ReleasePosix([], unlockFails: error));
    expect(events, isNot(contains('root.close')), reason: 'raíz prestada');
    expect(usable, isTrue, reason: 'la misma raíz, antes de su cierre');
  });

  test('a busy lock invents no release', () async {
    final holder = await SecureContextStore.open(box.box.root);
    final held = await holder.acquirePublication([holder.contextLock()]);
    try {
      final run = await _observe(box, ReleasePosix([]));
      expect(diagnosticCodes(run.result!), contains('busy'));
      expect(run.events, isNot(contains('lease.lock')));
      expect(run.events, isNot(contains('lease.unlock')));
    } finally {
      await held.release();
      await holder.close();
    }
  });

  test('unchanged and show take no lease', () async {
    await _observe(box, ReleasePosix([]));
    final unchanged = await _observe(box, ReleasePosix([]));
    expect(unchanged.result!.outcome, AssessmentOutcome.unchanged);
    expect(unchanged.events, isNot(contains('lease.lock')));
    final events = <String>[];
    box.posix = ReleasePosix(events);
    final shown = await box.run(AssessmentOperation.show);
    expect(shown.outcome, AssessmentOutcome.shown);
    expect(events, isNot(contains('lease.lock')));
  });

  test(
    'full and compact JSON and the human view tell the same thing',
    () async {
      final error = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
      final run = await _observe(box, ReleasePosix([], unlockFails: error));
      expect(run.error, isNull, reason: '${run.error}');
      final r = run.result!;
      for (final max in [maxAssessmentResponseBytes, 64]) {
        final response = presentAssessment(
          r,
          json: true,
          root: '/r',
          maxJsonBytes: max,
        );
        final json = jsonDecode(response.payload) as Map<String, Object?>;
        expect(response.exitCode, 74);
        expect(
          (json['operation'], json['outcome'], json['exitCode']),
          ('observe', 'failed', 74),
        );
        expect((json['effects']! as Map)['published'], isTrue);
        expect(json['diagnostics'].toString(), contains('io_failure'));
      }
      final human = presentAssessment(r, json: false, root: '/r').payload;
      expect(human.split('\n').first, _headline);
    },
  );
}
