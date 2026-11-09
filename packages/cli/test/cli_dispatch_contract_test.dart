import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

// Sólo el barril nombra los símbolos de cli: si pierde runCli, este archivo
// deja de compilar aunque las pruebas que importan `src/` sigan bien.

final AssessmentPlugin _neverAssessed = (
  observe: (_, _, _) => fail('assess no observa aquí'),
  observeInputs: (_, _, _) => fail('assess no relee insumos aquí'),
  basisOf: (_) => fail('assess no proyecta la base aquí'),
  producer: (contract: 'contrato', pluginId: 'plugin', parserVersion: '1'),
);

Future<Never> _neverRecognized(
  Directory _, {
  required ReportLimits reportLimits,
  required List<AuthorizedOmission> authorizedOmissions,
}) => fail('este comando no reconoce');

Map<String, Object?> _decode(CliResponse response) =>
    jsonDecode(response.payload) as Map<String, Object?>;

List<Object?> _codes(CliResponse response) => [
  for (final d in _decode(response)['diagnostics']! as List)
    (d as Map<String, Object?>)['code'],
];

void main() {
  late Directory root;
  setUp(() {
    final created = Directory.systemTemp.createTempSync('shipflow-dispatch-');
    root = Directory(created.resolveSymbolicLinksSync());
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'bootstrap neither recognizes nor assesses, and writes nothing',
    () async {
      final response = await runCli(
        ['bootstrap', '--json'],
        version: '0.0.0-prueba',
        workingDirectory: root,
        recognizeProject: _neverRecognized,
        assessment: _neverAssessed,
      );
      expect(response.exitCode, 65);
      expect(_decode(response)['type'], 'bootstrap');
      expect(_decode(response)['outcome'], 'choice_required');
      expect(root.listSync(), isEmpty);
    },
  );

  test('assess runs with the plugin it receives, and only then', () async {
    final missing = Directory('${root.path}/no-existe');
    Future<CliResponse> assess(AssessmentPlugin? plugin) => runCli(
      ['assess', '--json'],
      version: '0.0.0-prueba',
      workingDirectory: missing,
      recognizeProject: _neverRecognized,
      assessment: plugin,
    );
    final without = await assess(null);
    expect(without.exitCode, 70);
    expect(_codes(without), ['unexpected']);
    final withPlugin = await assess(_neverAssessed);
    expect(withPlugin.exitCode, 66);
    expect(_codes(withPlugin), ['invalid_root']);
    expect(root.listSync(), isEmpty);
  });
}
