import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assessment_fixtures.dart';

void main() {
  AssessmentSnapshot snapshotOf(Map<String, Object?> json) =>
      AssessmentSnapshot.fromJson(json);

  Map<String, Object?> unresolvedVariant() {
    final json = snapshotJson();
    (json['claims']! as List<Object?>).cast<Map<String, Object?>>().single
      ..['resolution'] = 'unresolved'
      ..['targetFileId'] = null
      ..['targetUnitId'] = null
      ..['reason'] = 'target_unreadable';
    final witnesses = (json['witnesses']! as List<Object?>)
        .cast<Map<String, Object?>>();
    witnesses.singleWhere((w) => w['id'] == 'local_resolution')
      ..['state'] = 'partial'
      ..['processed'] = 0
      ..['omitted'] = 1;
    return json..['coverage'] = 'partial';
  }

  test('a local claim becomes a connection that cites it', () {
    final connections = projectAssessment(snapshotOf(snapshotJson()));
    expect(connections.single.sourceUnitId, rootUnit);
    expect(connections.single.targetUnitId, widgetsUnit);
    expect(connections.single.claimIds, ['c_main_widget']);
  });

  test('unresolved and external references are not local edges', () {
    expect(projectAssessment(snapshotOf(unresolvedVariant())), isEmpty);
  });

  test('S3: declared and observed stay separate', () {
    // La fuente candidata del contexto es un vínculo declarado, y la única
    // conexión sale de la afirmación observada: ninguna se vuelve la otra.
    final snapshot = snapshotOf(snapshotJson());
    final connections = projectAssessment(snapshot);
    final linkIds = {for (final l in snapshot.contextLinks) l.sourceId};
    expect(connections.expand((c) => c.claimIds).toSet(), {'c_main_widget'});
    expect(linkIds.intersection({'c_main_widget'}), isEmpty);
    expect(
      snapshot.contextLinks.single.kind,
      AssessmentLinkKind.candidateSource,
    );
  });

  group('comparison', () {
    test('counts only between complete observations of one basis', () {
      final previous = snapshotOf(snapshotJson());
      final json = snapshotJson();
      final claims = (json['claims']! as List<Object?>)
          .cast<Map<String, Object?>>();
      claims.single['id'] = 'c_other';
      final comparison = compareAssessments(previous, snapshotOf(json))!;
      expect(comparison.addedReferences, 1);
      expect(comparison.repeatedReferences, 0);
      expect(comparison.notObservedNow, 1);
    });

    test('a partial reading never yields disappearance counts', () {
      final previous = snapshotOf(snapshotJson());
      expect(
        compareAssessments(previous, snapshotOf(unresolvedVariant())),
        isNull,
      );
    });

    test('another context or contract is not comparable', () {
      final previous = snapshotOf(snapshotJson());
      final other = snapshotJson();
      other['contextDigest'] = hashOf('d');
      final inputs = (other['inputs']! as List<Object?>)
          .cast<Map<String, Object?>>();
      inputs.last['sha256'] = hashOf('d');
      expect(compareAssessments(previous, snapshotOf(other)), isNull);
      final contract = snapshotJson();
      (contract['producer']! as Map<String, Object?>)['contract'] = 'v4';
      for (final w
          in (contract['witnesses']! as List<Object?>)
              .cast<Map<String, Object?>>()) {
        w['producerVersion'] = 'v4';
      }
      expect(compareAssessments(previous, snapshotOf(contract)), isNull);
    });
  });

  test('canonical identity orders keys by UTF-16 code units', () {
    // El vector del paquete: el carácter suplementario va antes que U+E000.
    expect(
      canonicalAssessmentJson({'': 3, 'a': 1, '😀': 2}),
      '{"a":1,"😀":2,"":3}',
    );
    expect(canonicalAssessmentJson(unitTuple('.')), '["unit","."]');
  });
}
