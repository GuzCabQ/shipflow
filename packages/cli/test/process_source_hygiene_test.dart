@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'process_contract_support.dart';

void main() {
  test('el ejecutable público sólo importa lo que necesita', () async {
    final root = await packageRoot();
    final imports = <String, Set<String>>{};
    for (final directory in ['lib', 'bin']) {
      for (final file
          in Directory('${root.path}/$directory')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final relative = file.path.substring(root.path.length + 1);
        imports[relative] = {
          for (final m in RegExp(
            r"^(?:import|export)\s+'([^']+)'",
            multiLine: true,
          ).allMatches(file.readAsStringSync()))
            m.group(1)!,
        };
      }
    }
    expect(imports, {
      'bin/shipflow.dart': {
        'dart:io',
        'package:cli/cli.dart',
        'package:plugin_dart/plugin_dart.dart',
      },
      'lib/cli.dart': {
        'src/build_version.dart',
        'src/cli_application.dart',
        'src/cli_command.dart',
        'src/cli_emitter.dart',
        'src/cli_process_boundary.dart',
        'src/cli_response.dart',
        'src/recognition_presenter.dart',
        'src/recognition_runner.dart',
      },
      'lib/src/build_version.dart': <String>{},
      'lib/src/cli_application.dart': {
        'dart:convert',
        'cli_command.dart',
        'cli_response.dart',
      },
      'lib/src/cli_command.dart': {'terminal_text.dart'},
      'lib/src/cli_emitter.dart': {
        'dart:convert',
        'dart:io',
        'cli_response.dart',
        'internal_failure.dart',
      },
      'lib/src/cli_process_boundary.dart': {
        'dart:io',
        'cli_command.dart',
        'cli_response.dart',
        'internal_failure.dart',
        'recognition_runner.dart',
      },
      'lib/src/cli_response.dart': <String>{},
      'lib/src/internal_failure.dart': {
        'cli_application.dart',
        'cli_response.dart',
      },
      'lib/src/recognition_presenter.dart': {
        'package:core/core.dart',
        'cli_application.dart',
        'cli_response.dart',
        'terminal_text.dart',
      },
      'lib/src/recognition_runner.dart': {
        'dart:io',
        'package:core/core.dart',
        'package:vcs/vcs.dart',
        'cli_application.dart',
        'cli_command.dart',
        'cli_response.dart',
        'recognition_presenter.dart',
      },
      'lib/src/terminal_text.dart': <String>{},
    });
    for (final relative in ['bin/shipflow.dart', 'lib/src/cli_emitter.dart']) {
      final source = File('${root.path}/$relative').readAsStringSync();
      for (final effect in [
        'Process',
        'File',
        'Directory',
        'Link',
        'Socket',
        'HttpClient',
        'InternetAddress',
        'Platform',
        'exit(',
      ]) {
        expect(
          source,
          isNot(contains(_symbol(effect))),
          reason: '$relative: $effect',
        );
      }
    }
  });

  test(
    'el reconocimiento sólo lee: ni escribe, ni lanza procesos, ni usa red',
    () async {
      final root = await packageRoot();
      for (final relative in [
        'lib/src/recognition_runner.dart',
        'lib/src/cli_process_boundary.dart',
      ]) {
        final source = File('${root.path}/$relative').readAsStringSync();
        for (final effect in [
          'Process',
          'Socket',
          'HttpClient',
          'InternetAddress',
          'Platform',
          'exit(',
          'write',
          'create',
          'delete',
          'rename',
          'copy',
          'lock(',
        ]) {
          expect(
            source,
            isNot(contains(_symbol(effect))),
            reason: '$relative: $effect',
          );
        }
      }
    },
  );

  test('el reconocimiento no incorpora Linguist', () async {
    final packages = (await packageRoot()).parent;
    final self = File(
      '${(await packageRoot()).path}/test/process_source_hygiene_test.dart',
    ).absolute.path;
    final mentions = [
      for (final file
          in packages
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (f) =>
                    !f.path.contains('.dart_tool') &&
                    (f.path.endsWith('.dart') || f.path.endsWith('.yaml')) &&
                    f.absolute.path != self,
              ))
        if (file.readAsStringSync().toLowerCase().contains('linguist'))
          file.path.substring(packages.path.length + 1),
    ];
    expect(mentions, isEmpty);
  });

  test('ningún comentario de packages/cli nombra una ruta local', () async {
    final root = await packageRoot();
    final local = RegExp(
      r'/Users/|/home/|~/|/private/|/var/folders/|file://|[A-Za-z]:\\|'
      r'Downloads|Obsidian',
      caseSensitive: false,
    );
    final found = <String>[];
    for (final file
        in root
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) => f.path.endsWith('.dart') && !f.path.contains('.dart_tool'),
            )) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//') && local.hasMatch(line)) {
          found.add('${file.path.substring(root.path.length + 1)}:${i + 1}');
        }
      }
    }
    expect(found, isEmpty);
  });
}

/// [effect] como símbolo propio, no como parte de otro nombre: `Directory`
/// no coincide con `currentWorkingDirectory`.
RegExp _symbol(String effect) => RegExp('\\b${RegExp.escape(effect)}');
