import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/checksum.dart';
import '../../tool/src/promotion.dart';

const installedName = 'shipflow';
const candidateName = '.shipflow.candidate';
const previousName = '.shipflow.previous';
const manifestName = '.shipflow.promote.json';
const lockName = '.shipflow.promote.lock';

Future<void> chmod(String mode, String path) async {
  final result = await Process.run('chmod', [mode, path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

Future<String> sha(File file) async => (await computeSha256(file)).sha256;

Future<String?> answer(String path) async {
  final result = await Process.run(
    path,
    ['--version'],
    environment: const {},
    includeParentEnvironment: false,
  );
  return result.exitCode == 0 ? result.stdout as String : null;
}

/// Contenido, tipo y modo de cada entrada: cualquier escritura lo cambia.
Future<Map<String, String>> state(Directory directory) async {
  final entries = <String, String>{};
  for (final entity in directory.listSync(followLinks: false)) {
    final name = entity.path.substring(directory.path.length + 1);
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    entries[name] = switch (type) {
      FileSystemEntityType.link => 'enlace:${Link(entity.path).targetSync()}',
      FileSystemEntityType.file =>
        'archivo:${entity.statSync().modeString()}:'
            '${base64.encode(File(entity.path).readAsBytesSync())}',
      _ => 'otro:$type',
    };
  }
  return entries;
}

/// Un bin-dir y un directorio de artefactos nuevos para cada test, dentro de
/// un sandbox que se borra al terminar.
final class PromotionSandbox {
  late Directory sandbox;
  late Directory binDir;
  late Directory artifacts;

  var counter = 0;

  void register() {
    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('shipflow-promocion-');
      binDir = await Directory('${sandbox.path}/bin').create();
      artifacts = await Directory('${sandbox.path}/artefactos').create();
    });

    tearDown(() async {
      await Process.run('chmod', ['-R', 'u+w', sandbox.path]);
      await sandbox.delete(recursive: true);
    });
  }

  /// Un ejecutable que responde `shipflow <version>`. Con
  /// [failsWhenInstalled] deja de responder cuando se llama `shipflow`, que
  /// es la verificación posterior al reemplazo.
  Future<File> executable(
    String version, {
    bool failsWhenInstalled = false,
    bool hangsWhenInstalled = false,
    String salt = '',
  }) async {
    final file = File('${artifacts.path}/candidato-${counter++}');
    file.writeAsStringSync(
      '#!/bin/sh\n'
      '# $salt\n'
      '${failsWhenInstalled ? 'case "\${0##*/}" in shipflow) exit 1;; esac\n' : ''}'
      '${hangsWhenInstalled ? 'case "\${0##*/}" in shipflow) exec sleep 60;; esac\n' : ''}'
      "printf 'shipflow %s\\n' '$version'\n",
    );
    await chmod('0755', file.path);
    return file;
  }

  Future<File> install(File source) async {
    final installed = await source.copy('${binDir.path}/$installedName');
    await chmod('0755', installed.path);
    return installed;
  }

  Future<PromotionRequest> request(
    File artifact,
    String version, {
    String? sha256,
  }) async => PromotionRequest(
    artifact: artifact,
    expectedSha256: sha256 ?? await sha(artifact),
    expectedVersion: version,
    binDirectory: binDir,
  );

  Future<void> expectClean(String version) async {
    expect(binDir.listSync().map((e) => e.path.split('/').last).toSet(), {
      installedName,
      lockName,
    });
    expect(File('${binDir.path}/$lockName').lengthSync(), 0);
    expect(
      await answer('${binDir.path}/$installedName'),
      'shipflow $version\n',
    );
  }

  void writeManifest(Map<String, Object> fields) {
    File(
      '${binDir.path}/$manifestName',
    ).writeAsStringSync(jsonEncode({'schemaVersion': 1, ...fields}));
  }
}

Matcher rejected(String fragment) => throwsA(
  isA<PromotionException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);
