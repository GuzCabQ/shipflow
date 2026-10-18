@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../../tool/build_release.dart';
import '../../tool/promote.dart';
import '../../tool/src/checksum.dart';
import '../../tool/src/promotion.dart';

const installedName = 'shipflow';
const candidateName = '.shipflow.candidate';
const previousName = '.shipflow.previous';
const manifestName = '.shipflow.promote.json';
const lockName = '.shipflow.promote.lock';

final class _Collector implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(bytes.addAll);

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

Future<Directory> packageRoot() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:cli/cli.dart'),
  );
  return File.fromUri(barrel!).parent.parent;
}

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

void main() {
  late Directory sandbox;
  late Directory binDir;
  late Directory artifacts;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('shipflow-promocion-');
    binDir = await Directory('${sandbox.path}/bin').create();
    artifacts = await Directory('${sandbox.path}/artefactos').create();
  });

  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+w', sandbox.path]);
    await sandbox.delete(recursive: true);
  });

  var counter = 0;

  /// Un ejecutable que responde `shipflow <version>`. Con
  /// [failsWhenInstalled] deja de responder cuando se llama `shipflow`, que
  /// es la verificación posterior al reemplazo.
  Future<File> executable(
    String version, {
    bool failsWhenInstalled = false,
    String salt = '',
  }) async {
    final file = File('${artifacts.path}/candidato-${counter++}');
    file.writeAsStringSync(
      '#!/bin/sh\n'
      '# $salt\n'
      '${failsWhenInstalled ? 'case "\${0##*/}" in shipflow) exit 1;; esac\n' : ''}'
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

  Matcher rejected(String fragment) => throwsA(
    isA<PromotionException>().having(
      (e) => e.message,
      'message',
      contains(fragment),
    ),
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

  group('promoción', () {
    test('primera instalación', () async {
      final artifact = await executable('1.0.0');
      await promote(await request(artifact, '1.0.0'));
      await expectClean('1.0.0');
    });

    test('actualización conserva sólo el instalado y el lock vacío', () async {
      await install(await executable('1.0.0'));
      await promote(await request(await executable('1.1.0'), '1.1.0'));
      await expectClean('1.1.0');
    });

    test('promover lo mismo que ya está instalado no cambia nada', () async {
      final artifact = await executable('1.0.0');
      await install(artifact);
      final installed = await sha(File('${binDir.path}/$installedName'));
      await promote(await request(artifact, '1.0.0'));
      expect(await sha(File('${binDir.path}/$installedName')), installed);
      await expectClean('1.0.0');
    });

    test('promueve un shipflow compilado de verdad', () async {
      final release = await buildRelease(
        version: '0.0.0-dev.7+gpromocion',
        output: Directory('${sandbox.path}/release'),
      );
      await promote(
        PromotionRequest(
          artifact: release.artifact,
          expectedSha256: release.evidence.sha256,
          expectedVersion: '0.0.0-dev.7+gpromocion',
          binDirectory: binDir,
        ),
      );
      await expectClean('0.0.0-dev.7+gpromocion');
    });
  });

  group('verificación previa: el destino no se toca', () {
    late File installed;
    late Map<String, String> before;

    setUp(() async {
      installed = await install(await executable('1.0.0'));
      before = await state(binDir);
    });

    // V0-S15
    test('un digest que no coincide se rechaza', () async {
      final artifact = await executable('2.0.0');
      await expectLater(
        promote(await request(artifact, '2.0.0', sha256: '0' * 64)),
        rejected('SHA-256'),
      );
      expect(await state(binDir), before);
    });

    // V0-S32
    test('un candidato que informa otra versión se rechaza', () async {
      await expectLater(
        promote(await request(await executable('2.0.1'), '2.0.0')),
        rejected('2.0.0'),
      );
      expect(await state(binDir), before);
    });

    test('un candidato que no responde se rechaza', () async {
      final mute = File('${artifacts.path}/mudo')
        ..writeAsStringSync('#!/bin/sh\nexit 1\n');
      await chmod('0755', mute.path);
      await expectLater(
        promote(await request(mute, '2.0.0')),
        rejected('2.0.0'),
      );
      expect(await state(binDir), before);
    });

    // V0-S33
    test('la misma versión con bytes distintos se rechaza', () async {
      await expectLater(
        promote(
          await request(await executable('1.0.0', salt: 'otro'), '1.0.0'),
        ),
        rejected('misma versión'),
      );
      expect((await state(binDir))..remove(lockName), before);
      expect(await answer(installed.path), 'shipflow 1.0.0\n');
    });

    test('una versión esperada que no es SemVer se rechaza', () async {
      await expectLater(
        promote(await request(await executable('v2.0.0'), 'v2.0.0')),
        rejected('SemVer'),
      );
      expect(await state(binDir), before);
    });

    test('un digest esperado mal formado se rechaza', () async {
      await expectLater(
        promote(
          await request(await executable('2.0.0'), '2.0.0', sha256: 'ab'),
        ),
        rejected('SHA-256'),
      );
      expect(await state(binDir), before);
    });

    test('un artefacto inexistente se rechaza', () async {
      await expectLater(
        promote(
          PromotionRequest(
            artifact: File('${artifacts.path}/no-existe'),
            expectedSha256: '0' * 64,
            expectedVersion: '2.0.0',
            binDirectory: binDir,
          ),
        ),
        rejected('no-existe'),
      );
      expect(await state(binDir), before);
    });

    test('un bin-dir inexistente no se crea', () async {
      final missing = Directory('${sandbox.path}/no-existe');
      final artifact = await executable('2.0.0');
      await expectLater(
        promote(
          PromotionRequest(
            artifact: artifact,
            expectedSha256: await sha(artifact),
            expectedVersion: '2.0.0',
            binDirectory: missing,
          ),
        ),
        rejected('no-existe'),
      );
      expect(missing.existsSync(), isFalse);
    });

    test('un bin-dir sin escritura deja la instalación intacta', () async {
      await chmod('0555', binDir.path);
      await expectLater(
        promote(await request(await executable('2.0.0'), '2.0.0')),
        throwsA(isA<PromotionException>()),
      );
      expect(await state(binDir), before);
    });

    test('con el lock ya creado y sin escritura tampoco cambia', () async {
      File('${binDir.path}/$lockName').createSync();
      before = await state(binDir);
      await chmod('0555', binDir.path);
      await expectLater(
        promote(await request(await executable('2.0.0'), '2.0.0')),
        throwsA(isA<PromotionException>()),
      );
      expect(await state(binDir), before);
    });
  });

  // V0-S36
  group('enlaces simbólicos', () {
    test('un artefacto enlace se rechaza sin seguirlo', () async {
      final target = await executable('2.0.0');
      final link = Link('${artifacts.path}/enlace')..createSync(target.path);
      await expectLater(
        promote(
          PromotionRequest(
            artifact: File(link.path),
            expectedSha256: await sha(target),
            expectedVersion: '2.0.0',
            binDirectory: binDir,
          ),
        ),
        rejected('enlace'),
      );
      expect(binDir.listSync(), isEmpty);
    });

    test('un bin-dir enlace se rechaza', () async {
      final link = Link('${sandbox.path}/bin-enlace')..createSync(binDir.path);
      final artifact = await executable('2.0.0');
      await expectLater(
        promote(
          PromotionRequest(
            artifact: artifact,
            expectedSha256: await sha(artifact),
            expectedVersion: '2.0.0',
            binDirectory: Directory(link.path),
          ),
        ),
        rejected('enlace'),
      );
      expect(binDir.listSync(), isEmpty);
    });

    for (final name in [installedName, lockName, candidateName, manifestName]) {
      test('un $name enlace se rechaza sin seguirlo', () async {
        final target = File('${sandbox.path}/objetivo')
          ..writeAsStringSync('no tocar');
        Link('${binDir.path}/$name').createSync(target.path);
        final before = await state(binDir);
        await expectLater(
          promote(await request(await executable('2.0.0'), '2.0.0')),
          rejected('enlace'),
        );
        expect(await state(binDir), before);
        expect(target.readAsStringSync(), 'no tocar');
      });
    }
  });

  // V0-S27, V0-S37
  group('verificación posterior al reemplazo', () {
    test('si falla, restaura el anterior y éste vuelve a responder', () async {
      final old = await install(await executable('1.0.0'));
      final oldBytes = old.readAsBytesSync();
      await expectLater(
        promote(
          await request(
            await executable('2.0.0', failsWhenInstalled: true),
            '2.0.0',
          ),
        ),
        rejected('restaur'),
      );
      expect(File('${binDir.path}/$installedName').readAsBytesSync(), oldBytes);
      await expectClean('1.0.0');
    });

    test('en una primera instalación no deja un ejecutable roto', () async {
      await expectLater(
        promote(
          await request(
            await executable('2.0.0', failsWhenInstalled: true),
            '2.0.0',
          ),
        ),
        throwsA(isA<PromotionException>()),
      );
      expect(binDir.listSync().map((e) => e.path.split('/').last), [lockName]);
    });
  });

  // V0-S34
  group('reconciliación de una promoción interrumpida', () {
    late File old;
    late File fresh;
    late String oldSha;
    late String freshSha;

    setUp(() async {
      old = await executable('1.0.0');
      fresh = await executable('2.0.0');
      oldSha = await sha(old);
      freshSha = await sha(fresh);
      File('${binDir.path}/$lockName').createSync();
    });

    Map<String, Object> manifest(String phase, {bool firstInstall = false}) => {
      'phase': phase,
      'candidateVersion': '2.0.0',
      'candidateSha256': freshSha,
      if (!firstInstall) ...{
        'previousVersion': '1.0.0',
        'previousSha256': oldSha,
      },
    };

    Future<void> place(File source, String name) async {
      final placed = await source.copy('${binDir.path}/$name');
      await chmod('0755', placed.path);
    }

    test('interrumpida al preparar el candidato', () async {
      await place(old, installedName);
      File('${binDir.path}/$candidateName').writeAsStringSync('a medias');
      writeManifest(manifest('staging'));
      await promote(await request(old, '1.0.0'));
      await expectClean('1.0.0');
    });

    test('interrumpida antes de respaldar el instalado', () async {
      await place(old, installedName);
      await place(fresh, candidateName);
      writeManifest(manifest('swapping'));
      await promote(await request(old, '1.0.0'));
      await expectClean('1.0.0');
    });

    test('interrumpida entre el respaldo y el reemplazo', () async {
      await place(old, previousName);
      await place(fresh, candidateName);
      writeManifest(manifest('swapping'));
      await promote(await request(old, '1.0.0'));
      await expectClean('1.0.0');
    });

    test('interrumpida después del reemplazo y antes de verificar', () async {
      await place(old, previousName);
      await place(fresh, installedName);
      writeManifest(manifest('swapping'));
      await promote(await request(old, '1.0.0'));
      await expectClean('1.0.0');
    });

    test('interrumpida al limpiar una promoción ya verificada', () async {
      await place(old, previousName);
      await place(fresh, installedName);
      writeManifest(manifest('committing'));
      await promote(await request(fresh, '2.0.0'));
      await expectClean('2.0.0');
    });

    test('una primera instalación interrumpida no queda instalada', () async {
      await place(fresh, installedName);
      writeManifest(manifest('swapping', firstInstall: true));
      final third = await executable('3.0.0');
      await promote(await request(third, '3.0.0'));
      await expectClean('3.0.0');
    });

    test('la reconciliación ocurre antes de promover otro artefacto', () async {
      await place(old, previousName);
      await place(fresh, installedName);
      writeManifest(manifest('swapping'));
      await expectLater(
        promote(await request(await executable('1.0.0', salt: 'x'), '1.0.0')),
        rejected('misma versión'),
      );
      expect(await answer('${binDir.path}/$installedName'), 'shipflow 1.0.0\n');
      expect(File('${binDir.path}/$manifestName').existsSync(), isFalse);
    });

    for (final (name, setup) in <(String, Future<void> Function())>[
      (
        'residuos sin manifiesto',
        () async {
          await place(old, installedName);
          await place(fresh, candidateName);
        },
      ),
      (
        'un manifiesto ilegible',
        () async {
          await place(old, installedName);
          File('${binDir.path}/$manifestName').writeAsStringSync('{a medias');
        },
      ),
      (
        'un respaldo que no es el del manifiesto',
        () async {
          await place(fresh, previousName);
          await place(fresh, installedName);
          writeManifest(manifest('swapping'));
        },
      ),
    ]) {
      test('$name no se sobrescribe a ciegas', () async {
        await setup();
        final before = await state(binDir);
        await expectLater(
          promote(await request(await executable('3.0.0'), '3.0.0')),
          throwsA(isA<PromotionException>()),
        );
        expect(await state(binDir), before);
      });
    }
  });

  group('promote.dart', () {
    late String script;

    setUp(() async {
      script = '${(await packageRoot()).path}/tool/promote.dart';
    });

    Future<(int, String, String)> invoke(List<String> arguments) async {
      final out = _Collector();
      final err = _Collector();
      final code = await runPromote(
        arguments,
        standardOut: IOSink(out),
        standardError: IOSink(err),
      );
      return (code, out.text, err.text);
    }

    test('exige las cuatro entradas explícitas', () async {
      final artifact = await executable('1.0.0');
      final full = [
        '--artifact',
        artifact.path,
        '--sha256',
        await sha(artifact),
        '--version',
        '1.0.0',
        '--bin-dir',
        binDir.path,
      ];
      for (var i = 0; i < full.length; i += 2) {
        final (code, out, err) = await invoke([
          ...full.sublist(0, i),
          ...full.sublist(i + 2),
        ]);
        expect(code, 64, reason: full[i]);
        expect(out, isEmpty);
        expect(err, contains('--bin-dir'));
      }
      expect((await invoke([...full, '--force', 'x'])).$1, 64);
      expect((await invoke([...full, ...full.sublist(0, 2)])).$1, 64);
      expect(binDir.listSync(), isEmpty);
    });

    test('promueve por línea de comandos', () async {
      final artifact = await executable('1.0.0');
      final (code, out, err) = await invoke([
        '--artifact',
        artifact.path,
        '--sha256',
        await sha(artifact),
        '--version',
        '1.0.0',
        '--bin-dir',
        binDir.path,
      ]);
      expect(code, 0, reason: err);
      expect(out, contains('shipflow 1.0.0'));
      await expectClean('1.0.0');
    });

    test('un rechazo sale con código 1', () async {
      final artifact = await executable('1.0.0');
      final (code, out, err) = await invoke([
        '--artifact',
        artifact.path,
        '--sha256',
        '0' * 64,
        '--version',
        '1.0.0',
        '--bin-dir',
        binDir.path,
      ]);
      expect(code, 1);
      expect(out, isEmpty);
      expect(err, contains('SHA-256'));
    });

    // V0-S35
    test('otra promoción con el lock tomado no modifica nada', () async {
      await install(await executable('1.0.0'));
      File('${binDir.path}/$lockName').createSync();
      final artifact = await executable('2.0.0');
      // El lock es de proceso: leer su archivo desde acá lo liberaría, así
      // que el estado se toma antes de adquirirlo.
      final before = await state(binDir);
      final lock = await File(
        '${binDir.path}/$lockName',
      ).open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      try {
        final contender = await Process.run(Platform.resolvedExecutable, [
          'run',
          script,
          '--artifact',
          artifact.path,
          '--sha256',
          await sha(artifact),
          '--version',
          '2.0.0',
          '--bin-dir',
          binDir.path,
        ]).timeout(const Duration(minutes: 2));
        expect(contender.exitCode, 1, reason: '${contender.stderr}');
        expect(contender.stderr, contains('otra promoción'));
        expect(await state(binDir), before);
      } finally {
        await lock.unlock();
        await lock.close();
      }
      await promote(await request(await executable('2.0.0'), '2.0.0'));
      await expectClean('2.0.0');
    });
  });
}
