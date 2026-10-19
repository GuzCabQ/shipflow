import 'package:cli/cli.dart';
import 'package:core/core.dart';

import 'recognition_reports.dart';

// Los textos esperados viven aquí, escritos a mano: no salen del renderer.
const expectedHead = 'Shipflow · reconocimiento del proyecto\n';
const expectedScope =
    'No se comprobó si el proyecto compila, si sus pruebas pasan, si respeta '
    'su arquitectura ni si el SDK está instalado.\n';
const expectedEffects =
    'No se modificó el proyecto. Shipflow no guardó este reporte ni creó un '
    'expediente.\n';
const expectedDetail =
    'Para repetir la inspección con detalle estructurado:\n'
    '  shipflow init --dry-run --json\n';
const expectedBlocked =
    'La propuesta no puede aplicarse: hay conflictos o limitaciones '
    'bloqueantes.\n';

String human(RecognitionReport report, [ReportBudgetProfile? profile]) =>
    presentRecognition(
      report,
      json: false,
      budgetProfile: profile ?? ReportBudgetProfile.standard,
    ).payload;

RecognitionReport wide({
  int units = 0,
  List<RecognitionConflict> conflicts = const [],
  List<RecognitionLimitation> limitations = const [],
}) => assembleRecognition(
  requestedRoot: '/r',
  resolvedRoot: '/r',
  repository: absentRepository,
  contributions: [
    RecognitionContribution(
      candidates: [
        StackCandidate(
          id: 'dart',
          displayName: 'Dart',
          pluginId: 'p',
          evidenceIds: const ['e0000'],
        ),
      ],
      units: [
        for (var i = 0; i < units; i++)
          ProjectUnit(
            id: 'u$i',
            name: 'p${i.toString().padLeft(2, '0')}',
            kind: 'k',
            path: 'packages/p${i.toString().padLeft(2, '0')}',
            evidenceIds: const ['e0000'],
          ),
      ],
      evidence: [evidence('e0000', 'pubspec.yaml', 'x')],
      conflicts: conflicts,
      limitations: limitations,
    ),
  ],
);

RecognitionLimitation limitation(String code, {bool blocking = true}) =>
    RecognitionLimitation(
      code: code,
      message: 'mensaje $code',
      path: null,
      blocking: blocking,
    );
