@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../../tool/promote.dart';
import '../../tool/src/promotion.dart';
import 'promotion_support.dart';

final class _Collector implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(bytes.addAll);

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

Future<Directory> packageRoot() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:cli/cli.dart'),
  );
  return File.fromUri(barrel!).parent.parent;
}

void main() {
  final box = PromotionSandbox()..register();

  group('promote.dart', () {
    late String script;

    setUp(() async {
      script = '${(await packageRoot()).path}/tool/promote.dart';
    });

    Future<(int, String, String)> invoke(List<String> arguments) async {
      final out = _Collector();
      final err = _Collector();
      final code = await runPromote(
        arguments,
        standardOut: IOSink(out),
        standardError: IOSink(err),
      );
      return (code, out.text, err.text);
    }

    test('exige las cuatro entradas explícitas', () async {
      final artifact = await box.executable('1.0.0');
      final full = [
        '--artifact',
        artifact.path,
        '--sha256',
        await sha(artifact),
        '--version',
        '1.0.0',
        '--bin-dir',
        box.binDir.path,
      ];
      for (var i = 0; i < full.length; i += 2) {
        final (code, out, err) = await invoke([
          ...full.sublist(0, i),
          ...full.sublist(i + 2),
        ]);
        expect(code, 64, reason: full[i]);
        expect(out, isEmpty);
        expect(err, contains('--bin-dir'));
      }
      expect((await invoke([...full, '--force', 'x'])).$1, 64);
      expect((await invoke([...full, ...full.sublist(0, 2)])).$1, 64);
      expect(box.binDir.listSync(), isEmpty);
    });

    test('promueve por línea de comandos', () async {
      final artifact = await box.executable('1.0.0');
      final (code, out, err) = await invoke([
        '--artifact',
        artifact.path,
        '--sha256',
        await sha(artifact),
        '--version',
        '1.0.0',
        '--bin-dir',
        box.binDir.path,
      ]);
      expect(code, 0, reason: err);
      expect(out, contains('shipflow 1.0.0'));
      await box.expectClean('1.0.0');
    });

    test('un rechazo sale con código 1', () async {
      final artifact = await box.executable('1.0.0');
      final (code, out, err) = await invoke([
        '--artifact',
        artifact.path,
        '--sha256',
        '0' * 64,
        '--version',
        '1.0.0',
        '--bin-dir',
        box.binDir.path,
      ]);
      expect(code, 1);
      expect(out, isEmpty);
      expect(err, contains('SHA-256'));
    });

    test('otra promoción con el lock tomado no modifica nada', () async {
      await box.install(await box.executable('1.0.0'));
      File('${box.binDir.path}/$lockName').createSync();
      final artifact = await box.executable('2.0.0');
      // El lock es de proceso: leer su archivo desde acá lo liberaría, así
      // que el estado se toma antes de adquirirlo.
      final before = await state(box.binDir);
      final lock = await File(
        '${box.binDir.path}/$lockName',
      ).open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      try {
        final contender = await Process.run(Platform.resolvedExecutable, [
          'run',
          script,
          '--artifact',
          artifact.path,
          '--sha256',
          await sha(artifact),
          '--version',
          '2.0.0',
          '--bin-dir',
          box.binDir.path,
        ]).timeout(const Duration(minutes: 2));
        expect(contender.exitCode, 1, reason: '${contender.stderr}');
        expect(contender.stderr, contains('otra promoción'));
        expect(await state(box.binDir), before);
      } finally {
        await lock.unlock();
        await lock.close();
      }
      await promote(await box.request(await box.executable('2.0.0'), '2.0.0'));
      await box.expectClean('2.0.0');
    });
  });
}
