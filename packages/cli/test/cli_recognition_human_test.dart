import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'human_expectations.dart';
import 'recognition_reports.dart';

void main() {
  test('reconocido: qué se vio, qué no se comprobó y qué sigue', () {
    expect(
      human(report()),
      '${expectedHead}Identidad reconocida dentro del alcance indicado\n'
      'Carpeta: /resuelta\n'
      'Alias: /solicitada\n'
      '$expectedTwoUnits'
      'Resultado\n'
      '  No se detectaron conflictos ni límites en este reconocimiento.\n'
      '  La propuesta es elegible, pero no se aplicó.\n'
      '$expectedScope'
      '$expectedEffects'
      '$expectedRecognizedNext'
      '$expectedDetail',
    );
  });

  test('no concluyente: conflictos con sus fuentes y limitaciones', () {
    final payload = human(conflicted());
    expect(
      payload,
      '${expectedHead}Reconocimiento no concluyente\n'
      'Carpeta: /resuelta\n'
      'Alias: /solicitada\n'
      'Hay 2 causas que impiden continuar; se detallan en «Resultado».\n'
      '$expectedTwoUnits'
      'Resultado\n'
      '  Qué impide continuar:\n'
      '    versions_disagree (1):\n'
      '      - no coinciden · fuentes: packages/a/manifest (a), '
      'packages/b/manifest (b)\n'
      '    subtree_unreadable (1):\n'
      '      - no se pudo listar · cerrado\n'
      '  Advertencias que no bloquean:\n'
      '    note (1):\n'
      '      - sólo una nota\n'
      '  La propuesta no puede aplicarse: hay contradicciones entre '
      'declaraciones y limitaciones bloqueantes.\n'
      '$expectedScope'
      '$expectedEffects'
      '  Revisa las fuentes indicadas y repite la inspección después de '
      'decidir su corrección.\n'
      '$expectedLimitsNext'
      '$expectedDetail',
    );
  });

  test('no soportado: explica el alcance Dart y Flutter', () {
    final unsupported = assembleRecognition(
      requestedRoot: '/r',
      resolvedRoot: '/r',
      repository: absentRepository,
      contributions: const [],
    );
    expect(
      human(unsupported),
      '${expectedHead}Proyecto no soportado\n'
      'Carpeta: /r\n'
      '\n'
      'Identidad\n'
      '  Tecnología: no identificada\n'
      '\n'
      'Unidades y relaciones\n'
      '  Paquetes observados: 0\n'
      '  Relaciones declaradas: ninguna\n'
      '$expectedEmptyBlocks'
      'Resultado\n'
      '  No se detectaron conflictos ni límites en este reconocimiento.\n'
      '$expectedScope'
      '$expectedEffects'
      '  Esta versión reconoce proyectos Dart y Flutter mediante sus '
      'manifiestos y marcadores.\n'
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
      'Hay 1 causa que impide continuar; se detalla en «Resultado».\n'
      '\n'
      'Resultado\n'
      '  Qué impide continuar:\n'
      '    root_not_found (1):\n'
      '      - la raíz no existe\n'
      '$expectedScope'
      '$expectedEffects'
      '  Comprueba que la carpeta exista y que tengas permiso para leerla.\n'
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
        'Hay 1 causa que impide continuar; se detalla en «Resultado».\n'
        '\n'
        'Resultado\n'
        '  Qué impide continuar:\n'
        '    report_limit_reached (1):\n'
        '      - El reconocimiento alcanzó el límite de elementos del reporte '
        'del perfil normal; no se publica un inventario parcial.\n'
        '  La propuesta no puede aplicarse: hay limitaciones bloqueantes.\n'
        '$expectedScope'
        '$expectedEffects'
        '  Puedes repetir con shipflow init --dry-run '
        '--report-budget=extended. El perfil ampliado puede consumir más '
        'recursos.\n'
        '$expectedDetail',
      );
    });

    test('en ampliado explica el techo y conserva el perfil', () {
      final payload = human(reached(true), ReportBudgetProfile.extended);
      expect(
        payload,
        endsWith(
          '$expectedEffects'
          '  Se alcanzó el máximo disponible en esta versión. Inspecciona una '
          'raíz tecnológica más acotada; esto cambia el alcance de la '
          'inspección.\n'
          '\n'
          'Para repetir la inspección con detalle estructurado:\n'
          '  shipflow init --dry-run --json --report-budget=extended\n',
        ),
      );
      expect(payload, contains('del perfil ampliado; no se publica'));
    });
  });
}

/// Un conflicto con dos fuentes, una nota que no bloquea y una lectura que sí.
RecognitionReport conflicted() => report(
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
);
