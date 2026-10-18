import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/src/project_scanner.dart';
import 'package:test/test.dart';

/// Una raíz temporal canónica, nueva en cada prueba.
final class ScanSandbox {
  late Directory root;

  void register() {
    setUp(() async {
      final created = await Directory.systemTemp.createTemp('shipflow-scan-');
      root = Directory(created.resolveSymbolicLinksSync());
    });
    tearDown(() async {
      await Process.run('chmod', ['-R', 'u+rwx', root.path]);
      await root.delete(recursive: true);
    });
  }

  /// Crea [relative] bajo la raíz con [content], y sus directorios.
  File place(String relative, [String content = 'name: x\n']) =>
      File('${root.path}/$relative')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);

  Directory directory(String relative) =>
      Directory('${root.path}/$relative')..createSync(recursive: true);
}

List<String> sourcePaths(ScanResult result) => [
  for (final source in result.sources) source.path,
];

/// Cada limitación como `código:ruta:bloqueante`.
List<String> limitationsOf(ScanResult result) => [
  for (final RecognitionLimitation(:code, :path, :blocking)
      in result.limitations)
    '$code:$path:$blocking',
];
