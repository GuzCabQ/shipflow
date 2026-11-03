import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assessment_support.dart';

void main() {
  final box = AssessSandbox()..register();

  /// Un proyecto con un paquete local declarado por ruta y un vecino con el
  /// nombre de una dependencia remota.
  void project(String main) {
    box.package(
      '.',
      'app',
      extra: '''
dependencies:
  widgets:
    path: packages/widgets
  remote: ^1.0.0
''',
    );
    box.package('packages/widgets', 'widgets');
    box.package('packages/remote', 'remote');
    box.place('packages/widgets/lib/widget.dart', 'class W {}\n');
    box.place('packages/remote/lib/r.dart', 'class R {}\n');
    box.place('lib/src/util.dart', 'class U {}\n');
    box.place('build/gen.dart', 'class G {}\n');
    box.place('lib/main.dart', main);
  }

  Future<AssessmentClaim> only(String main) async {
    project(main);
    return claimsFrom(await box.observe(), 'lib/main.dart').single;
  }

  test('a relative reference resolves to an included file', () async {
    final claim = await only("import 'src/util.dart';\n");
    expect(claim.resolution, AssessmentResolution.local);
    expect(claim.targetLabel, 'lib/src/util.dart');
  });

  test('the own package resolves only to its own lib', () async {
    final claim = await only("import 'package:app/src/util.dart';\n");
    expect(claim.resolution, AssessmentResolution.local);
    expect(claim.targetLabel, 'lib/src/util.dart');
  });

  test('a corroborated path dependency is local with its evidence', () async {
    final claim = await only("import 'package:widgets/widget.dart';\n");
    expect(claim.resolution, AssessmentResolution.local);
    expect(claim.targetLabel, 'packages/widgets/lib/widget.dart');
    expect(claim.targetUnitId, startsWith('u_'));
    expect((claim.evidence.offset, claim.evidence.line), (0, 1));
    expect(claim.evidence.length, 37);
  });

  test('a neighbour named like a remote dependency is not linked', () async {
    final claim = await only("import 'package:remote/r.dart';\n");
    expect(claim.resolution, isNot(AssessmentResolution.local));
    expect(claim.targetUnitId, isNull);
    expect(claim.resolution, AssessmentResolution.external);
    expect(claim.targetLabel, 'package:remote/r.dart');
  });

  test('the platform library is external and never a local edge', () async {
    final claim = await only("import 'dart:io';\n");
    expect(claim.resolution, AssessmentResolution.external);
    expect(claim.targetLabel, 'dart:io');
    expect(claim.targetFileId, isNull);
  });

  test('a reference that leaves the root is unresolved', () async {
    final claim = await only("import '../../fuera.dart';\n");
    expect(
      (claim.resolution, claim.reason, claim.targetLabel),
      (AssessmentResolution.unresolved, 'outside_root', null),
    );
  });

  test(
    'an excluded or a missing target is unresolved with its reason',
    () async {
      final excluded = await only("import '../build/gen.dart';\n");
      expect(excluded.reason, 'target_excluded');
      box.place('lib/main.dart', "import 'nada.dart';\n");
      final missing = claimsFrom(await box.observe(), 'lib/main.dart').single;
      expect(missing.reason, 'target_missing');
    },
  );

  test(
    'an unsupported scheme is unresolved and its literal is not kept',
    () async {
      project("import 'https://evil.example/x.dart';\n");
      final observation = await box.observe();
      final claim = claimsFrom(observation, 'lib/main.dart').single;
      expect(
        (claim.resolution, claim.reason, claim.targetLabel),
        (AssessmentResolution.unresolved, 'unsupported_scheme', null),
      );
      expect(observedText(observation), isNot(contains('evil.example')));
    },
  );

  test(
    'a named part owner stays unresolved; a uri owner is attached',
    () async {
      project("import 'src/util.dart';\n");
      box.place('lib/src/named.dart', 'part of app.util;\n');
      box.place('lib/src/part.dart', "part of 'util.dart';\n");
      final observation = await box.observe();
      final named = claimsFrom(observation, 'lib/src/named.dart').single;
      expect(
        (named.resolution, named.reason),
        (AssessmentResolution.unresolved, 'named_owner'),
      );
      final attached = claimsFrom(observation, 'lib/src/part.dart').single;
      expect(attached.relation, AssessmentRelation.sourceAttachment);
      expect(attached.resolution, AssessmentResolution.local);
    },
  );

  test('a conditional import keeps its fallback and branches', () async {
    final observation = await (() async {
      project('''
import 'src/util.dart'
    if (dart.library.io) 'src/io.dart';
''');
      box.place('lib/src/io.dart', 'class I {}\n');
      return box.observe();
    })();
    final claims = claimsFrom(observation, 'lib/main.dart');
    expect(
      {for (final c in claims) c.condition},
      {AssessmentCondition.fallback, AssessmentCondition.conditional},
    );
    expect({for (final c in claims) c.groupId}, hasLength(1));
    final branch = claims.singleWhere(
      (c) => c.condition == AssessmentCondition.conditional,
    );
    expect(branch.sourceMetadata.conditionText, 'dart.library.io');
  });
}
