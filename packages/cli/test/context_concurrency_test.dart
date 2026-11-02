@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'init_process_support.dart';
import 'support/context_service_support.dart';

void main() {
  late ServiceSandbox box;
  setUp(() {
    box = ServiceSandbox.create();
    box.project();
  });
  tearDown(() => box.dispose());

  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];

  test(
    'S04: a live owner of the lease makes init busy, never stolen',
    () async {
      await box.run(ContextOperation.init);
      box.file('packages/b/pubspec.yaml', 'name: b\n');
      final script =
          '${(await cliRoot()).path}/test/support/context_process.dart';
      final owner = await Process.start(Platform.resolvedExecutable, [
        '--packages=${(await Isolate.packageConfig)!.toFilePath()}',
        script,
        box.root.path,
        'context',
      ]);
      addTearDown(() => owner.kill(ProcessSignal.sigkill));
      expect(
        await owner.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'held',
      );
      final before = box.snapshot();
      final refresh = await box.run(ContextOperation.refresh);
      expect(refresh.exitCode, 75, reason: '${codes(refresh)}');
      expect(codes(refresh), contains('busy'));
      expect(box.snapshot(), before);
      owner.kill(ProcessSignal.sigkill);
      await owner.exitCode;
      expect((await box.run(ContextOperation.refresh)).exitCode, 0);
    },
  );

  test(
    'a change between preparation and lease is a concurrent change',
    () async {
      await box.run(ContextOperation.init);
      box.file('packages/b/pubspec.yaml', 'name: b\n');
      final result = await box.run(
        ContextOperation.refresh,
        wrap: (real) => EditOnLease(real, () {
          box.file('shipflow/local/settings.json', '{"otro": true}\n');
        }),
      );
      expect(result.exitCode, 75, reason: '${codes(result)}');
      expect(codes(result), contains('concurrent_change'));
      expect(
        File(box.path('shipflow/local/settings.json')).readAsStringSync(),
        '{"otro": true}\n',
      );
    },
  );

  test('a reader that sees two generations retries once, then 75', () async {
    await box.run(ContextOperation.init);
    var reads = 0;
    final result = await box.run(
      ContextOperation.doctor,
      wrap: (real) => EditOnRead(real, () {
        box.file('shipflow/project.json', '{"generacion": ${++reads}}\n');
      }),
    );
    expect(result.exitCode, 75, reason: '${codes(result)}');
    expect(codes(result), contains('concurrent_change'));
    expect(reads, greaterThanOrEqualTo(2));
  });

  test('worktrees sharing one exclude report drift, never toggle it', () async {
    final linked = _linkedWorktree(box);
    await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.local,
    );
    final exclude = File(box.path('.git/info/exclude'));
    final before = exclude.readAsBytesSync();
    final other = ServiceSandbox.at(box.base, Directory(linked))..project();
    final result = await other.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.share,
    );
    expect(result.exitCode, 65, reason: '${codes(result)}');
    expect(codes(result), contains('sharing_conflict'));
    expect(exclude.readAsBytesSync(), before);
  });
}

/// Un repositorio con un commit y una segunda copia de trabajo vinculada.
String _linkedWorktree(ServiceSandbox box) {
  box.gitInit();
  final linked = '${box.base.path}/vinculado';
  for (final args in [
    ['commit', '-q', '--allow-empty', '-m', 'x'],
    ['worktree', 'add', '-q', linked, '-b', 'otra'],
  ]) {
    Process.runSync('git', args, workingDirectory: box.root.path);
  }
  return linked;
}

/// Un tercero que escribe justo cuando Shipflow toma el lease.
final class EditOnLease extends CrashingStore {
  EditOnLease(ContextStore real, this.edit) : super(real, 1 << 30);

  final void Function() edit;

  @override
  Future<ContextLease> acquirePublication(List<ContextResource> resources) {
    edit();
    return super.acquirePublication(resources);
  }
}

/// Un tercero que publica otra versión del contexto en cada lectura suya.
final class EditOnRead extends CrashingStore {
  EditOnRead(ContextStore real, this.edit) : super(real, 1 << 30);

  final void Function() edit;

  @override
  Future<List<int>?> readRelative(String path, {required int maxBytes}) async {
    final bytes = await super.readRelative(path, maxBytes: maxBytes);
    if (path == 'shipflow/project.json') edit();
    return bytes;
  }
}
