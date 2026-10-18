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
      'bin/shipflow.dart': {'dart:io', 'package:cli/cli.dart'},
      'lib/cli.dart': {
        'src/build_version.dart',
        'src/cli_application.dart',
        'src/cli_command.dart',
        'src/cli_emitter.dart',
        'src/cli_response.dart',
      },
      'lib/src/build_version.dart': <String>{},
      'lib/src/cli_application.dart': {
        'dart:convert',
        'cli_command.dart',
        'cli_response.dart',
      },
      'lib/src/cli_command.dart': {'terminal_text.dart'},
      'lib/src/terminal_text.dart': <String>{},
      'lib/src/cli_emitter.dart': {
        'dart:convert',
        'dart:io',
        'cli_response.dart',
      },
      'lib/src/cli_response.dart': <String>{},
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
        expect(source, isNot(contains(effect)), reason: '$relative: $effect');
      }
    }
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
