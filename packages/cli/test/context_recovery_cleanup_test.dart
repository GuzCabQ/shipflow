@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_service_support.dart';
import 'support/context_service_support.dart';
import 'support/recovery_cleanup_support.dart';
import 'support/store_spy_support.dart';

const _io = {'read', 'publish', 'remove', 'mkdir', 'rmdir'};

/// Posiciones del último uso de un almacén, del primer unlock del lease y del
/// cierre de la administración; -1 si no ocurrió.
({int lastUse, int release, int close}) _order(List<String> events) => (
  lastUse: events.lastIndexWhere((e) => _io.contains(e.split('.').last)),
  release: events.indexOf('lease.unlock'),
  close: events.indexOf('admin.close'),
);

List<String> _codes(ContextOperationResult r) => [
  for (final d in r.diagnostics) d.code,
];

void main() {
  late ServiceSandbox box;
  late List<String> events;
  late TracedAdmins admins;
  setUp(() {
    box = ServiceSandbox.create()
      ..project()
      ..gitInit();
    events = [];
    admins = TracedAdmins(events);
  });
  tearDown(() async {
    await admins.dispose();
    box.dispose();
  });

  Directory common() => Directory(box.path('.git'));

  test('with an exclude it releases after the last use, then closes', () async {
    await interruptedInit(box, git: true);
    final r = await recoverTraced(box, events, admins);
    expect(r.error, isNull);
    expect(r.result!.outcome, ContextOutcome.recovered);
    final o = _order(events);
    expect(o.lastUse, lessThan(o.release), reason: '$events');
    expect(o.release, lessThan(o.close), reason: '$events');
    expect(events.where((e) => e == 'lease.close'), hasLength(2));
    expect(admins.opened.single.closes, 1);
    expect(await admins.opened.single.stillReads('info/exclude'), isFalse);
    expect(events, isNot(contains('root.close')), reason: 'raíz prestada');
    expect(r.rootUsable, isTrue, reason: 'la misma raíz, antes de su cierre');
    expect(await publicationFree(box.root, common()), isTrue);
  });

  test('without an exclude it opens no administration', () async {
    await interruptedInit(box, git: false);
    final r = await recoverTraced(box, events, admins, git: false);
    expect(r.error, isNull);
    expect(r.result!.outcome, ContextOutcome.recovered);
    expect(admins.opened, isEmpty);
    expect(events.where((e) => e == 'lease.close'), hasLength(1));
    expect(_order(events).lastUse, lessThan(_order(events).release));
    expect(events, isNot(contains('root.close')));
    expect(r.rootUsable, isTrue);
    final store = await SecureContextStore.open(box.root);
    addTearDown(store.close);
    final again = await store.acquirePublication([store.contextLock()]);
    await again.release();
  });

  test('a conflict keeps everything and still releases, then closes', () async {
    await interruptedInit(box, git: true);
    box.file('shipflow/project.json', '{"ajeno": true}\n');
    final kept = box.snapshot();
    final r = await recoverTraced(box, events, admins);
    expect(r.result!.exitCode, 75, reason: '${r.error}');
    expect(_codes(r.result!), contains('recovery_conflict'));
    expect(box.snapshot(), kept);
    final o = _order(events);
    expect(o.lastUse, lessThan(o.release));
    expect(o.release, lessThan(o.close));
    expect(admins.opened.single.closes, 1);
    expect(await publicationFree(box.root, common()), isTrue);
  });

  test('changed sources abort, undo, and then release and close', () async {
    await interruptedInit(box, git: true);
    box.file('pubspec.yaml', 'name: app\ndescription: otra\n');
    final r = await recoverTraced(box, events, admins);
    expect(r.result!.exitCode, 65, reason: '${r.error}');
    expect(_codes(r.result!), contains('recovery_aborted'));
    expect(
      File(box.path('shipflow/local/transaction.json')).existsSync(),
      isFalse,
    );
    final o = _order(events);
    expect(o.lastUse, lessThan(o.release));
    expect(o.release, lessThan(o.close));
    expect(admins.opened.single.closes, 1);
  });

  test(
    'a busy lease after opening the administration closes it, no release',
    () async {
      await interruptedInit(box, git: true);
      final holder = await SecureContextStore.open(box.root);
      final held = await holder.acquirePublication([holder.contextLock()]);
      try {
        final r = await recoverTraced(box, events, admins);
        expect(_codes(r.result!), ['busy']);
        expect(events, isNot(contains('lease.unlock')));
        expect(admins.opened.single.closes, 1);
        expect(await admins.opened.single.stillReads('info/exclude'), isFalse);
      } finally {
        await held.release();
        await holder.close();
      }
    },
  );

  test('a failing open leaves nothing to release or close', () async {
    await interruptedInit(box, git: true);
    final open = failure(StateError('open'), 'OPEN_TRACE');
    admins = TracedAdmins(events, failOpen: open);
    final r = await recoverTraced(box, events, admins);
    expect(identical(r.error, open.$1), isTrue, reason: '${r.error}');
    expect('${r.trace}', contains('OPEN_TRACE'));
    expect(events, isNot(contains('root.acquire')));
    expect(events, isNot(contains('admin.close')));
  });

  test('no journal and a foreign journal take no resources', () async {
    final r = await recoverTraced(box, events, admins);
    expect(_codes(r.result!), ['not_initialized']);
    final basis = await BasisBox.initialized();
    addTearDown(basis.dispose);
    await interruptBasis(basis, [create('rule', ruleOf())]);
    final foreign = await recoverTraced(basis.box, events, admins, git: false);
    expect(foreign.result!.exitCode, isNot(0));
    expect(admins.opened, isEmpty);
    expect(events.where((e) => e.contains('acquire')), isEmpty);
  });
}
