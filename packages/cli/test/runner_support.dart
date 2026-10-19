import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

/// Un directorio temporal canónico y un contribuidor que registra cada raíz
/// que recibe.
final class RunnerSandbox {
  late Directory root;
  final received = <String>[];

  void register() {
    setUp(() async {
      final created = await Directory.systemTemp.createTemp('shipflow-run-');
      root = Directory(created.resolveSymbolicLinksSync());
      received.clear();
    });
    tearDown(() async {
      await Process.run('chmod', ['-R', 'u+rwx', root.path]);
      await root.delete(recursive: true);
    });
  }

  Future<RecognitionContribution> contribute(
    Directory directory, {
    required ReportLimits reportLimits,
  }) async {
    received.add(directory.path);
    return RecognitionContribution(
      candidates: [
        StackCandidate(
          id: 'stack',
          displayName: 'Stack',
          pluginId: 'plugin',
          evidenceIds: const ['e0001'],
        ),
      ],
      units: [
        ProjectUnit(
          id: 'u0001',
          name: 'app',
          kind: 'package',
          path: '.',
          evidenceIds: const ['e0001'],
        ),
      ],
      evidence: const [
        RecognitionEvidence(
          id: 'e0001',
          kind: 'k',
          path: 'manifest',
          value: 'app',
          fingerprint: 'sha256:x',
        ),
      ],
      conflicts: const [],
      limitations: const [],
    );
  }

  Future<CliResponse> run(
    List<String> arguments, {
    Directory? workingDirectory,
    RecognitionContributor? contributor,
    String? logicalRootHint,
  }) => runCli(
    arguments,
    version: '1.0.0',
    workingDirectory: workingDirectory ?? root,
    recognizeProject: contributor ?? contribute,
    logicalRootHint: logicalRootHint,
  );
}

Map<String, Object?> decode(CliResponse response) =>
    jsonDecode(response.payload) as Map<String, Object?>;
