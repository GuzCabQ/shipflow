import 'dart:io';

import 'package:vcs/vcs.dart';

import 'assessment/assessment_cli.dart';
import 'basis/basis_cli.dart';
import 'cli_application.dart';
import 'command/cli_command.dart';
import 'command/cli_parser.dart';
import 'cli_response.dart';
import 'context/context_cli.dart';
import 'context/context_prompt.dart';
import 'recognition_presenter.dart';
import 'recognition_runner.dart';

/// Responde [arguments]. Un fallo de programación sale tal cual, con su
/// objeto y su traza: traducirlo es trabajo de la frontera del proceso.
///
/// [logicalRootHint] es la ruta lógica que el entorno dice tener, como
/// `PWD`; sólo se muestra si resuelve a la misma carpeta real.
Future<CliResponse> runCli(
  List<String> arguments, {
  required String version,
  required Directory workingDirectory,
  required RecognitionContributor recognizeProject,
  String? logicalRootHint,
  GitContextAdapter? git,
  ContextPromptIO? prompt,
  AssessmentPlugin? assessment,
}) => runCommand(
  parseCliCommand(arguments),
  version: version,
  workingDirectory: workingDirectory,
  recognizeProject: recognizeProject,
  logicalRootHint: logicalRootHint,
  git: git,
  prompt: prompt,
  assessment: assessment,
);

Future<CliResponse> runCommand(
  CliCommand command, {
  required String version,
  required Directory workingDirectory,
  required RecognitionContributor recognizeProject,
  String? logicalRootHint,
  GitContextAdapter? git,
  ContextPromptIO? prompt,
  AssessmentPlugin? assessment,
}) async => switch (command) {
  final StaticCommand static => respondStatically(static, version: version),
  final RunContext context => await runContextCommand(
    context,
    version: version,
    workingDirectory: workingDirectory,
    recognizeProject: recognizeProject,
    logicalRootHint: logicalRootHint,
    git: git,
    prompt: prompt,
  ),
  RunAssessment() || RunBootstrap() => await _stateCommand(
    command,
    version,
    workingDirectory,
    recognizeProject,
    (logicalRootHint: logicalRootHint, git: git, prompt: prompt),
    assessment,
  ),
  final RunInitDryRun dryRun => await _dryRun(
    dryRun,
    workingDirectory,
    recognizeProject,
    logicalRootHint,
  ),
};

/// Los comandos con estado propio fuera del contexto V2: assess y
/// bootstrap.
Future<CliResponse> _stateCommand(
  CliCommand command,
  String version,
  Directory workingDirectory,
  RecognitionContributor recognizeProject,
  ({String? logicalRootHint, GitContextAdapter? git, ContextPromptIO? prompt})
  optional,
  AssessmentPlugin? assessment,
) => switch (command) {
  final RunBootstrap run => runBootstrapCommand(
    run,
    version: version,
    workingDirectory: workingDirectory,
    prompt: optional.prompt,
  ),
  _ => runAssessmentCommand(
    command as RunAssessment,
    version: version,
    workingDirectory: workingDirectory,
    recognizeProject: recognizeProject,
    plugin: assessment,
    logicalRootHint: optional.logicalRootHint,
    git: optional.git,
  ),
};

/// `init --dry-run`: reconoce y presenta, sin escribir.
Future<CliResponse> _dryRun(
  RunInitDryRun command,
  Directory workingDirectory,
  RecognitionContributor recognizeProject,
  String? logicalRootHint,
) async => presentRecognition(
  await recognizeRoot(
    workingDirectory,
    recognizeProject,
    logicalRootHint: logicalRootHint,
    budgetProfile: command.budgetProfile,
  ),
  json: command.json,
  budgetProfile: command.budgetProfile,
);
