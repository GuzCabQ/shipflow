import 'dart:io';

import 'package:vcs/vcs.dart';

import 'cli_command.dart';
import 'context/context_prompt.dart';
import 'cli_response.dart';
import 'internal_failure.dart';
import 'recognition_runner.dart';

/// Lo que el proceso público responde: igual que [runCli], salvo que un
/// fallo inesperado se vuelve la respuesta genérica de código 70, sin la
/// excepción, la traza ni rutas. Es el único lugar que lo traduce.
Future<CliResponse> runCliAtProcessBoundary(
  List<String> arguments, {
  required String version,
  required Directory workingDirectory,
  required RecognitionContributor recognizeProject,
  String? logicalRootHint,
  GitContextAdapter? git,
  ContextPromptIO? prompt,
}) async {
  CliCommand? command;
  try {
    command = parseCliCommand(arguments);
    return await runCommand(
      command,
      version: version,
      workingDirectory: workingDirectory,
      recognizeProject: recognizeProject,
      logicalRootHint: logicalRootHint,
      git: git,
      prompt: prompt,
    );
  } on Object {
    return internalFailure(json: command?.json ?? false);
  }
}
