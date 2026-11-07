@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/assessment/assessment_response_shape.dart';
import 'package:cli/src/context/context_response_shape.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';
import 'support/basis_service_support.dart';
import 'support/basis_support.dart';
import 'support/context_service_support.dart';

Map<String, Object?> _json(String file) =>
    jsonDecode(File('${v4Fixtures()}/compat/$file').readAsStringSync())
        as Map<String, Object?>;

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  Future<ContextOperationResult> doctor() =>
      box.box.run(ContextOperation.doctor);

  ContextCheck checkOf(ContextOperationResult r, String id) =>
      r.checks.singleWhere((c) => c.id.toWireName() == id);

  List<String> actionsOf(ContextOperationResult r) => [
    for (final a in r.nextActions)
      '${a.command.toWireName()} ${a.arguments.join(' ')}',
  ];

  test('old_context_remains_usable_without_basis', () async {
    final result = await doctor();
    expect(result.exitCode, 0);
    expect(result.schemaVersion, 4);
    expect(result.contextState, ContextState.present);
    final integrity = checkOf(result, 'basis_integrity');
    expect(integrity.status, ContextCheckStatus.notChecked);
    expect(integrity.code, 'basis_not_initialized');
    expect(
      checkOf(result, 'basis_transaction').status,
      ContextCheckStatus.passed,
    );
    shapeResponse(jsonDecode(jsonEncode(result.toJson())));
  });

  test('a published basis is owned state and passes its check', () async {
    await box.publish(box.input([create('rule', ruleOf())]));
    final result = await doctor();
    expect(result.exitCode, 0);
    expect(
      checkOf(result, 'basis_integrity').status,
      ContextCheckStatus.passed,
    );
  });

  test(
    'an invalid basis is reported without invalidating the context',
    () async {
      await box.publish(box.input([create('rule', ruleOf())]));
      box.basis.writeAsStringSync('{"roto": true}\n');
      final result = await doctor();
      expect(result.exitCode, 65);
      expect(result.outcome, ContextOutcome.needsAttention);
      expect(result.contextState, ContextState.present);
      expect(
        checkOf(result, 'basis_integrity').status,
        ContextCheckStatus.failed,
      );
      expect(box.basis.readAsStringSync(), '{"roto": true}\n');
    },
  );

  test('a pending basis publication is 75 with its recover action', () async {
    await interruptBasis(box, [create('rule', ruleOf())]);
    final result = await doctor();
    expect(result.exitCode, 75);
    final check = checkOf(result, 'basis_transaction');
    expect(check.status, ContextCheckStatus.failed);
    expect(check.code, 'basis_recovery_required');
    expect(actionsOf(result), contains('bootstrap --recover'));
    shapeResponse(jsonDecode(jsonEncode(result.toJson())));
  });

  group('foreign_journal_owner_is_not_recovered', () {
    test(
      'init --recover keeps the basis journal and points to bootstrap',
      () async {
        await interruptBasis(box, [create('rule', ruleOf())]);
        final journal = box.journal.readAsBytesSync();
        final result = await box.box.run(ContextOperation.recover);
        expect(box.journal.readAsBytesSync(), journal);
        expect(result.exitCode, isNot(0));
        expect(actionsOf(result), contains('bootstrap --recover'));
      },
    );

    test('assess is blocked and points to bootstrap --recover', () async {
      final assess = await AssessServiceBox.initialized();
      addTearDown(assess.dispose);
      final basis = BasisBox.on(assess.box);
      await interruptBasis(basis, [create('rule', ruleOf())]);
      final result = await assess.run(AssessmentOperation.observe);
      expect(result.exitCode, 75);
      expect(result.schemaVersion, 2);
      expect(result.effects.published, isFalse);
      expect([
        for (final a in result.nextActions) a.argv.join(' '),
      ], contains('shipflow bootstrap --recover'));
      shapeAssessmentResponse(jsonDecode(jsonEncode(result.toJson())));
    });

    test('bootstrap --recover does not take an init transaction', () async {
      await interruptBasis(box, [create('rule', ruleOf())]);
      box.box.file('pubspec.yaml', 'name: app\n# cambio\n');
      await expectLater(
        box.box.run(ContextOperation.refresh, wrap: (r) => CrashingStore(r, 1)),
        throwsA(isA<SimulatedCrash>()),
      );
      final journal = box.journal.readAsBytesSync();
      final result = await box.recover();
      expect(result.exitCode, 75);
      expect(box.journal.readAsBytesSync(), journal);
    });
  });

  test('a same-project refresh keeps the basis consultable', () async {
    await box.publish(box.input([create('rule', ruleOf())]));
    box.box.file('pubspec.yaml', 'name: app\n# cambio\n');
    expect((await box.box.run(ContextOperation.refresh)).exitCode, 0);
    final shown = await box.show();
    expect(shown.exitCode, 0, reason: '${codesOf(shown)}');
    expect(shown.selected, hasLength(1));
  });

  group('response majors', () {
    test('the package compat examples have the new shapes', () {
      shapeResponse(_json('valid-doctor-basis-recovery.json'));
      shapeAssessmentResponse(_json('valid-assess-basis-recovery.json'));
    });

    test('an old major is rejected explicitly, not read as new', () {
      final old = {
        ..._json('valid-doctor-basis-recovery.json'),
        'schemaVersion': 3,
      };
      expect(() => shapeResponse(old), throwsA(isA<ContextFormatException>()));
      final assess = {
        ..._json('valid-assess-basis-recovery.json'),
        'schemaVersion': 1,
      };
      expect(
        () => shapeAssessmentResponse(assess),
        throwsA(isA<ContextFormatException>()),
      );
    });
  });
}
