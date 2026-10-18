import 'dart:io';

import 'src/options.dart';
import 'src/promotion.dart';

const _usage =
    'uso: dart run packages/cli/tool/promote.dart --artifact <ruta> '
    '--sha256 <hex> --version <semver> --bin-dir <directorio>';
const _names = {'--artifact', '--sha256', '--version', '--bin-dir'};

const _exitPromoted = 0;
const _exitRejected = 1;
const _exitUsage = 64;

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
  final options = parseNamedOptions(arguments, _names);
  if (options == null || options.length != _names.length) {
    standardError.writeln(
      'promote: se requieren exactamente --artifact, --sha256, --version y '
      '--bin-dir.\n$_usage',
    );
    return _exitUsage;
  }
  final request = _requestFrom(options);
  try {
    await promote(request);
  } on PromotionException catch (error) {
    standardError.writeln('promote: ${error.message}');
    return _exitRejected;
  }
  standardOut.writeln(
    'shipflow ${request.expectedVersion} promovido en '
    '${request.binDirectory.absolute.path}/shipflow y verificado.',
  );
  return _exitPromoted;
}

PromotionRequest _requestFrom(Map<String, String> options) => PromotionRequest(
  artifact: File(options['--artifact']!),
  expectedSha256: options['--sha256']!,
  expectedVersion: options['--version']!,
  binDirectory: Directory(options['--bin-dir']!),
);
