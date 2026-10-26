import 'dart:io';

import 'package:test/test.dart';

/// Un directorio temporal canónico por prueba, con Git real a mano.
final class GitSandbox {
  late Directory base;

  void register() {
    setUp(() {
      base = Directory(
        Directory.systemTemp
            .createTempSync('shipflow-git-')
            .resolveSymbolicLinksSync(),
      );
    });
    tearDown(() => base.deleteSync(recursive: true));
  }

  Directory directory(String relative) =>
      Directory('${base.path}/$relative')..createSync(recursive: true);

  File file(String relative, String text) {
    final file = File('${base.path}/$relative');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(text);
  }

  /// Un repositorio con un commit inicial en [relative].
  Directory repository(String relative) {
    final dir = directory(relative);
    git(['init', '-q', '-b', 'main'], dir);
    git(['config', 'user.email', 'prueba@example.invalid'], dir);
    git(['config', 'user.name', 'Prueba'], dir);
    File('${dir.path}/README').writeAsStringSync('x\n');
    git(['add', 'README'], dir);
    git(['commit', '-q', '-m', 'inicio'], dir);
    return dir;
  }

  /// Un ejecutable `git` falso en [relative] que corre [script] de shell.
  Directory fakeGit(String relative, String script) {
    final dir = directory(relative);
    final file = File('${dir.path}/git')
      ..writeAsStringSync('#!/bin/sh\n$script\n');
    Process.runSync('chmod', ['755', file.path]);
    return dir;
  }
}

/// Git real, para preparar escenarios: las pruebas sí heredan su entorno.
ProcessResult git(List<String> args, Directory cwd) {
  final result = Process.runSync('git', args, workingDirectory: cwd.path);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
  return result;
}

/// El PATH real con el directorio de [git] real, para el adapter.
Map<String, String> realPath() => {
  'PATH': Platform.environment['PATH']!,
  'HOME': Platform.environment['HOME']!,
};
