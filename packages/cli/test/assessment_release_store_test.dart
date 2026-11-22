@Timeout(Duration(minutes: 2))
library;

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/assessment/assessment_store.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_release_support.dart';
import 'support/assessment_store_support.dart';

/// Lo que sale de `AssessmentStore.publish`: el testigo o el error con su
/// traza, y lo que anotó [posix].
typedef _Published = ({
  AssessmentPublication? publication,
  Object? error,
  StackTrace? trace,
  List<String> events,
});

Future<_Published> _publish(
  AssessmentBox box,
  AssessmentDocument document,
  ReleasePosix posix, {
  Future<void> Function()? revalidate,
}) async {
  final store = await SecureContextStore.open(box.box.root, api: posix);
  try {
    final publication = await AssessmentStore(store).publish(
      document,
      operationId: operationA,
      expectedSha256: null,
      baseContextDigest: document.current.contextDigest,
      preconditions: () async {},
      revalidate: revalidate ?? () async {},
    );
    return (
      publication: publication,
      error: null,
      trace: null,
      events: posix.events,
    );
  } on Object catch (error, trace) {
    return (
      publication: null,
      error: error,
      trace: trace,
      events: posix.events,
    );
  } finally {
    posix.closeLeaked();
    await store.close();
  }
}

/// Los efectos de un testigo, para comparar dos salidas por contenido.
List<Object> _effects(AssessmentPublication p) => [
  p.created,
  p.replaced,
  p.published,
];

/// Una publicación cuyo trabajo falla después del rename (EIO en el fsync
/// del directorio), con o sin un release que también falla.
Future<_Published> _commitFailure(
  AssessmentDocument first, {
  required bool releaseFails,
}) async {
  final other = await AssessmentBox.initialized();
  addTearDown(other.dispose);
  final unlock = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
  return _publish(
    other,
    first,
    ReleasePosix(
      [],
      fsyncAfterRename: true,
      unlockFails: releaseFails ? unlock : null,
    ),
  );
}

void main() {
  late AssessmentBox box;
  late AssessmentDocument first;
  setUp(() async {
    box = await AssessmentBox.initialized();
    (first, _) = await twoRevisions();
  });
  tearDown(() => box.dispose());

  test('a failing release after publishing wraps the exact witness', () async {
    final other = await AssessmentBox.initialized();
    addTearDown(other.dispose);
    final healthy = await _publish(other, first, ReleasePosix([]));
    final unlock = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
    final run = await _publish(
      box,
      first,
      ReleasePosix([], unlockFails: unlock),
    );
    final failure = run.error;
    expect(failure, isA<AssessmentCommitFailure>(), reason: '$failure');
    failure as AssessmentCommitFailure;
    expect(failure.code, 'io');
    expect(_effects(failure.publication), _effects(healthy.publication!));
    expect(
      '${run.trace}',
      contains('UNLOCK_TRACE'),
      reason: 'traza del release',
    );
  });

  test('a commit failure of the work leaves publish as it is', () async {
    final healthy = await _commitFailure(first, releaseFails: false);
    final failing = await _commitFailure(first, releaseFails: true);
    expect(
      failing.error,
      isA<AssessmentCommitFailure>(),
      reason: '${failing.error}',
    );
    final (h, f) = (
      healthy.error! as AssessmentCommitFailure,
      failing.error! as AssessmentCommitFailure,
    );
    expect(
      [f.code, ..._effects(f.publication)],
      [h.code, ..._effects(h.publication)],
    );
    expect('${failing.trace}', contains('commitReported'));
    expect('${failing.trace}', isNot(contains('UNLOCK_TRACE')));
    expect(failing.events.where((e) => e == 'lease.unlock'), hasLength(1));
  });

  // Sólo propagación: una instancia conocida de AssessmentCommitFailure sale
  // del trabajo por revalidate, para exigir identidad. La publicación real y
  // su contenido los cubre «a commit failure of the work leaves publish…».
  for (final releaseFails in [false, true]) {
    test('a known commit failure of the work comes out identical, '
        'release fails: $releaseFails', () async {
      final primary = AssessmentCommitFailure(
        'io',
        AssessmentPublication(
          created: [assessmentPath],
          replaced: [],
          published: true,
        ),
      );
      final unlock = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
      final run = await _publish(
        box,
        first,
        ReleasePosix([], unlockFails: releaseFails ? unlock : null),
        revalidate: () =>
            Future.error(primary, StackTrace.fromString('PRIMARY_TRACE')),
      );
      expect(identical(run.error, primary), isTrue, reason: '${run.error}');
      expect('${run.trace}', contains('PRIMARY_TRACE'));
      expect(run.events.where((e) => e == 'lease.unlock'), hasLength(1));
    });
  }

  test(
    'any other work error leaves publish identical, with its trace',
    () async {
      final work = injected(StateError('work'), 'WORK_TRACE');
      final unlock = injected(ReleasePosix.eio, 'UNLOCK_TRACE');
      final before = box.state();
      final run = await _publish(
        box,
        first,
        ReleasePosix([], unlockFails: unlock),
        revalidate: () => Future.error(work.$1, work.$2),
      );
      expect(identical(run.error, work.$1), isTrue, reason: '${run.error}');
      expect('${run.trace}', contains('WORK_TRACE'));
      expect(run.events.where((e) => e == 'lease.unlock'), hasLength(1));
      expect(box.document.existsSync(), isFalse, reason: 'antes del rename');
      expect(before.keys, isNot(contains(assessmentPath)));
    },
  );
}
