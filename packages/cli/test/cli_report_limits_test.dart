import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'runner_support.dart';

void main() {
  final sandbox = RunnerSandbox()..register();
  final seen = <ReportLimits>[];

  setUp(seen.clear);

  RecognitionContributor recording([RecognitionContributor? then]) =>
      (root, {required reportLimits}) {
        seen.add(reportLimits);
        return (then ?? sandbox.contribute)(root, reportLimits: reportLimits);
      };

  RecognitionContributor exceeding(ReportLimitDimension dimension) =>
      recording((_, {required reportLimits}) async {
        throw ReportLimitExceeded(dimension);
      });

  Future<Map<String, Object?>> run(
    List<String> extra,
    RecognitionContributor contributor,
  ) async {
    final response = await sandbox.run([
      'init',
      '--dry-run',
      '--json',
      ...extra,
    ], contributor: contributor);
    final json = decode(response);
    expect(response.exitCode, json['exitCode']);
    return json;
  }

  group('el perfil llega al contribuidor', () {
    test('omitido es standard, y no se arrastra de una invocación', () async {
      await run(['--report-budget=extended'], recording());
      await run([], recording());
      await run(['--report-budget=standard'], recording());
      expect([for (final l in seen) l.maxDerivedItems], [18432, 16384, 16384]);
      expect(
        [for (final l in seen) l.maxReportJsonBytes],
        [2359296, 2097152, 2097152],
      );
    });
  });

  group('al exceder, un reporte compacto no concluyente', () {
    setUp(() => Directory('${sandbox.root.path}/.git').createSync());

    test('conserva raíces y Git y descarta el inventario', () async {
      final json = await run([], exceeding(ReportLimitDimension.items));
      expect(json['status'], 'ambiguous');
      expect(json['exitCode'], 65);
      expect(json['requestedRoot'], sandbox.root.path);
      expect(json['resolvedRoot'], sandbox.root.path);
      expect(json['repository'], containsPair('status', 'detected'));
      for (final list in ['candidates', 'units', 'evidence', 'conflicts']) {
        expect(json[list], isEmpty, reason: list);
      }
      final limitation = (json['limitations']! as List).single as Map;
      expect(limitation['code'], 'report_limit_reached');
      expect(limitation['blocking'], isTrue);
      expect(limitation['message'], contains('elementos del reporte'));
      expect(limitation['message'], contains('--report-budget=extended'));
      expect(json['proposal'], containsPair('eligible', false));
      expect((json['proposal']! as Map)['actions'], isEmpty);
    });

    test('en ampliado explica el techo, sin volver a ofrecerlo', () async {
      final json = await run([
        '--report-budget=extended',
      ], exceeding(ReportLimitDimension.textBytes));
      final message =
          ((json['limitations']! as List).single as Map)['message'] as String;
      expect(message, contains('texto del reporte del perfil ampliado'));
      expect(message, contains('máximo disponible en esta versión'));
      expect(message, isNot(contains('--report-budget=extended')));
    });

    test('lo que el ensamblador cuenta también corta', () async {
      final json = await run(
        [],
        recording((_, {required reportLimits}) async {
          return RecognitionContribution(
            candidates: const [],
            units: const [],
            evidence: [
              for (var i = 0; i < 16385; i++)
                RecognitionEvidence(
                  id: 'e$i',
                  kind: 'k',
                  path: 'p',
                  value: 'v',
                  fingerprint: 'f',
                ),
            ],
            conflicts: const [],
            limitations: const [],
          );
        }),
      );
      expect(
        ((json['limitations']! as List).single as Map)['code'],
        'report_limit_reached',
      );
    });
  });

  test('un límite de lectura conserva lo observado', () async {
    final json = await run(
      [],
      recording((root, {required reportLimits}) async {
        final normal = await sandbox.contribute(
          root,
          reportLimits: reportLimits,
        );
        return RecognitionContribution(
          candidates: normal.candidates,
          units: normal.units,
          evidence: normal.evidence,
          conflicts: const [],
          limitations: const [
            RecognitionLimitation(
              code: 'scan_limit_reached',
              message: 'se alcanzó el máximo',
              path: 'x',
              blocking: true,
            ),
          ],
        );
      }),
    );
    expect(json['status'], 'ambiguous');
    expect(json['evidence'], hasLength(1));
    expect(json['units'], hasLength(1));
  });

  test('otro error no se disfraza de límite', () async {
    await expectLater(
      sandbox.run(
        ['init', '--dry-run'],
        contributor: (_, {required reportLimits}) =>
            Future.error(StateError('defecto')),
      ),
      throwsStateError,
    );
  });
}
