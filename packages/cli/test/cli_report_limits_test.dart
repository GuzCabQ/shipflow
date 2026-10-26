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
      (root, {required reportLimits, required authorizedOmissions}) {
        seen.add(reportLimits);
        return (then ?? sandbox.contribute)(
          root,
          reportLimits: reportLimits,
          authorizedOmissions: authorizedOmissions,
        );
      };

  RecognitionContributor exceeding(ReportLimitDimension dimension) => recording(
    (_, {required reportLimits, required authorizedOmissions}) async {
      throw ReportLimitExceeded(dimension);
    },
  );

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
      for (final list in [
        'candidates',
        'units',
        'evidence',
        'conflicts',
        'relations',
        'contextSources',
        'omissions',
      ]) {
        expect(json[list], isEmpty, reason: list);
      }
      expect(json['schemaVersion'], 3);
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
      final json = await run([], recording(_overflowingEvidence));
      expect(
        ((json['limitations']! as List).single as Map)['code'],
        'report_limit_reached',
      );
    });
  });

  test('un límite de lectura conserva lo observado', () async {
    final json = await run(
      [],
      recording(
        (root, {required reportLimits, required authorizedOmissions}) =>
            _withReadLimit(sandbox, root, reportLimits, authorizedOmissions),
      ),
    );
    expect(json['status'], 'ambiguous');
    expect(json['evidence'], hasLength(1));
    expect(json['units'], hasLength(1));
  });

  test('otro error no se disfraza de límite', () async {
    await expectLater(
      sandbox.run(
        ['init', '--dry-run'],
        contributor:
            (_, {required reportLimits, required authorizedOmissions}) =>
                Future.error(StateError('defecto')),
      ),
      throwsStateError,
    );
  });

  group('un JSON que los escapes inflan', () {
    // 250 valores de 4000 controles: caben en las cotas derivadas (1 MB de
    // texto), pero escapados son unos 6 MB de JSON.
    RecognitionContributor inflating() => recording((
      _, {
      required reportLimits,
      required authorizedOmissions,
    }) async {
      return RecognitionContribution(
        candidates: const [],
        units: const [],
        evidence: [
          for (var i = 0; i < 250; i++)
            RecognitionEvidence(
              role: EvidenceRole.identity,
              label: 'Nombre del paquete',
              id: 'e$i',
              kind: 'k',
              path: 'p',
              value: '\x01' * 4000,
              fingerprint: 'f',
            ),
        ],
        conflicts: const [],
        limitations: const [],
      );
    });

    test('corta igual en JSON y en la vista humana', () async {
      final json = await run([], inflating());
      final message =
          ((json['limitations']! as List).single as Map)['message'] as String;
      expect(message, contains('tamaño JSON del reporte del perfil normal'));
      final human = await sandbox.run([
        'init',
        '--dry-run',
      ], contributor: inflating());
      expect(human.exitCode, 65);
      expect(human.payload, contains('tamaño JSON del reporte'));
    });

    test('en ampliado lo mide contra la cota ampliada', () async {
      final json = await run(['--report-budget=extended'], inflating());
      final message =
          ((json['limitations']! as List).single as Map)['message'] as String;
      expect(message, contains('del perfil ampliado'));
    });
  });
}

/// Más evidencia de la que el ensamblador admite con el perfil normal.
Future<RecognitionContribution> _overflowingEvidence(
  Directory _, {
  required ReportLimits reportLimits,
  required List<AuthorizedOmission> authorizedOmissions,
}) async => RecognitionContribution(
  candidates: const [],
  units: const [],
  evidence: [
    for (var i = 0; i < 16385; i++)
      RecognitionEvidence(
        role: EvidenceRole.identity,
        label: 'Nombre del paquete',
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

/// Lo normal del sandbox con una limitación de lectura bloqueante.
Future<RecognitionContribution> _withReadLimit(
  RunnerSandbox sandbox,
  Directory root,
  ReportLimits reportLimits,
  List<AuthorizedOmission> authorizedOmissions,
) async {
  final normal = await sandbox.contribute(
    root,
    reportLimits: reportLimits,
    authorizedOmissions: authorizedOmissions,
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
}
