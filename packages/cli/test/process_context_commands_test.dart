@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/context/context_codec.dart';
import 'package:test/test.dart';

import 'init_process_support.dart';

void main() {
  final process = InitProcessSandbox()..register();
  const codec = ContextCodec();

  test('a first session, a return and a doctor, compiled', () async {
    process.place('pubspec.yaml', 'name: app\n');
    final first = await process.run(['init', '--json']);
    expect(first.exitCode, 0, reason: first.stdout + first.stderr);
    expect(first.stderr, isEmpty);
    codec.decodeResponse(utf8.encode(first.stdout));
    expect(
      File('${process.root.path}/shipflow/project.json').existsSync(),
      isTrue,
    );
    final before = treeSnapshot(process.root);
    final again = await process.run(['init']);
    expect(again.exitCode, 0, reason: again.stdout);
    expect(again.stdout, contains('Contexto disponible'));
    final doctor = await process.run(['doctor', '--json']);
    expect(doctor.exitCode, 0);
    expect(
      codec.decodeResponse(utf8.encode(doctor.stdout)).effects.wrote,
      isFalse,
    );
    expect(treeSnapshot(process.root), before);
    expect(process.home.listSync(), isEmpty);
    expect(process.temp.listSync(), isEmpty);
  });

  test('without a terminal the choice is required, never awaited', () async {
    process.place('pubspec.yaml', 'name: app\n');
    Process.runSync('git', ['init', '-q'], workingDirectory: process.root.path);
    final result = await process
        .run(['init'], environment: {'PATH': '/usr/bin:/bin'})
        .timeout(const Duration(seconds: 60));
    expect(result.exitCode, 65, reason: result.stdout + result.stderr);
    expect(result.stdout, contains('--sharing=share'));
    expect(Directory('${process.root.path}/shipflow').existsSync(), isFalse);
  });

  test('an explicit choice without Git writes nothing', () async {
    process.place('pubspec.yaml', 'name: app\n');
    final result = await process.run(['init', '--sharing=local', '--json']);
    expect(result.exitCode, 65);
    expect(
      (jsonDecode(result.stdout) as Map<String, Object?>)['outcome'],
      'needs_attention',
    );
    expect(Directory('${process.root.path}/shipflow').existsSync(), isFalse);
  });
}
