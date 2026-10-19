import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
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

/// Cada omisión como `ruta:regla:tipos de su evidencia`.
List<String> omissionsOf(ScanResult result) => [
  for (final o in result.omissions)
    '${o.path}:${o.rule.toWireName()}:${o.evidence.map((e) => e.kind).join(',')}',
];

/// Cada fuente candidata como `ruta:tipo:motivo`.
List<String> contextOf(ScanResult result) => [
  for (final s in result.contextSources)
    '${s.path}:${s.entityType.toWireName()}:${s.reason.toWireName()}',
];

/// Un listado que anota qué directorios se pidieron, relativos a [root].
final class ListingSpy {
  ListingSpy(this.root);

  final Directory root;
  final listed = <String>[];

  Stream<FileSystemEntity> call(Directory directory) {
    final path = directory.path;
    listed.add(path == root.path ? '.' : path.substring(root.path.length + 1));
    return directory.list(followLinks: false);
  }
}

/// El catálogo de fuentes candidatas que la CLI entrega al plugin.
const candidateCatalogue = [
  ContextSourceRule(
    relativePath: 'README.md',
    kind: ContextSourceKind.documentation,
    expectsDirectory: false,
  ),
  ContextSourceRule(
    relativePath: 'analysis_options.yaml',
    kind: ContextSourceKind.analysisConfiguration,
    expectsDirectory: false,
  ),
  ContextSourceRule(
    relativePath: 'Makefile',
    kind: ContextSourceKind.taskConfiguration,
    expectsDirectory: false,
  ),
  ContextSourceRule(
    relativePath: '.gitlab-ci.yml',
    kind: ContextSourceKind.ciConfiguration,
    expectsDirectory: false,
  ),
  ContextSourceRule(
    relativePath: 'docs',
    kind: ContextSourceKind.documentation,
    expectsDirectory: true,
  ),
  ContextSourceRule(
    relativePath: '.github/workflows',
    kind: ContextSourceKind.ciConfiguration,
    expectsDirectory: true,
  ),
  ContextSourceRule(
    relativePath: 'AGENTS.md',
    kind: ContextSourceKind.instructions,
    expectsDirectory: false,
  ),
  ContextSourceRule(
    relativePath: 'NOTES.md',
    kind: ContextSourceKind.instructions,
    expectsDirectory: false,
  ),
];
