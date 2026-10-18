import 'dart:io';

import 'src/promotion.dart';

const _usage =
    'uso: dart run packages/cli/tool/promote.dart --artifact <ruta> '
    '--sha256 <hex> --version <semver> --bin-dir <directorio>';

Future<void> main(List<String> arguments) async {
  exitCode = await runPromote(
    arguments,
    standardOut: stdout,
    standardError: stderr,
  );
}

Future<int> runPromote(
  List<String> arguments, {
  required IOSink standardOut,
  required IOSink standardError,
}) async {
  final options = _parse(arguments);
  if (options == null) {
    standardError.writeln(
      'promote: se requieren exactamente --artifact, --sha256, --version y '
      '--bin-dir.\n$_usage',
    );
    return 64;
  }
  final binDirectory = Directory(options['--bin-dir']!);
  try {
    await promote(
      PromotionRequest(
        artifact: File(options['--artifact']!),
        expectedSha256: options['--sha256']!,
        expectedVersion: options['--version']!,
        binDirectory: binDirectory,
      ),
    );
  } on PromotionException catch (error) {
    standardError.writeln('promote: ${error.message}');
    return 1;
  }
  standardOut.writeln(
    'shipflow ${options['--version']} promovido en '
    '${binDirectory.absolute.path}/shipflow y verificado.',
  );
  return 0;
}

/// Las cuatro opciones, cada una una vez con su valor; otra forma es inválida.
Map<String, String>? _parse(List<String> arguments) {
  const names = {'--artifact', '--sha256', '--version', '--bin-dir'};
  if (arguments.length != names.length * 2) return null;
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    final name = arguments[i];
    if (!names.contains(name) || options.containsKey(name)) return null;
    options[name] = arguments[i + 1];
  }
  return options;
}
