import 'dart:io';

import 'package:cli/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await emitCliResponse(
    switch (parseCliCommand(arguments)) {
      final StaticCommand command => respondStatically(
        command,
        version: buildVersion,
      ),
      RunInitDryRun() => const CliResponse(
        exitCode: 70,
        channel: CliOutputChannel.stderr,
        payload: 'shipflow: no se pudo completar la operación.\n',
      ),
    },
    standardOut: stdout,
    standardError: stderr,
  );
}
