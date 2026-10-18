import 'dart:io';

import 'package:cli/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await emitCliResponse(
    evaluateCli(arguments, version: buildVersion),
    standardOut: stdout,
    standardError: stderr,
  );
}
