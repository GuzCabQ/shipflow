import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'src/checksum.dart';
import 'src/options.dart';
import 'src/semver.dart';

const _usage =
    'uso: dart run packages/cli/tool/build_release.dart '
    '--version <semver> --output <ruta>';
const _names = {'--version', '--output'};

const _exitBuilt = 0;
const _exitFailed = 1;
const _exitUsage = 64;

Future<void> main(List<String> arguments) async {
  exitCode = await runBuildRelease(
    arguments,
    standardOut: stdout,
    standardError: stderr,
  );
}

final class ReleaseBuildException implements Exception {
  const ReleaseBuildException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ReleaseBuild {
  const ReleaseBuild({
    required this.artifact,
    required this.checksums,
    required this.platform,
    required this.evidence,
  });

  final File artifact;
  final File checksums;
  final String platform;
  final ChecksumEvidence evidence;
}

/// El nombre de release de cada plataforma declarada. Las demás no tienen
/// nombre: producir un artefacto que no se puede ejecutar acá no demuestra
/// soporte.
String? releasePlatformFor(Abi abi) => switch (abi) {
  Abi.macosArm64 => 'macos-arm64',
  Abi.linuxX64 => 'linux-x64',
  _ => null,
};

Future<int> runBuildRelease(
  List<String> arguments, {
  required IOSink standardOut,
  required IOSink standardError,
}) async {
  final request = _readRequest(arguments, standardError);
  if (request == null) return _exitUsage;
  final (:version, :output) = request;
  try {
    final build = await buildRelease(
      version: version,
      output: Directory(output),
    );
    standardOut.writeln(
      'shipflow $version construido y ejecutado nativamente en '
      '${build.platform}.\n'
      'artefacto:  ${build.artifact.path}\n'
      'sha256:     ${build.evidence.sha256} (${build.evidence.tool})\n'
      'SHA256SUMS: ${build.checksums.path}',
    );
    return _exitBuilt;
  } on ReleaseBuildException catch (error) {
    standardError.writeln('build_release: ${error.message}');
    return _exitFailed;
  }
}

/// Las dos opciones, o null después de explicar en [standardError] por qué
/// no alcanzan.
({String version, String output})? _readRequest(
  List<String> arguments,
  IOSink standardError,
) {
  final options = parseNamedOptions(arguments, _names) ?? const {};
  final version = options['--version'];
  final output = options['--output'];
  if (options.isEmpty || version == null || output == null) {
    standardError.writeln(
      'build_release: se requieren exactamente --version y --output.\n$_usage',
    );
    return null;
  }
  if (!isValidSemVer(version)) {
    standardError.writeln(
      'build_release: «$version» no es SemVer 2.0; no se compiló nada.',
    );
    return null;
  }
  return (version: version, output: output);
}

/// Compila, ejecuta y digiere el artefacto en un directorio de trabajo
/// hermano de [output], que sólo se vuelve [output] si todo lo anterior
/// resultó: un fallo nunca deja un candidato aceptable.
Future<ReleaseBuild> buildRelease({
  required String version,
  required Directory output,
  File? entrypoint,
  Abi? hostAbi,
  ChecksumTool? checksumTool,
}) async {
  final platform = _requireBuildable(version, output, hostAbi ?? Abi.current());
  final tool = checksumTool ?? _hostChecksumTool();
  final source = entrypoint ?? await _publicEntrypoint();
  final staging = await _createStaging(output);
  try {
    return await _assemble(staging, output, version, platform, source, tool);
  } on Object catch (error) {
    final failure = _failure(error);
    if (failure == null) rethrow;
    await _discard(staging, failure);
  }
}

/// Compila, ejecuta y digiere en [staging], y lo publica como [output].
Future<ReleaseBuild> _assemble(
  Directory staging,
  Directory output,
  String version,
  String platform,
  File source,
  ChecksumTool tool,
) async {
  final name = 'shipflow-$version-$platform';
  final artifact = File('${staging.path}/$name');
  await _compile(source, artifact, version);
  await _requireAnswer(artifact, version);
  final evidence = await _digest(artifact, tool);
  File(
    '${staging.path}/SHA256SUMS',
  ).writeAsStringSync('${evidence.sha256}  $name\n', flush: true);
  final published = await staging.rename(output.path);
  return ReleaseBuild(
    artifact: File('${published.path}/$name'),
    checksums: File('${published.path}/SHA256SUMS'),
    platform: platform,
    evidence: evidence,
  );
}

/// El nombre de release de esta plataforma, una vez que nada impide compilar.
String _requireBuildable(String version, Directory output, Abi abi) {
  if (!isValidSemVer(version)) {
    throw ReleaseBuildException('«$version» no es SemVer 2.0.');
  }
  final platform = releasePlatformFor(abi);
  if (platform == null) {
    throw ReleaseBuildException(
      '$abi no es una plataforma declarada; no se produce artefacto.',
    );
  }
  if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw ReleaseBuildException('${output.path} ya existe; no se reemplaza.');
  }
  if (!output.absolute.parent.existsSync()) {
    throw const ReleaseBuildException(
      'el directorio que contiene --output no existe o no es un directorio; '
      'no se compiló nada.',
    );
  }
  return platform;
}

Future<Directory> _createStaging(Directory output) async {
  try {
    return await output.absolute.parent.createTemp('.shipflow-release-');
  } on FileSystemException catch (error) {
    throw ReleaseBuildException(
      'no se pudo crear el directorio de trabajo junto a --output '
      '(${_reason(error)}); no se compiló nada.',
    );
  }
}

Future<void> _compile(File source, File artifact, String version) async {
  final compiled = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '-DSHIPFLOW_VERSION=$version',
    '-o',
    artifact.path,
    source.path,
  ]);
  if (compiled.exitCode != 0 || !artifact.existsSync()) {
    throw ReleaseBuildException(
      '${source.path} no compiló:\n${compiled.stdout}${compiled.stderr}',
    );
  }
}

/// Ejecuta el artefacto recién compilado sin entorno heredado.
Future<void> _requireAnswer(File artifact, String version) async {
  final ran = await Process.run(
    artifact.path,
    ['--version'],
    workingDirectory: artifact.parent.path,
    environment: const {},
    includeParentEnvironment: false,
  );
  final expected = 'shipflow $version\n';
  if (ran.exitCode != 0 || ran.stdout != expected || ran.stderr != '') {
    throw ReleaseBuildException(
      'el artefacto no respondió «${expected.trim()}» a --version: '
      'código ${ran.exitCode}, stdout «${ran.stdout}», '
      'stderr «${ran.stderr}».',
    );
  }
}

Future<ChecksumEvidence> _digest(File artifact, ChecksumTool tool) async {
  try {
    return await computeSha256With(artifact, tool);
  } on ChecksumException catch (error) {
    throw ReleaseBuildException(error.message);
  }
}

/// El fallo de la build como frase, o null si no es uno de los previstos.
String? _failure(Object error) => switch (error) {
  ReleaseBuildException(:final message) => message,
  FileSystemException() || ProcessException() =>
    'la build no terminó (${_reason(error)}); no hay candidato.',
  _ => null,
};

/// Borra el directorio de trabajo y falla con [failure]; si no se puede
/// borrar, lo dice para que nadie lo tome por un candidato.
Future<Never> _discard(Directory staging, String failure) async {
  try {
    if (staging.existsSync()) await staging.delete(recursive: true);
  } on FileSystemException catch (cleanup) {
    throw ReleaseBuildException(
      '$failure\nAdemás, no se pudo borrar el directorio de trabajo '
      '.shipflow-release-* junto a --output (${_reason(cleanup)}); no es un '
      'candidato y hay que borrarlo a mano.',
    );
  }
  throw ReleaseBuildException(failure);
}

/// El motivo del sistema operativo, sin la ruta ni la traza de la excepción.
String _reason(Object error) => switch (error) {
  FileSystemException(:final osError?) => osError.message,
  FileSystemException(:final message) => message,
  ProcessException(:final message) => message,
  _ => 'error inesperado',
};

ChecksumTool _hostChecksumTool() {
  try {
    return checksumToolFor(Platform.operatingSystem);
  } on ChecksumException catch (error) {
    throw ReleaseBuildException(error.message);
  }
}

Future<File> _publicEntrypoint() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:cli/cli.dart'),
  );
  return File('${File.fromUri(barrel!).parent.parent.path}/bin/shipflow.dart');
}
