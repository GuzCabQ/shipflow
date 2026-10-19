import 'dart:io';

import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_dart/src/project_scanner.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

/// Un manifiesto Flutter que declara [assets] en `flutter.assets`.
String flutterManifest(List<String> assets, {String name = 'app'}) =>
    '''
name: $name
dependencies:
  flutter:
    sdk: flutter
flutter:
  assets:
${[for (final a in assets) '    - $a'].join('\n')}
''';

void main() {
  final sandbox = ScanSandbox()..register();
  late ListingSpy spy;

  setUp(() => spy = ListingSpy(sandbox.root));

  Future<ScanResult> scan() =>
      scanProject(sandbox.root, limits: const ScanLimits(), list: spy.call);

  group('a Flutter package excludes its temporary and declared trees', () {
    setUp(() {
      sandbox.place(
        'pubspec.yaml',
        flutterManifest(['assets/fonts/', './assets/images/', 'assets/a.png']),
      );
      for (final hidden in [
        'ios/Flutter/ephemeral/secret/pubspec.yaml',
        'assets/fonts/f/pubspec.yaml',
        'assets/images/i/pubspec.yaml',
        'assets/other/pubspec.yaml',
      ]) {
        sandbox.place(hidden, 'name: hidden\n');
      }
    });

    test('never lists ephemeral nor the declared directories', () async {
      final result = await scan();
      expect(spy.listed, isNot(contains('ios/Flutter/ephemeral')));
      expect(spy.listed, isNot(contains('assets/fonts')));
      expect(spy.listed, isNot(contains('assets/images')));
      expect(spy.listed, contains('assets'));
      expect(sourcePaths(result), [
        'assets/other/pubspec.yaml',
        'pubspec.yaml',
      ]);
    });

    test('records each omission with the evidence that justifies it', () async {
      final result = await scan();
      expect(omissionsOf(result), [
        'assets/fonts:declared_resource:manifest.resource_directory',
        'assets/images:declared_resource:manifest.resource_directory',
        'ios/Flutter/ephemeral:temporary_directory:manifest.flutter_dependency',
      ]);
      expect(result.limitations, isEmpty);
    });

    test('a file entry grants no exclusion and no limitation', () async {
      final result = await scan();
      final manifest = result.manifests.last;
      expect(manifest.facts.resourceDirectories, [
        'assets/fonts/',
        'assets/images/',
      ]);
      expect(result.manifestLimitations, isEmpty);
    });
  });

  test('a declared parent omits only itself, not its descendants', () async {
    sandbox.place('pubspec.yaml', flutterManifest(['assets/', 'assets/x/']));
    sandbox.place('assets/x/y/pubspec.yaml');
    final result = await scan();
    expect(spy.listed, isNot(contains('assets')));
    expect(omissionsOf(result), [
      'assets:declared_resource:manifest.resource_directory',
    ]);
  });

  group('no exception without its exact justification', () {
    test('a Dart package does not exclude ephemeral nor assets', () async {
      sandbox.place(
        'pubspec.yaml',
        'name: app\nflutter:\n  assets:\n    - assets/\n',
      );
      sandbox.place('ios/Flutter/ephemeral/pubspec.yaml', 'name: e\n');
      sandbox.place('assets/pubspec.yaml', 'name: a\n');
      final result = await scan();
      expect(sourcePaths(result), [
        'assets/pubspec.yaml',
        'ios/Flutter/ephemeral/pubspec.yaml',
        'pubspec.yaml',
      ]);
      expect(result.omissions, isEmpty);
    });

    test('a look-alike ephemeral or an undeclared assets is walked', () async {
      sandbox.place('pubspec.yaml', flutterManifest(['assets/fonts/']));
      for (final walked in [
        'android/Flutter/ephemeral/pubspec.yaml',
        'ios/ephemeral/pubspec.yaml',
        'app/ios/Flutter/ephemeral/pubspec.yaml',
        'assets/images/pubspec.yaml',
      ]) {
        sandbox.place(walked, 'name: w\n');
      }
      sandbox.directory('assets/fonts');
      final result = await scan();
      expect(sourcePaths(result), hasLength(5));
      expect(omissionsOf(result), [
        'assets/fonts:declared_resource:manifest.resource_directory',
      ]);
    });

    test('a nested package only excludes inside itself', () async {
      sandbox.place('app/pubspec.yaml', flutterManifest(['assets/']));
      sandbox.place('assets/pubspec.yaml', 'name: root_assets\n');
      final result = await scan();
      expect(sourcePaths(result), ['app/pubspec.yaml', 'assets/pubspec.yaml']);
    });
  });

  group('links and broken manifests grant nothing', () {
    test('a declared directory that is a link is omitted unfollowed', () async {
      sandbox.place('pubspec.yaml', flutterManifest(['assets/']));
      sandbox.place('real/pubspec.yaml', 'name: hidden\n');
      Link('${sandbox.root.path}/assets').createSync('real');
      final result = await scan();
      expect(result.limitations, isEmpty);
      expect(omissionsOf(result), [
        'assets:declared_resource:manifest.resource_directory',
      ]);
      expect(spy.listed, isNot(contains('assets')));
    });

    test('a link where nothing is declared still blocks', () async {
      sandbox.place('pubspec.yaml', flutterManifest(['assets/fonts/']));
      sandbox.directory('real');
      sandbox.directory('assets');
      Link('${sandbox.root.path}/assets/images').createSync('../real');
      final result = await scan();
      expect(limitationsOf(result), [
        'symlink_not_followed:assets/images:true',
      ]);
    });

    test('an invalid manifest grants no exclusion', () async {
      sandbox.place('pubspec.yaml', '${flutterManifest(['assets/'])}: [');
      sandbox.place('assets/pubspec.yaml', 'name: a\n');
      final result = await scan();
      expect(sourcePaths(result), contains('assets/pubspec.yaml'));
      expect(result.omissions, isEmpty);
    });

    test('a linked manifest grants no exclusion', () async {
      sandbox.place('elsewhere.yaml', flutterManifest(['assets/']));
      Link('${sandbox.root.path}/pubspec.yaml').createSync('elsewhere.yaml');
      sandbox.place('assets/pubspec.yaml', 'name: a\n');
      final result = await scan();
      expect(sourcePaths(result), ['assets/pubspec.yaml']);
      expect(result.omissions, isEmpty);
    });
  });

  group('unsupported resource declarations', () {
    for (final entry in [
      '{path: assets/x/}',
      '../assets/',
      '/abs/assets/',
      'assets/*/',
      r'assets\x\',
      'assets//x/',
      'images/',
      'https://cdn/assets/',
      'assets/../x/',
      "'./'",
    ]) {
      test('«$entry» is informed and grants no exclusion', () async {
        sandbox.place('pubspec.yaml', flutterManifest([entry]));
        final result = await scan();
        expect(result.omissions, isEmpty);
        expect(
          result.manifestLimitations.map((l) => '${l.code}:${l.blocking}'),
          ['unsupported_resource_declaration:false'],
        );
      });
    }

    test('a non-list assets declaration is informed', () async {
      sandbox.place(
        'pubspec.yaml',
        'name: a\ndependencies:\n  flutter:\n    sdk: flutter\n'
            'flutter:\n  assets: assets/\n',
      );
      final result = await scan();
      expect(result.manifestLimitations.map((l) => '${l.code}:${l.blocking}'), [
        'unsupported_resource_declaration:false',
      ]);
    });
  });

  group('baseline exclusions become omissions when found', () {
    test('each excluded tree at any depth', () async {
      sandbox.place('pubspec.yaml');
      sandbox.directory('.git/objects');
      sandbox.directory('packages/a/build');
      sandbox.directory('packages/a/node_modules');
      final result = await scan();
      expect(omissionsOf(result), [
        '.git:baseline_exclusion:',
        'packages/a/build:baseline_exclusion:',
        'packages/a/node_modules:baseline_exclusion:',
      ]);
      expect(spy.listed, isNot(contains('.git')));
    });
  });

  group('the manifest is read once and shared', () {
    test(
      'each manifest is read twice, the stable read, and parsed once',
      () async {
        final reads = <String>[];
        sandbox.place('pubspec.yaml', flutterManifest(['assets/']));
        sandbox.place('packages/b/pubspec.yaml', 'name: b\n');
        final result = await scanProject(
          sandbox.root,
          readBytes: (file, max) {
            reads.add(file.path.substring(sandbox.root.path.length + 1));
            return File(
              file.path,
            ).openRead(0, max + 1).expand((b) => b).toList();
          },
        );
        // La raíz lee su manifiesto antes de descender; el resultado se
        // entrega en orden de ruta.
        expect(reads, [
          'pubspec.yaml',
          'pubspec.yaml',
          'packages/b/pubspec.yaml',
          'packages/b/pubspec.yaml',
        ]);
        expect(result.manifests.map((m) => m.facts.name), ['b', 'app']);
      },
    );

    test('a manifest that changes between reads grants nothing', () async {
      sandbox.place('pubspec.yaml', flutterManifest(['assets/']));
      sandbox.place('assets/pubspec.yaml', 'name: a\n');
      var count = 0;
      final result = await scanProject(
        sandbox.root,
        readBytes: (file, max) async {
          final bytes = await File(file.path).readAsBytes();
          return file.path.endsWith('/assets/pubspec.yaml') || count++ == 0
              ? bytes
              : [...bytes, 0x20];
        },
      );
      expect(limitationsOf(result), [
        'source_changed_during_scan:pubspec.yaml:true',
      ]);
      expect(sourcePaths(result), ['assets/pubspec.yaml']);
      expect(result.omissions, isEmpty);
    });
  });
}
