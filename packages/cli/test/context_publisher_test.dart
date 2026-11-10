@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cli/src/command/cli_command.dart';
import 'package:cli/src/context/context_init_publication.dart';
import 'package:cli/src/context/context_observation.dart';
import 'package:cli/src/context/context_publication_outcome.dart';
import 'package:cli/src/context/context_result.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:cli/src/recognition_runner.dart';
import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

import 'support/context_service_support.dart';
import 'support/store_spy_support.dart';

/// Un publicador sin sesión ni servicio: sólo con sus dependencias reales, un
/// almacén espiado y una observación producida por [observeContext].
void main() {
  late ServiceSandbox box;
  late AdminSpies spies;
  setUp(() {
    box = ServiceSandbox.create()
      ..project()
      ..gitInit();
    spies = AdminSpies();
  });
  tearDown(() async {
    await spies.dispose();
    box.dispose();
  });

  Future<RecognitionReport> recognize(
    ReportBudgetProfile profile,
    List<AuthorizedOmission> omissions,
  ) => recognizeRoot(
    box.root,
    (r, {required reportLimits, required authorizedOmissions}) =>
        recognizeDartProject(
          r,
          reportLimits: reportLimits,
          authorizedOmissions: authorizedOmissions,
        ),
    budgetProfile: profile,
    authorizedOmissions: omissions,
  );

  Future<ContextStore> store() => SecureContextStore.open(box.root);

  Future<ContextStore> Function(Directory) opener() => spies.opener();

  ContextPublisher publisher(
    ContextStore s,
    Future<ContextStore> Function(Directory) open,
  ) => ContextPublisher(
    root: box.root,
    store: s,
    git: GitContextAdapter(parentEnvironment: box.realGit),
    recognize: recognize,
    version: '0.0.0-prueba',
    now: () => DateTime.utc(2026, 11, 10, 12),
    newId: box.newId,
    openAdministration: open,
  );

  Future<ObservedContext> observe(ContextStore s) => observeContext(
    root: box.root,
    store: s,
    git: GitContextAdapter(parentEnvironment: box.realGit),
    budget: GitBudget(),
    recognize: recognize,
    profile: ReportBudgetProfile.standard,
  );

  PublishRequest request({
    required bool keep,
    SharingChoice choice = SharingChoice.local,
  }) => (
    projectId: '00000000-0000-4000-8000-000000000001',
    revision: 1,
    current: null,
    choice: choice,
    operation: TransactionOperation.sharing,
    keepSharing: keep,
  );

  test(
    'sin exclude que tocar: nada que publicar, con la modalidad comprobada',
    () async {
      final s = await store();
      addTearDown(s.close);
      box.project();
      final o = await observe(s);
      final out = await publisher(s, opener()).publish(
        request(keep: true),
        o: o,
        profile: ReportBudgetProfile.standard,
        budget: GitBudget(),
        effects: EffectsLog(),
      );
      expect(out, isA<NothingToPublish>());
      expect(
        spies.opened,
        isEmpty,
        reason: 'con keepSharing no se abre administración',
      );
    },
  );

  test(
    'exclude enlazado: rechazo con su diagnóstico, sin journal y con un cierre',
    () async {
      final foreign = File('${box.base.path}/ajeno')..writeAsStringSync('x\n');
      final exclude = File(box.path('.git/info/exclude'));
      if (exclude.existsSync()) exclude.deleteSync();
      Link(exclude.path).createSync(foreign.path);
      final s = await store();
      addTearDown(s.close);
      final o = await observe(s);
      final out = await publisher(s, opener()).publish(
        request(keep: false),
        o: o,
        profile: ReportBudgetProfile.standard,
        budget: GitBudget(),
        effects: EffectsLog(),
      );
      expect(out, isA<PublicationRefused>());
      expect((out as PublicationRefused).journalLeft, isFalse);
      expect(out.diagnostics.map((d) => d.code), contains('sharing_conflict'));
      expect(spies.opened.single.closes, 1);
    },
  );

  test(
    'publicación local: completada con la modalidad aplicada y un cierre',
    () async {
      final s = await store();
      addTearDown(s.close);
      final o = await observe(s);
      final out = await publisher(s, opener()).publish(
        request(keep: false),
        o: o,
        profile: ReportBudgetProfile.standard,
        budget: GitBudget(),
        effects: EffectsLog(),
      );
      expect(out, isA<PublicationCompleted>());
      expect((out as PublicationCompleted).choice, SharingChoice.local);
      expect(spies.opened.single.closes, 1);
      expect(spies.opened.single.calls, contains('directoryLock'));
    },
  );

  test(
    'la observación no cambia al publicar y el almacén prestado sigue abierto',
    () async {
      final s = await store();
      addTearDown(s.close);
      final o = await observe(s);
      final report = o.report;
      final settings = o.settings;
      final project = o.project;
      await publisher(s, opener()).publish(
        request(keep: false),
        o: o,
        profile: ReportBudgetProfile.standard,
        budget: GitBudget(),
        effects: EffectsLog(),
      );
      expect(identical(o.report, report), isTrue);
      expect(identical(o.settings, settings), isTrue);
      expect(identical(o.project, project), isTrue);
      expect(await s.readRelative('pubspec.yaml', maxBytes: 1024), isNotNull);
    },
  );
}
