import 'dart:io';

import 'package:plugin_dart/src/project_scanner.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

// Sólo un manifiesto válido y con nombre concede exclusiones (§4, RU-06).
void main() {
  final sandbox = ScanSandbox()..register();

  Future<ScanResult> scan() => scanProject(sandbox.root);

  group('exclusions need a valid named manifest', () {
    test('a semantically invalid manifest grants no exclusion', () async {
      sandbox.place(
        'pubspec.yaml',
        flutterManifest([
          'assets/x/',
        ]).replaceFirst('name: app\n', 'name: app\nenvironment: 3\n'),
      );
      sandbox.directory('assets/x/inner');
      Link('${sandbox.root.path}/assets/x/inner/lnk').createSync('.');
      final result = await scan();
      expect(result.omissions, isEmpty);
      expect(
        limitationsOf(result),
        contains('symlink_not_followed:assets/x/inner/lnk:true'),
      );
    });

    test('a nameless manifest grants no exclusion', () async {
      sandbox.place(
        'tool/pubspec.yaml',
        flutterManifest(['assets/']).replaceFirst('name: app\n', ''),
      );
      sandbox.directory('tool/assets');
      Link('${sandbox.root.path}/tool/assets/lnk').createSync('.');
      final result = await scan();
      expect(result.omissions, isEmpty);
      expect(
        limitationsOf(result),
        contains('symlink_not_followed:tool/assets/lnk:true'),
      );
    });
  });
}
