import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'human_expectations.dart';
import 'recognition_reports.dart';

void main() {
  test('reconocido: qué se vio, qué no se comprobó y qué sigue', () {
    expect(
      human(report()),
      '${expectedHead}Proyecto reconocido\n'
      'Carpeta: /resuelta\n'
      'Alias: /solicitada\n'
      'Tecnología: Stack\n'
      'Paquetes observados: 2\n'
      '  a · packages/a\n'
      '  b · packages/b\n'
      '\n'
      'No se detectaron conflictos ni límites en este reconocimiento.\n'
      'La propuesta es elegible, pero no se aplicó.\n'
      '$expectedScope'
      '\n'
      '$expectedEffects'
      'La inspección terminó. Esta versión todavía no aplica la inicialización '
      'ni inicia tareas.\n'
      '$expectedDetail',
    );
  });

  test('no concluyente: conflictos con sus fuentes y limitaciones', () {
    final payload = human(
      report(
        conflicts: [
          RecognitionConflict(
            code: 'versions_disagree',
            message: 'no coinciden',
            evidenceIds: const ['e0002', 'e0001'],
          ),
        ],
        limitations: const [
          RecognitionLimitation(
            code: 'note',
            message: 'sólo una nota',
            path: null,
            blocking: false,
          ),
          RecognitionLimitation(
            code: 'subtree_unreadable',
            message: 'no se pudo listar',
            path: 'cerrado',
            blocking: true,
          ),
        ],
      ),
    );
    expect(
      payload,
      '${expectedHead}Reconocimiento no concluyente\n'
      'Carpeta: /resuelta\n'
      'Alias: /solicitada\n'
      'Tecnología: Stack\n'
      'Paquetes observados: 2\n'
      '  a · packages/a\n'
      '  b · packages/b\n'
      '\n'
      'Conflictos:\n'
      '  - no coinciden · fuentes: packages/a/manifest (a), '
      'packages/b/manifest (b)\n'
      'Limitaciones:\n'
      '  - sólo una nota (no bloquea)\n'
      '  - no se pudo listar · cerrado\n'
      '$expectedBlocked'
      '$expectedScope'
      '\n'
      '$expectedEffects'
      'Revisa las fuentes indicadas y repite la inspección después de decidir '
      'su corrección.\n'
      'Revisa las limitaciones indicadas; el reconocimiento está incompleto.\n'
      '$expectedDetail',
    );
  });

  test('no soportado: explica el alcance Dart y Flutter', () {
    final unsupported = assembleRecognition(
      requestedRoot: '/r',
      resolvedRoot: '/r',
      repository: absentRepository,
      contributions: [
        RecognitionContribution(
          candidates: const [],
          units: const [],
          evidence: const [],
          conflicts: const [],
          limitations: const [],
        ),
      ],
    );
    expect(
      human(unsupported),
      '${expectedHead}Proyecto no soportado\n'
      'Carpeta: /r\n'
      'Paquetes observados: 0\n'
      '\n'
      'No se detectaron conflictos ni límites en este reconocimiento.\n'
      '$expectedScope'
      '\n'
      '$expectedEffects'
      'Esta versión reconoce proyectos Dart y Flutter mediante sus manifiestos '
      'y marcadores.\n'
      '$expectedDetail',
    );
  });

  test('carpeta inválida: comprobar existencia y permisos', () {
    final invalid = RecognitionReport.invalidRoot(
      requestedRoot: '/no-existe',
      reason: const RecognitionLimitation(
        code: 'root_not_found',
        message: 'la raíz no existe',
        path: null,
        blocking: true,
      ),
    );
    final response = presentRecognition(invalid, json: false);
    expect(response.exitCode, 66);
    expect(
      response.payload,
      '${expectedHead}No se pudo inspeccionar la carpeta\n'
      'Carpeta: /no-existe\n'
      '\n'
      'Limitaciones:\n'
      '  - la raíz no existe\n'
      '$expectedScope'
      '\n'
      '$expectedEffects'
      'Comprueba que la carpeta exista y que tengas permiso para leerla.\n'
      '$expectedDetail',
    );
  });

  group('exceso del reporte', () {
    RecognitionReport reached(bool extended) => reportLimitReached(
      requestedRoot: '/alias',
      resolvedRoot: '/real',
      repository: absentRepository,
      dimension: ReportLimitDimension.items,
      extended: extended,
    );

    test('en normal ofrece ampliar', () {
      expect(
        human(reached(false)),
        '${expectedHead}Reconocimiento no concluyente\n'
        'Carpeta: /real\n'
        'Alias: /alias\n'
        '\n'
        'Limitaciones:\n'
        '  - El reconocimiento alcanzó el límite de elementos del reporte del '
        'perfil normal; no se publica un inventario parcial.\n'
        '$expectedBlocked'
        '$expectedScope'
        '\n'
        '$expectedEffects'
        'Puedes repetir con shipflow init --dry-run --report-budget=extended. '
        'El perfil ampliado puede consumir más recursos.\n'
        '$expectedDetail',
      );
    });

    test('en ampliado explica el techo y conserva el perfil', () {
      final payload = human(reached(true), ReportBudgetProfile.extended);
      expect(
        payload,
        endsWith(
          '$expectedEffects'
          'Se alcanzó el máximo disponible en esta versión. Inspecciona una '
          'raíz tecnológica más acotada; esto cambia el alcance de la '
          'inspección.\n'
          'Para repetir la inspección con detalle estructurado:\n'
          '  shipflow init --dry-run --json --report-budget=extended\n',
        ),
      );
      expect(payload, contains('del perfil ampliado; no se publica'));
    });
  });
}
