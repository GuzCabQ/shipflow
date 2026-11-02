import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Un levantamiento neutral de dos unidades con una referencia local, con la
/// forma del fixture `valid-local` del paquete V3: sus IDs son opacos aquí,
/// porque core no calcula huellas.
const assessmentProjectId = '11111111-1111-4111-8111-111111111111';
const contextHash =
    '03a96e6318f48a2464456e960bcb254e1f37855fd564d4b0750bcc3fbcc61b7b';
const rootUnit = 'u_root';
const widgetsUnit = 'u_widgets';
const mainFile = 'f_main';
const widgetFile = 'f_widget';

String hashOf(String seed) => seed * 64;

Map<String, Object?> witnessJson(
  String capability,
  List<int> counts, [
  String state = 'complete',
]) => {
  'id': capability,
  'capability': capability,
  'producerVersion': 'source-topology-v3.2',
  'state': state,
  'expected': counts[0],
  'processed': counts[1],
  'failed': counts[2],
  'omitted': counts[3],
};

Map<String, Object?> inputJson(
  String path,
  String kind, {
  String state = 'read',
  String? sha256,
  String? reason,
}) => {
  'path': path,
  'kind': kind,
  'state': state,
  'sha256': state == 'read' || state == 'listed' ? sha256 ?? hashOf('b') : null,
  'reason': reason,
};

Map<String, Object?> fileJson(String id, String path, String unit) => {
  'id': id,
  'path': path,
  'unitId': unit,
  'inputPath': path,
  'role': 'source',
  'parseState': 'parsed',
  'witnessId': 'source_references',
  'editable': 'unknown',
};

Map<String, Object?> localClaimJson() => {
  'id': 'c_main_widget',
  'witnessId': 'source_references',
  'sourceFileId': mainFile,
  'targetFileId': widgetFile,
  'targetUnitId': widgetsUnit,
  'targetLabel': 'packages/widgets/lib/widget.src',
  'relation': 'source_reference',
  'resolution': 'local',
  'reason': null,
  'condition': 'always',
  'groupId': 'g_main_0',
  'evidence': {'offset': 0, 'length': 45, 'line': 1, 'column': 1},
  'sourceMetadata': {'directive': 'import', 'conditionText': null},
};

/// El snapshot válido de referencia, como JSON mutable.
Map<String, Object?> snapshotJson() => {
  'snapshotId': hashOf('a'),
  'observedAt': '2026-11-02T12:00:00Z',
  'producer': {
    'version': '0.3.0-spec',
    'contract': 'source-topology-v3.2',
    'pluginId': 'plugin_example',
    'parserVersion': '14.1.0',
  },
  'contextDigest': contextHash,
  'profile': 'standard',
  'coverage': 'complete',
  'inventoryComplete': true,
  'units': [
    {'id': rootUnit, 'path': '.', 'label': 'example'},
    {'id': widgetsUnit, 'path': 'packages/widgets', 'label': 'widgets'},
  ],
  'inputs': _inputs(),
  'files': [
    fileJson(mainFile, 'lib/main.src', rootUnit),
    fileJson(widgetFile, 'packages/widgets/lib/widget.src', widgetsUnit),
  ],
  'claims': [localClaimJson()],
  'witnesses': _witnesses(),
  'contextLinks': [_readmeLink()],
  'diagnostics': <Object?>[],
};

List<Object?> _inputs() => [
  inputJson('.', 'directory', state: 'listed'),
  inputJson('lib/main.src', 'source'),
  inputJson('manifest.example', 'recognition_source'),
  inputJson('packages/widgets/lib/widget.src', 'source'),
  inputJson('packages/widgets/manifest.example', 'recognition_source'),
  inputJson('shipflow/project.json', 'context', sha256: contextHash),
];

List<Object?> _witnesses() => [
  witnessJson('context_candidates', [1, 1, 0, 0]),
  witnessJson('local_resolution', [1, 1, 0, 0]),
  witnessJson('source_inventory', [6, 6, 0, 0]),
  witnessJson('source_references', [2, 2, 0, 0]),
  witnessJson('test_inventory', [2, 2, 0, 0]),
];

Map<String, Object?> _readmeLink() => {
  'kind': 'candidate_source',
  'sourceId': 's_readme',
  'sourcePath': 'README.md',
  'label': 'documentation',
  'targetUnitId': null,
};

/// Un documento con [current] y, opcionalmente, [previous].
Map<String, Object?> documentJson({
  Map<String, Object?>? current,
  Map<String, Object?>? previous,
  int revision = 1,
}) => {
  'schemaVersion': 1,
  'kind': 'shipflow.assessment',
  'projectId': assessmentProjectId,
  'revision': revision,
  'current': current ?? snapshotJson(),
  'previous': previous,
};

/// Una copia profunda de [json], para mutarla sin tocar la de referencia.
Map<String, Object?> copyJson(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

/// Rechaza la construcción con el código semántico [code].
Matcher rejectsWith(String code) => throwsA(
  isA<ContextFormatException>()
      .having((e) => e.layer, 'layer', ContextFormatLayer.semantic)
      .having((e) => e.code, 'code', code),
);

AssessmentDocument buildDocument(Map<String, Object?> json) =>
    AssessmentDocument.fromJson(json);
