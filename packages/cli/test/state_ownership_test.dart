@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:cli/src/context/context_codec.dart';
import 'package:cli/src/context/state_ownership.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'support/context_store_support.dart';
import 'v2_fixtures.dart';

const _gitignore =
    '# Local operational state; project.json remains shareable.\n/local/\n';

void main() {
  late StoreSandbox box;
  setUp(() async => box = await StoreSandbox.create());
  tearDown(() => box.dispose());

  Future<StateOwnershipKind> kind() async =>
      (await inspectStateOwnership(box.root)).kind;

  group('the state is ours only when its form says so', () {
    test('absent and empty are free to initialize', () async {
      expect(await kind(), StateOwnershipKind.absent);
      box.directory('shipflow');
      expect(await kind(), StateOwnershipKind.empty);
    });

    test('scaffolding alone is a bootstrap that init may resume', () async {
      box.directory('shipflow/local/staging');
      box.file('shipflow/.gitignore', _gitignore);
      box.file('shipflow/local/locks/context.lock', '');
      expect(await kind(), StateOwnershipKind.bootstrap);
    });

    test('a valid document makes it owned', () async {
      box.file('shipflow/.gitignore', _gitignore);
      File(
        box.path('shipflow/project.json'),
      ).writeAsBytesSync(await v2Bytes('fixtures/valid/project.json'));
      box.file('shipflow/local/settings.json', '');
      File(
        box.path('shipflow/local/settings.json'),
      ).writeAsBytesSync(await v2Bytes('fixtures/valid/settings-pending.json'));
      expect(await kind(), StateOwnershipKind.owned);
    });

    for (final (name, setup) in [
      ('a corrupt document', () => box.file('shipflow/project.json', '{')),
      (
        'an unknown temporary without a journal',
        () => box.file('shipflow/.project.json.0123456789abcdef.tmp', 'x'),
      ),
      (
        'a future schema',
        () => box.file('shipflow/local/settings.json', '{"schemaVersion":2}'),
      ),
    ]) {
      test('$name is invalid, kept and named', () async {
        setup();
        final ownership = await inspectStateOwnership(box.root);
        expect(ownership.kind, StateOwnershipKind.invalid);
        expect(ownership.findings, isNotEmpty);
        expect(ownership.authorizesOmission, isFalse);
      });
    }

    for (final (name, setup) in [
      ('code of another tool', () => box.file('shipflow/main.dart', 'x')),
      ('a different ignore file', () => box.file('shipflow/.gitignore', '*\n')),
      ('a file named shipflow', () => box.file('shipflow', 'x')),
      (
        'a link named shipflow',
        () => Link(box.path('shipflow')).createSync(box.outside.path),
      ),
      (
        'a link inside',
        () {
          box.directory('shipflow');
          Link(box.path('shipflow/local')).createSync(box.outside.path);
        },
      ),
      ('an unexpected directory', () => box.directory('shipflow/src')),
    ]) {
      test('$name is foreign', () async {
        setup();
        expect(await kind(), StateOwnershipKind.foreign);
      });
    }

    test('a FIFO inside is foreign and never blocks', () async {
      box.directory('shipflow');
      await Process.run('mkfifo', [box.path('shipflow/project.json')]);
      expect(await kind(), StateOwnershipKind.foreign);
    });

    test('inspecting never changes the tree', () async {
      box.file('shipflow/project.json', '{');
      final before = box.snapshot();
      await inspectStateOwnership(box.root);
      expect(box.snapshot(), before);
    });
  });

  group('init --dry-run accounts for the state without masking code', () {
    Future<Map<String, Object?>> dryRun() async {
      final response = await runCli(
        ['init', '--dry-run', '--json'],
        version: '1.0.0',
        workingDirectory: box.root,
        recognizeProject:
            (root, {required reportLimits, required authorizedOmissions}) =>
                recognizeDartProject(
                  root,
                  reportLimits: reportLimits,
                  authorizedOmissions: authorizedOmissions,
                ),
      );
      const ContextCodec().checkDryRun(utf8.encode(response.payload));
      return jsonDecode(response.payload) as Map<String, Object?>;
    }

    List<Object?> toolStates(Map<String, Object?> json) => [
      for (final o in json['omissions']! as List<Object?>)
        if ((o! as Map<String, Object?>)['rule'] == 'tool_state') o,
    ];

    setUp(() => box.file('pubspec.yaml', 'name: app\n'));

    test('schema 3 with one policy omission, absent or owned', () async {
      final absent = await dryRun();
      expect(absent['schemaVersion'], 3);
      expect(absent['command'], 'init');
      expect(absent['operation'], 'dry_run');
      expect(toolStates(absent), hasLength(1));
      File(box.path('shipflow/project.json'))
        ..parent.createSync()
        ..writeAsBytesSync(await v2Bytes('fixtures/valid/project.json'));
      final before = box.snapshot();
      final owned = await dryRun();
      expect(owned['omissions'], absent['omissions']);
      expect(owned['evidence'], absent['evidence']);
      expect(box.snapshot(), before);
    });

    test('foreignStateDirectoryIsNotOmitted', () async {
      box.file('shipflow/pubspec.yaml', 'name: ajeno\n');
      final json = await dryRun();
      expect(toolStates(json), isEmpty);
      expect([
        for (final u in json['units']! as List<Object?>) (u! as Map)['path'],
      ], contains('shipflow'));
    });
  });
}
