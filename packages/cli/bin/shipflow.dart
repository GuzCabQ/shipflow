import 'dart:io';

import 'package:cli/cli.dart';
import 'package:plugin_dart/plugin_dart.dart';

/// El catálogo finito de fuentes candidatas, en cada raíz de unidad. Sólo se
/// consultan sus metadatos; los nombres de proveedores viven sólo aquí.
const _contextSources = [
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
    relativePath: 'CLAUDE.md',
    kind: ContextSourceKind.instructions,
    expectsDirectory: false,
  ),
];

Future<void> main(List<String> arguments) async {
  exitCode = await emitCliResponse(
    await runCliAtProcessBoundary(
      arguments,
      version: buildVersion,
      workingDirectory: currentWorkingDirectory(),
      recognizeProject: (root, {required reportLimits}) => recognizeDartProject(
        root,
        reportLimits: reportLimits,
        contextSources: _contextSources,
      ),
      logicalRootHint: Platform.environment['PWD'],
    ),
    standardOut: stdout,
    standardError: stderr,
  );
}
