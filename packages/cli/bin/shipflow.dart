import 'dart:io';

import 'package:cli/cli.dart';
import 'package:plugin_dart/plugin_dart.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await emitCliResponse(
    await runCliAtProcessBoundary(
      arguments,
      version: buildVersion,
      workingDirectory: currentWorkingDirectory(),
      recognizeProject: recognizeDartProject,
    ),
    standardOut: stdout,
    standardError: stderr,
  );
}
