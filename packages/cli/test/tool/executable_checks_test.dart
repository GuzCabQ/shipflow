import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/executable_checks.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('shipflow-version-');
  });

  tearDown(() => sandbox.delete(recursive: true));

  Future<File> script(String body) async {
    final file = File('${sandbox.path}/ejecutable');
    file.writeAsStringSync('#!/bin/sh\n$body\n');
    final chmod = await Process.run('chmod', ['0755', file.path]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
    return file;
  }

  test('lee la versión de quien responde el contrato', () async {
    final file = await script("printf 'shipflow 1.2.3\\n'");
    expect(await reportedVersion(file), '1.2.3');
  });

  test('un ejecutable colgado se mata y se espera antes de volver', () async {
    final pidFile = File('${sandbox.path}/pid');
    final file = await script('echo \$\$ > "${pidFile.path}"\nexec sleep 60');
    final watch = Stopwatch()..start();
    final version = await reportedVersion(
      file,
      timeout: const Duration(seconds: 1),
    );
    expect(version, isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    final pid = pidFile.readAsStringSync().trim();
    final alive = await Process.run('kill', ['-0', pid]);
    expect(alive.exitCode, isNot(0), reason: 'el proceso $pid sigue vivo');
  });

  test('una salida que no es UTF-8 no es una versión', () async {
    final file = await script("printf 'shipflow \\377\\n'");
    expect(await reportedVersion(file), isNull);
  });

  test('un stderr que no es UTF-8 tampoco hace fallar la lectura', () async {
    final file = await script("printf 'shipflow 1.2.3\\n'; printf '\\377' >&2");
    expect(await reportedVersion(file), isNull);
  });
}
