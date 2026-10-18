import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recognition_reports.dart';

void main() {
  test('una sola línea con las claves en el orden del protocolo', () {
    final response = presentRecognition(report(), json: true);
    expect(response.channel, CliOutputChannel.stdout);
    expect(response.payload, endsWith('}\n'));
    expect('\n'.allMatches(response.payload).length, 1);
    final body = jsonDecode(response.payload) as Map<String, Object?>;
    expect(body.keys, [
      'schemaVersion',
      'type',
      'status',
      'requestedRoot',
      'resolvedRoot',
      'repository',
      'candidates',
      'units',
      'evidence',
      'conflicts',
      'limitations',
      'proposal',
      'effects',
      'exitCode',
    ]);
    expect(body['schemaVersion'], 1);
    expect(body['type'], 'init_dry_run');
    expect(body['repository'], {
      'status': 'absent',
      'root': null,
      'relation': 'none',
    });
    expect((body['units']! as List).map((u) => (u as Map)['path']), [
      'packages/a',
      'packages/b',
    ]);
    expect((body['candidates']! as List).single, {
      'id': 'stack',
      'displayName': 'Stack',
      'pluginId': 'plugin',
      'evidenceIds': ['e0001', 'e0002'],
    });
    expect(body['effects'], {
      'filesWritten': 0,
      'directoriesCreated': 0,
      'processesStarted': 0,
      'networkRequests': 0,
    });
  });

  test('el cuerpo es el reporte, sin pérdida', () {
    final source = report();
    final body =
        jsonDecode(presentRecognition(source, json: true).payload)
            as Map<String, Object?>;
    final rebuilt = RecognitionReport.fromJson(
      {...body}
        ..remove('schemaVersion')
        ..remove('type')
        ..remove('exitCode'),
    );
    expect(jsonEncode(rebuilt.toJson()), jsonEncode(source.toJson()));
  });

  group('cada estado con su código', () {
    void expectStatus(RecognitionReport r, String status, int code) {
      final response = presentRecognition(r, json: true);
      final body = jsonDecode(response.payload) as Map<String, Object?>;
      expect(body['status'], status);
      expect(body['exitCode'], code);
      expect(response.exitCode, code);
      expect(response.channel, CliOutputChannel.stdout);
    }

    test('recognized sale con 0', () {
      expectStatus(report(), 'recognized', 0);
    });

    test('ambiguous sale con 65', () {
      expectStatus(
        report(
          conflicts: [
            RecognitionConflict(
              code: 'c',
              message: 'm',
              evidenceIds: const ['e0001'],
            ),
          ],
        ),
        'ambiguous',
        65,
      );
    });

    test('unsupported sale con 65', () {
      expectStatus(
        assembleRecognition(
          requestedRoot: '/a',
          resolvedRoot: '/a',
          repository: absentRepository,
          contributions: const [],
        ),
        'unsupported',
        65,
      );
    });

    test('invalid_root sale con 66 y raíz resuelta null', () {
      final invalid = RecognitionReport.invalidRoot(
        requestedRoot: '/no-existe',
        reason: const RecognitionLimitation(
          code: 'root_not_found',
          message: 'm',
          path: null,
          blocking: true,
        ),
      );
      expectStatus(invalid, 'invalid_root', 66);
      final body =
          jsonDecode(presentRecognition(invalid, json: true).payload)
              as Map<String, Object?>;
      expect(body.containsKey('resolvedRoot'), isTrue);
      expect(body['resolvedRoot'], isNull);
    });
  });
}
