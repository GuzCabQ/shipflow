import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'src/checksum.dart';
import 'src/semver.dart';

const _usage =
    'uso: dart run packages/cli/tool/build_release.dart '
    '--version <semver> --output <ruta>';

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
  final options = _parse(arguments);
  final version = options['--version'];
  final output = options['--output'];
  if (options.isEmpty || version == null || output == null) {
    standardError.writeln(
      'build_release: se requieren exactamente --version y --output.\n$_usage',
    );
    return 64;
  }
  if (!isValidSemVer(version)) {
    standardError.writeln(
      'build_release: «$version» no es SemVer 2.0; no se compiló nada.',
    );
    return 64;
  }
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
    return 0;
  } on ReleaseBuildException catch (error) {
    standardError.writeln('build_release: ${error.message}');
    return 1;
  }
}

/// Cada opción aparece una vez con su valor; cualquier otra forma es inválida.
Map<String, String> _parse(List<String> arguments) {
  const names = {'--version', '--output'};
  final options = <String, String>{};
  if (arguments.length.isOdd) return const {};
  for (var i = 0; i < arguments.length; i += 2) {
    final name = arguments[i];
    if (!names.contains(name) || options.containsKey(name)) return const {};
    options[name] = arguments[i + 1];
  }
  return options;
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
  if (!isValidSemVer(version)) {
    throw ReleaseBuildException('«$version» no es SemVer 2.0.');
  }
  final abi = hostAbi ?? Abi.current();
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
      'el directorio que contiene --output no existe; no se compiló nada.',
    );
  }
  final tool = checksumTool ?? _hostChecksumTool();
  final source = entrypoint ?? await _publicEntrypoint();
  final staging = await output.absolute.parent.createTemp('.shipflow-release-');
  try {
    final name = 'shipflow-$version-$platform';
    final artifact = File('${staging.path}/$name');
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
    final ran = await Process.run(
      artifact.path,
      ['--version'],
      workingDirectory: staging.path,
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
    final ChecksumEvidence evidence;
    try {
      evidence = await computeSha256With(artifact, tool);
    } on ChecksumException catch (error) {
      throw ReleaseBuildException(error.message);
    }
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
  } on Object catch (error) {
    if (staging.existsSync()) await staging.delete(recursive: true);
    if (error is FileSystemException || error is ProcessException) {
      throw ReleaseBuildException('la build no terminó: $error');
    }
    rethrow;
  }
}

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
