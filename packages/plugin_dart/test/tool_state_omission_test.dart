import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart' show ContextSourceRule;
import 'package:plugin_dart/src/dart_project_recognizer.dart';
import 'package:plugin_dart/src/recognition/directory_listing.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

final _toolState = AuthorizedOmission(
  relativePath: 'shipflow',
  rule: OmissionRule.toolState,
);

void main() {
  final sandbox = ScanSandbox()..register();

  /// El reconocimiento de la raíz, con los directorios que llegó a listar.
  Future<(RecognitionContribution, List<String>)> recognize({
    List<AuthorizedOmission> authorized = const [],
  }) async {
    final listed = <String>[];
    final contribution = await recognizeListing(
      sandbox.root,
      authorizedOmissions: authorized,
      list: (directory) {
        listed.add(directory.path);
        return listWithoutFollowing(directory);
      },
    );
    return (contribution, listed);
  }

  setUp(() => sandbox.place('pubspec.yaml', 'name: app\n'));

  test('ownedStateHasStableOmissionBeforeAndAfterInit', () async {
    final (before, _) = await recognize(authorized: [_toolState]);
    sandbox.place('shipflow/project.json', '{}');
    sandbox.place('shipflow/local/settings.json', '{}');
    final (after, listed) = await recognize(authorized: [_toolState]);
    expect(jsonEncode(after.toJson()), jsonEncode(before.toJson()));
    final omission = after.omissions.single;
    expect(omission.path, 'shipflow');
    expect(omission.rule, OmissionRule.toolState);
    expect(omission.evidenceIds, isEmpty);
    expect(
      listed.where((p) => p.startsWith('${sandbox.root.path}/shipflow')),
      isEmpty,
    );
  });

  test('foreignStateDirectoryIsNotOmitted without authorization', () async {
    sandbox.place('shipflow/pubspec.yaml', 'name: ajeno\n');
    final (contribution, listed) = await recognize();
    expect(contribution.omissions, isEmpty);
    expect(contribution.units.map((u) => u.path), contains('shipflow'));
    expect(listed, contains('${sandbox.root.path}/shipflow'));
  });

  test('requiredReferenceIntoStateStillBlocks', () async {
    sandbox.place(
      'pubspec.yaml',
      'name: app\ndependencies:\n  x: {path: shipflow/x}\n',
    );
    final (contribution, _) = await recognize(authorized: [_toolState]);
    expect(
      contribution.limitations.map((l) => l.code),
      contains('required_path_excluded'),
    );
    expect(contribution.relations.single.status, RelationStatus.unresolved);
  });

  test(
    'a candidate source inside the state is excluded, not observed',
    () async {
      final contribution = await recognizeDartProject(
        Directory(sandbox.root.path),
        authorizedOmissions: [_toolState],
        contextSources: const [
          ContextSourceRule(
            relativePath: 'shipflow/README.md',
            kind: ContextSourceKind.documentation,
            expectsDirectory: false,
          ),
        ],
      );
      final source = contribution.contextSources.single;
      expect(source.reason, ContextReason.excluded);
    },
  );
}
