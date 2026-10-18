import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

import 'cli_support.dart';

void main() {
  group('invariantes de toda respuesta', () {
    final cases = <List<String>>[
      [],
      ['--help'],
      ['-h'],
      ['--json'],
      ['--version'],
      ['--version', '--json'],
      ['--inventada'],
      ['--json', '--inventada'],
      ['--help', '--version'],
      ['-h', '--help'],
      ['--json=true'],
      ['a\nb'],
      ['--json', 'a\nb'],
      ['x' * 5000],
    ];

    for (final arguments in cases) {
      test('${jsonEncode(arguments).substring(0, 1)}… '
          '${arguments.length} argumento(s): una sola nueva línea final', () {
        final payload = evaluateCli(arguments, version: version).payload;
        expect(payload.endsWith('\n'), isTrue);
        expect(payload.endsWith('\n\n'), isFalse);
      });
    }

    for (final arguments in cases.where((a) => a.contains('--json'))) {
      test('${arguments.length} argumento(s) con --json: una línea JSON '
          'decodificable con exitCode coherente', () {
        final response = evaluateCli(arguments, version: version);
        expect(response.channel, CliOutputChannel.stdout);
        final lines = const LineSplitter().convert(response.payload);
        expect(lines, hasLength(1));
        final decoded = jsonDecode(lines.single) as Map<String, Object?>;
        expect(decoded['schemaVersion'], 1);
        expect(decoded['exitCode'], response.exitCode);
        expect(decoded.values, isNot(contains(null)));
      });
    }

    test('ninguna respuesta se identifica como sdlc', () {
      for (final arguments in cases) {
        final payload = evaluateCli(arguments, version: version).payload;
        expect(payload.toLowerCase(), isNot(contains('sdlc')));
        if (!payload.contains('"type":"error"')) {
          expect(payload, contains('shipflow'));
        }
      }
    });

    test('los únicos códigos son 0 y 64', () {
      for (final arguments in cases) {
        expect([
          0,
          64,
        ], contains(evaluateCli(arguments, version: version).exitCode));
      }
    });

    test('la misma entrada produce la misma respuesta', () {
      for (final arguments in cases) {
        final a = evaluateCli(arguments, version: version);
        final b = evaluateCli(List.of(arguments), version: version);
        expect(
          [a.exitCode, a.channel, a.payload],
          [b.exitCode, b.channel, b.payload],
        );
      }
    });
  });

  test('la evaluación no importa entrada y salida del SDK', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:cli/src/cli_application.dart'),
    );
    final source = File.fromUri(uri!).readAsStringSync();
    final imports = RegExp(
      r'''^import\s+'([^']+)';''',
      multiLine: true,
    ).allMatches(source).map((m) => m.group(1)).toSet();
    expect(imports, {'dart:convert', 'cli_response.dart'});
  });
}
