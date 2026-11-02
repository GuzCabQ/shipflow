@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';

/// El exclude fuera de su perímetro y los contextos de carpetas superiores.
void main() {
  late ServiceSandbox box;
  setUp(() {
    box = ServiceSandbox.create();
    box.project();
    box.gitInit();
  });
  tearDown(() => box.dispose());

  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];
  File exclude() => File(box.path('.git/info/exclude'));

  test(
    'C2: an exclude that is a link is refused, its target untouched',
    () async {
      final foreign = File('${box.base.path}/dot/common-exclude')
        ..parent.createSync()
        ..writeAsStringSync('# ajeno\n');
      File('${box.base.path}/dot/exclude').writeAsStringSync('# otro\n');
      Process.runSync('chmod', ['600', '${box.base.path}/dot/exclude']);
      exclude().deleteSync();
      Link(exclude().path).createSync(foreign.path);
      final before = box.snapshot(Directory('${box.base.path}/dot'));
      final result = await box.run(
        ContextOperation.init,
        git: box.realGit,
        sharing: SharingChoice.local,
      );
      expect(result.exitCode, 65, reason: '${codes(result)}');
      expect(codes(result), contains('sharing_conflict'));
      expect(result.effects.excludeModified, isFalse);
      expect(box.snapshot(Directory('${box.base.path}/dot')), before);
      final mode = File('${box.base.path}/dot/exclude').statSync().mode & 511;
      expect(mode, 384);
    },
  );

  test(
    'C2: a missing info directory is created inside the administration',
    () async {
      Directory(box.path('.git/info')).deleteSync(recursive: true);
      final result = await box.run(
        ContextOperation.init,
        git: box.realGit,
        sharing: SharingChoice.local,
      );
      expect(result.exitCode, 0, reason: '${codes(result)}');
      expect(exclude().readAsStringSync(), contains('# shipflow:'));
    },
  );

  test('I5: a context above the repository root is not an ancestor', () async {
    File('${box.base.path}/shipflow/project.json')
      ..parent.createSync()
      ..writeAsStringSync('x');
    final result = await box.run(
      ContextOperation.init,
      git: box.realGit,
      sharing: SharingChoice.share,
    );
    expect(result.exitCode, 0, reason: '${codes(result)}');
  });

  test('I5: without Git no ancestor is searched', () async {
    File('${box.base.path}/shipflow/project.json')
      ..parent.createSync()
      ..writeAsStringSync('x');
    expect((await box.run(ContextOperation.init)).exitCode, 0);
  });

  test(
    'I5: from a subfolder of an initialized repository, use its root',
    () async {
      await box.run(
        ContextOperation.init,
        git: box.realGit,
        sharing: SharingChoice.share,
      );
      final sub = ServiceSandbox.at(
        box.base,
        Directory(box.path('apps/a'))..createSync(recursive: true),
      )..project();
      final result = await sub.run(
        ContextOperation.init,
        git: box.realGit,
        sharing: SharingChoice.share,
      );
      expect(codes(result), contains('ancestor_context'));
    },
  );
}
