@Timeout(Duration(minutes: 2))
library;

import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';
import 'support/recovery_cleanup_support.dart';
import 'support/store_spy_support.dart';

/// Qué falla al limpiar: nada, soltar el lease, cerrar la administración o
/// las dos cosas.
enum _Cleanup { sano, lease, admin, ambos }

/// Lo que se observa de una recuperación con fallos inyectados.
typedef _Run = ({Recovered r, List<String> events, TracedStore admin});

final _leaseError = StateError('lease');
final _adminError = StateError('admin');

/// Recupera un init interrumpido con exclude, con [work] inyectado al leer
/// después de adquirir y [cleanup] al soltar o cerrar.
Future<_Run> _recover(
  ServiceSandbox box,
  _Cleanup cleanup, {
  InjectedFailure? work,
  InjectedFailure? acquire,
  InjectedFailure? closeWith,
  void Function()? before,
}) async {
  await interruptedInit(box, git: true);
  before?.call();
  final events = <String>[];
  final lease = {_Cleanup.lease, _Cleanup.ambos}.contains(cleanup);
  final admin = {_Cleanup.admin, _Cleanup.ambos}.contains(cleanup);
  final admins = TracedAdmins(
    events,
    failClose:
        closeWith ?? (admin ? failure(_adminError, 'ADMIN_TRACE') : null),
  );
  addTearDown(admins.dispose);
  final r = await recoverTraced(
    box,
    events,
    admins,
    posix: RecordingPosix(
      events,
      failUnlockAt: lease ? (2, failure(_leaseError, 'LEASE_TRACE')) : null,
    ),
    failAcquire: acquire,
    failReadAfterAcquire: work,
  );
  return (r: r, events: events, admin: admins.opened.single);
}

/// El error que llegó es exactamente [expected], con su traza.
void _same(Recovered r, Object expected, String trace) {
  expect(identical(r.error, expected), isTrue, reason: '${r.error}');
  expect('${r.trace}', contains(trace));
}

/// Los dos descriptores se intentaron soltar y la administración recibió un
/// intento de cierre, después.
void _bothAttempted(_Run run) {
  expect(run.events.where((e) => e == 'lease.unlock'), hasLength(2));
  expect(run.admin.closes, 1, reason: '${run.events}');
  expect(
    run.events.lastIndexOf('lease.unlock'),
    lessThan(run.events.indexOf('admin.close')),
  );
}

Map<String, Object?> _visible(ContextOperationResult r) => {
  'exit': r.exitCode,
  'outcome': r.outcome.name,
  'codes': [for (final d in r.diagnostics) d.code],
  'effects': r.effects.toJson(),
};

void main() {
  late ServiceSandbox box;
  setUp(() {
    box = ServiceSandbox.create()
      ..project()
      ..gitInit();
  });
  tearDown(() => box.dispose());

  test(
    'only the release fails: its error, and the close still happens',
    () async {
      final run = await _recover(box, _Cleanup.lease);
      _same(run.r, _leaseError, 'LEASE_TRACE');
      final after = (
        closes: run.admin.closes,
        usable: await run.admin.stillReads('info/exclude'),
      );
      expect(after, (closes: 1, usable: false), reason: 'intento y efecto');
      expect(
        run.events.indexOf('lease.unlock.fail'),
        run.events.lastIndexOf('lease.unlock') + 1,
        reason: 'falla el segundo unlock, ya hecho',
      );
      _bothAttempted(run);
      expect(run.r.rootUsable, isTrue);
    },
  );

  test('only the close fails: its error, once', () async {
    final run = await _recover(box, _Cleanup.admin);
    _same(run.r, _adminError, 'ADMIN_TRACE');
    _bothAttempted(run);
  });

  test('both fail: the release error first, the close attempted', () async {
    final run = await _recover(box, _Cleanup.ambos);
    _same(run.r, _leaseError, 'LEASE_TRACE');
    _bothAttempted(run);
  });

  for (final cleanup in _Cleanup.values) {
    test(
      'an unexpected work error survives a ${cleanup.name} cleanup',
      () async {
        final work = failure(StateError('work'), 'WORK_TRACE');
        final run = await _recover(box, cleanup, work: work);
        expect(
          run.events.indexOf('root.acquire'),
          lessThan(run.events.indexOf('root.read.fail')),
          reason: 'la inyección ocurre con el lease tomado',
        );
        _same(run.r, work.$1, 'WORK_TRACE');
        _bothAttempted(run);
      },
    );
  }

  group('a store failure of the work keeps its failed result', () {
    late Map<String, Object?> healthy;
    setUpAll(() async {
      final other = ServiceSandbox.create()
        ..project()
        ..gitInit();
      addTearDown(other.dispose);
      final work = failure(const ContextStoreFailure('io'), 'WORK_TRACE');
      healthy = _visible(
        (await _recover(other, _Cleanup.sano, work: work)).r.result!,
      );
    });
    for (final cleanup in _Cleanup.values) {
      test('with a ${cleanup.name} cleanup', () async {
        final work = failure(const ContextStoreFailure('io'), 'WORK_TRACE');
        final run = await _recover(box, cleanup, work: work);
        expect(run.r.error, isNull, reason: '${run.r.error}');
        expect(_visible(run.r.result!), healthy);
        expect(healthy['codes'], contains('io_failure'));
        _bothAttempted(run);
      });
    }
  });

  test('a store failure raised by cleanup is not translated', () async {
    final io = failure(const ContextStoreFailure('io'), 'CLOSE_TRACE');
    final run = await _recover(box, _Cleanup.sano, closeWith: io);
    _same(run.r, io.$1, 'CLOSE_TRACE');
  });

  test('a business return with diagnostics does not hide cleanup', () async {
    final run = await _recover(
      box,
      _Cleanup.admin,
      before: () => box.file('shipflow/project.json', '{"ajeno": true}\n'),
    );
    _same(run.r, _adminError, 'ADMIN_TRACE');
  });

  test('a failed lease after opening keeps its error over the close', () async {
    final acquire = failure(StateError('acquire'), 'ACQUIRE_TRACE');
    final run = await _recover(box, _Cleanup.admin, acquire: acquire);
    _same(run.r, acquire.$1, 'ACQUIRE_TRACE');
    expect(
      run.events.indexOf('admin.open'),
      lessThan(run.events.indexOf('root.acquire.fail')),
      reason: 'la administración ya era propia',
    );
    expect(run.events, isNot(contains('lease.unlock')));
    expect(run.admin.closes, 1);
  });

  test(
    'a busy lease after opening keeps its diagnostic over the close',
    () async {
      final busy = failure(const ContextStoreFailure('busy'), 'BUSY_TRACE');
      final run = await _recover(box, _Cleanup.admin, acquire: busy);
      expect(run.r.error, isNull, reason: '${run.r.error}');
      expect([for (final d in run.r.result!.diagnostics) d.code], ['busy']);
      expect(run.admin.closes, 1);
    },
  );
}
