import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assessment_fixtures.dart';

void main() {
  Map<String, Object?> current(Map<String, Object?> document) =>
      document['current']! as Map<String, Object?>;
  List<Map<String, Object?>> rows(Map<String, Object?> s, String key) =>
      (s[key]! as List<Object?>).cast<Map<String, Object?>>();
  Map<String, Object?> witness(Map<String, Object?> s, String capability) =>
      rows(s, 'witnesses').singleWhere((w) => w['capability'] == capability);

  test('the reference document is accepted and round trips', () {
    final json = documentJson();
    final document = buildDocument(copyJson(json));
    expect(document.toJson(), json);
    expect(
      document.current.claims.single.resolution,
      AssessmentResolution.local,
    );
  });

  test('a dangling local target is rejected', () {
    final json = documentJson();
    rows(current(json), 'claims').single['targetFileId'] = 'f_missing';
    expect(() => buildDocument(json), rejectsWith('claim_target'));
  });

  test('a local claim needs its target file and unit', () {
    final json = documentJson();
    rows(current(json), 'claims').single['targetFileId'] = null;
    expect(() => buildDocument(json), rejectsWith('claim_target'));
  });

  test('an external or unresolved claim never names a local target', () {
    final json = documentJson();
    final claim = rows(current(json), 'claims').single;
    claim['resolution'] = 'external';
    expect(() => buildDocument(json), rejectsWith('claim_target'));
    claim
      ..['resolution'] = 'unresolved'
      ..['targetFileId'] = null
      ..['targetUnitId'] = null;
    expect(() => buildDocument(json), rejectsWith('claim_reason'));
  });

  test('a file the parser failed on contributes no claims', () {
    final json = documentJson();
    final s = current(json);
    rows(s, 'files').first['parseState'] = 'failed';
    witness(s, 'source_references')
      ..['state'] = 'partial'
      ..['processed'] = 1
      ..['failed'] = 1;
    s['coverage'] = 'partial';
    expect(() => buildDocument(json), rejectsWith('unparsed_claim'));
  });

  test('witness counts must follow the collections', () {
    final json = documentJson();
    witness(current(json), 'source_references')['expected'] = 3;
    expect(() => buildDocument(json), rejectsWith('witness_counts'));
  });

  test('a complete witness cannot carry omissions', () {
    final json = documentJson();
    final s = current(json);
    rows(s, 'claims').single
      ..['resolution'] = 'unresolved'
      ..['targetFileId'] = null
      ..['targetUnitId'] = null
      ..['reason'] = 'target_unreadable';
    witness(s, 'local_resolution')
      ..['processed'] = 0
      ..['omitted'] = 1;
    expect(() => buildDocument(json), rejectsWith('witness_state'));
  });

  test('coverage cannot claim complete over a partial witness', () {
    final json = documentJson();
    final s = current(json);
    rows(s, 'claims').single
      ..['resolution'] = 'unresolved'
      ..['targetFileId'] = null
      ..['targetUnitId'] = null
      ..['reason'] = 'target_unreadable';
    witness(s, 'local_resolution')
      ..['state'] = 'partial'
      ..['processed'] = 0
      ..['omitted'] = 1;
    expect(() => buildDocument(json), rejectsWith('coverage'));
    s['coverage'] = 'partial';
    expect(buildDocument(json).current.coverage, AssessmentCoverage.partial);
  });

  test('a witness from another producer contract is rejected', () {
    final json = documentJson();
    witness(current(json), 'test_inventory')['producerVersion'] = 'other';
    expect(() => buildDocument(json), rejectsWith('witness_identity'));
  });

  test('every capability leaves exactly one witness', () {
    final json = documentJson();
    rows(current(json), 'witnesses').removeLast();
    expect(() => buildDocument(json), rejectsWith('capabilities'));
  });

  test('a file names its own source input and its deepest unit', () {
    final mismatch = documentJson();
    rows(current(mismatch), 'files').last['inputPath'] = 'lib/main.src';
    expect(() => buildDocument(mismatch), rejectsWith('file_input'));
    final owner = documentJson();
    rows(current(owner), 'files').last['unitId'] = rootUnit;
    rows(current(owner), 'claims').single['targetUnitId'] = rootUnit;
    expect(() => buildDocument(owner), rejectsWith('file_owner'));
  });

  test('every eligible source in the inventory has its file', () {
    final json = documentJson();
    final s = current(json);
    rows(s, 'files').removeLast();
    rows(s, 'claims').clear();
    witness(s, 'source_references')
      ..['expected'] = 1
      ..['processed'] = 1;
    witness(s, 'test_inventory')
      ..['expected'] = 1
      ..['processed'] = 1;
    witness(s, 'local_resolution')
      ..['expected'] = 0
      ..['processed'] = 0;
    expect(() => buildDocument(json), rejectsWith('file_input'));
  });

  test('the context input carries the cited context digest', () {
    final json = documentJson();
    rows(current(json), 'inputs').last['sha256'] = hashOf('c');
    expect(() => buildDocument(json), rejectsWith('context_input'));
  });

  test('an input appears once per path and kind', () {
    final json = documentJson();
    final inputs = rows(current(json), 'inputs');
    inputs.insert(1, inputs[1]);
    expect(() => buildDocument(json), rejectsWith('duplicate_input'));
  });

  test('collections keep their canonical order', () {
    final json = documentJson();
    final units = rows(current(json), 'units');
    current(json)['units'] = units.reversed.toList();
    expect(() => buildDocument(json), rejectsWith('order'));
  });

  test('previous only exists from the second revision on', () {
    final json = documentJson(previous: snapshotJson());
    expect(() => buildDocument(json), rejectsWith('revision'));
    expect(
      buildDocument(
        documentJson(previous: snapshotJson(), revision: 2),
      ).previous,
      isNotNull,
    );
  });

  test('zero references over parsed sources is complete', () {
    final json = documentJson();
    final s = current(json);
    rows(s, 'claims').clear();
    witness(s, 'local_resolution')
      ..['expected'] = 0
      ..['processed'] = 0;
    final document = buildDocument(json);
    expect(document.current.coverage, AssessmentCoverage.complete);
    expect(document.current.claims, isEmpty);
  });

  test('a detector that did not run is not zero references', () {
    final json = documentJson();
    final s = current(json);
    rows(s, 'claims').clear();
    for (final file in rows(s, 'files')) {
      file['parseState'] = 'not_run';
    }
    witness(s, 'local_resolution')
      ..['expected'] = 0
      ..['processed'] = 0;
    witness(s, 'source_references')
      ..['state'] = 'not_run'
      ..['processed'] = 0
      ..['omitted'] = 2;
    expect(() => buildDocument(json), rejectsWith('coverage'));
    s['coverage'] = 'partial';
    final document = buildDocument(json);
    final references = document.current.witnesses.singleWhere(
      (w) => w.capability == AssessmentCapability.sourceReferences,
    );
    expect(references.state, AssessmentWitnessState.notRun);
  });
}
