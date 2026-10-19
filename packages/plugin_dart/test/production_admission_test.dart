import 'dart:convert';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

int bytes(String text) => utf8.encode(text).length;

/// Una fila de evidencia: tipo, ruta, valor y huella `sha256:<64>`.
int evidenceRow(String kind, String value) =>
    bytes(kind) + bytes('pubspec.yaml') + bytes(value) + 71;

/// Una limitación de truncado del manifiesto.
int truncationRow(String message) =>
    bytes('observed_value_truncated') + bytes(message) + bytes('pubspec.yaml');

// Testigo de CV1-S02 sobre la producción real. Cada elemento mide más de
// 4096 bytes, así que deja una limitación de truncado (unos 100 bytes)
// antes de su evidencia (unos 4200). Cobrando de a uno, la secuencia es
// nombre, L1, E1, L2, E2…: el texto se agota en la tercera evidencia. Si la
// lista se expandiera entera antes de cobrar, las diez limitaciones irían
// primero y lo que se agotaría serían los elementos. La dimensión que corta
// distingue ambos órdenes sin instrumentar el código.
void main() {
  final sandbox = ScanSandbox()..register();

  Future<void> expectInterleaved({
    required String manifest,
    required String kind,
    required String truncationMessage,
    required String preview,
  }) async {
    sandbox.place('pubspec.yaml', manifest);
    final name = evidenceRow('manifest.package_name', 'n');
    final limitation = truncationRow(truncationMessage);
    final evidence = evidenceRow(kind, preview);
    await expectLater(
      recognizeDartProject(
        sandbox.root,
        reportLimits: ReportLimits(
          maxDerivedItems: 11,
          maxDerivedTextBytes: name + 10 * limitation + 2 * evidence + 100,
        ),
      ),
      throwsA(
        isA<ReportLimitExceeded>().having(
          (e) => e.dimension,
          'dimension',
          ReportLimitDimension.textBytes,
        ),
      ),
    );
  }

  final long = 'x' * 5000;
  final preview = '${'x' * 4093}…';

  test('la lista workspace se cobra miembro por miembro', () async {
    await expectInterleaved(
      manifest: 'name: n\nworkspace:\n${'  - $long\n' * 10}',
      kind: 'manifest.workspace_member',
      truncationMessage: '«workspace» excede 4096 bytes y se conserva truncado',
      preview: preview,
    );
  });

  test('las dependencias locales se cobran una por una', () async {
    final dependencies = [
      for (var i = 0; i < 10; i++) '  d$i$long: {path: p}',
    ].join('\n');
    await expectInterleaved(
      manifest: 'name: n\ndependencies:\n$dependencies\n',
      kind: 'manifest.path_dependency',
      truncationMessage:
          'una dependencia local de «dependencies» excede 4096 bytes; se '
          'conserva truncada y no se interpreta',
      preview: '${'dependencies.d0${'x' * 4077}'}…',
    );
  });
}
