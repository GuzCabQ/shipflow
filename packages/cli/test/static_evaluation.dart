import 'package:cli/cli.dart';
import 'package:test/test.dart';

/// La respuesta que el CLI da sin mirar el proyecto. Falla la prueba si los
/// argumentos piden reconocerlo.
CliResponse evaluate(List<String> arguments, {required String version}) =>
    switch (parseCliCommand(arguments)) {
      final StaticCommand command => respondStatically(
        command,
        version: version,
      ),
      RunInitDryRun() => fail('$arguments pide reconocer el proyecto'),
    };
