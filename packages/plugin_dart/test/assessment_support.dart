import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

/// Una raíz temporal canónica para observar fuentes, nueva en cada prueba.
final class AssessSandbox {
  late Directory root;

  void register() {
    setUp(() async {
      final created = await Directory.systemTemp.createTemp('shipflow-obs-');
      root = Directory(created.resolveSymbolicLinksSync());
    });
    tearDown(() async {
      await Process.run('chmod', ['-R', 'u+rwx', root.path]);
      await root.delete(recursive: true);
    });
  }

  File place(String relative, String content) => File('${root.path}/$relative')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  /// Un paquete con manifiesto en [path] llamado [name].
  void package(String path, String name, {String extra = ''}) {
    place(path == '.' ? 'pubspec.yaml' : '$path/pubspec.yaml', '''
name: $name
environment:
  sdk: ^3.6.0
$extra''');
  }

  /// El contexto V2 que reconoce hoy la raíz, como lo citaría assess.
  Future<ProjectContext> context({
    List<ContextSourceRule> sources = const [],
  }) async {
    final contribution = await recognizeDartProject(
      root,
      contextSources: sources,
      authorizedOmissions: [
        AuthorizedOmission(
          relativePath: toolStatePath,
          rule: OmissionRule.toolState,
        ),
      ],
    );
    final report = _assembled(root, contribution);
    final recognition = projectRecognition(report);
    return ProjectContext(
      projectId: '11111111-1111-4111-8111-111111111111',
      revision: 1,
      producer: ContextProducer(
        version: '0.0.0-prueba',
        recognitionContract: 'declared-project-v2.1',
        pluginIds: {
          for (final c in recognition.candidates) c.pluginId,
        }.toList(),
      ),
      observedAt: '2026-11-02T12:00:00Z',
      recognition: recognition,
      observationDigest: 'a' * 64,
    );
  }

  Future<AssessmentObservation> observe({
    AssessmentLimits? limits,
    DirectiveParser? parser,
  }) async => observeDartSources(
    root,
    await context(),
    limits ?? AssessmentLimits.forProfile(AssessmentProfile.standard),
    parser: parser,
  );
}

/// La afirmación cuyo archivo de origen es [source].
List<AssessmentClaim> claimsFrom(AssessmentObservation o, String source) {
  final id = o.files.singleWhere((f) => f.path == source).id;
  return [
    for (final c in o.claims)
      if (c.sourceFileId == id) c,
  ];
}

AssessmentFile fileAt(AssessmentObservation o, String path) =>
    o.files.singleWhere((f) => f.path == path);

AssessmentInput inputAt(
  AssessmentObservation o,
  String path, [
  AssessmentInputKind? kind,
]) => o.inputs.singleWhere(
  (i) => i.path == path && (kind == null || i.kind == kind),
);

List<String> diagnosticCodes(AssessmentObservation o) => [
  for (final d in o.diagnostics) d.code,
];

/// Todo lo observado como texto, para comprobar qué nunca se guarda.
String observedText(AssessmentObservation o) => jsonEncode(o.toJson());

RecognitionReport _assembled(
  Directory root,
  RecognitionContribution contribution,
) => assembleRecognition(
  requestedRoot: root.path,
  resolvedRoot: root.path,
  repository: const RepositoryContext(
    status: RepositoryStatus.absent,
    root: null,
    relation: RepositoryRelation.none,
  ),
  contributions: [contribution],
);
