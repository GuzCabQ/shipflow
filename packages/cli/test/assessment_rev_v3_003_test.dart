@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';
import 'support/context_service_support.dart';

/// Regresiones de REV-V3-003: efectos conservados tras publicar (R10),
/// contexto revalidado al terminar la consulta (R11) y retiro de historia
/// informado por quien publica (R12).
void main() {
  late AssessServiceBox box;
  setUp(() async {
    box = await AssessServiceBox.initialized();
    await box.run(AssessmentOperation.observe);
  });
  tearDown(() => box.dispose());

  Future<AssessmentResult> recover() => box.run(AssessmentOperation.recover);
  Future<AssessmentResult> show() => box.run(AssessmentOperation.show);
  Future<void> secondRevision() async {
    box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
    expect((await box.run(AssessmentOperation.observe)).exitCode, 0);
  }

  group('R10: a failure after recovering keeps what was published', () {
    for (final (name, failure) in [
      ('a read that fails', _AfterRename.failing),
      ('bytes that do not decode', _AfterRename.garbage),
    ]) {
      test('$name once the journal is gone', () async {
        await interruptPublication(box);
        box.storeWrap = (real) =>
            _AfterRename(real, failure, afterJournal: true);
        final result = await recover();
        expect(result.effects.published, isTrue);
        expect(result.effects.replaced, contains(assessmentPath));
        expect(result.snapshot, isNotNull);
        // Presenta el documento validado con el lock: no vuelve a leer un
        // archivo que otro pudo sustituir, así que no hay fallo que dar.
        expect(result.exitCode, 0, reason: '${diagnosticCodes(result)}');
      });
    }

    test('a read that fails right after the rename', () async {
      await interruptPublication(box);
      box.storeWrap = (real) => _AfterRename(real, _AfterRename.failing);
      final result = await recover();
      expect(result.effects.published, isTrue);
      expect(result.exitCode, 74);
      expect(diagnosticCodes(result), contains('io_failure'));
    });

    test('observe keeps it too when a read after the rename fails', () async {
      box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
      box.storeWrap = (real) => _AfterRename(real, _AfterRename.failing);
      final result = await box.run(AssessmentOperation.observe);
      expect(result.effects.published, isTrue);
      expect(result.exitCode, 74);
    });
  });

  group('R11: --show rechecks the context when it ends', () {
    test('a context changed during the check is never current', () async {
      var changes = 0;
      box.inputsWrap = (real) => (root, context, limits) {
        if (changes++ == 0) _touchContext(box);
        return real(root, context, limits);
      };
      final result = await show();
      expect(result.freshness, AssessmentFreshness.stale);
      expect(result.exitCode, 65);
    });

    test('a context that keeps changing is a concurrent change', () async {
      box.inputsWrap = (real) => (root, context, limits) {
        _touchContext(box);
        return real(root, context, limits);
      };
      final result = await show();
      expect(result.freshness, isNot(AssessmentFreshness.current));
      expect(result.exitCode, 75);
      expect(diagnosticCodes(result), contains('concurrent_change'));
    });

    test(
      'without changes it stays current, without parser or writes',
      () async {
        final before = box.snapshot();
        final observations = box.observations;
        final result = await show();
        expect(result.freshness, AssessmentFreshness.current);
        expect(result.exitCode, 0, reason: '${diagnosticCodes(result)}');
        expect(box.observations, observations);
        expect(box.snapshot(), before);
      },
    );
  });

  group('R12: the operation that publishes reports the retired revision', () {
    Future<void> interruptThird() async {
      await secondRevision();
      box.box.file('lib/other.dart', "import 'main.dart';\n// r3\n");
      box.storeWrap = (real) => CrashingStore(real, 2);
      await expectLater(
        box.run(AssessmentOperation.observe),
        throwsA(isA<SimulatedCrash>()),
      );
      box.storeWrap = null;
    }

    test('recovering the third revision retires the first', () async {
      await interruptThird();
      final result = await recover();
      expect(decodeAssessment(box.document.readAsBytesSync()).revision, 3);
      expect(result.retiredRevision, 1);
      expect(diagnosticCodes(result), contains('revision_retired'));
    });

    test('recovering the second revision retires nothing', () async {
      box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
      box.storeWrap = (real) => CrashingStore(real, 2);
      await expectLater(
        box.run(AssessmentOperation.observe),
        throwsA(isA<SimulatedCrash>()),
      );
      box.storeWrap = null;
      final result = await recover();
      expect(decodeAssessment(box.document.readAsBytesSync()).revision, 2);
      expect(result.retiredRevision, isNull);
      expect(diagnosticCodes(result), isNot(contains('revision_retired')));
    });

    test('cleaning a done publication reports it, as observe did', () async {
      await secondRevision();
      box.box.file('lib/other.dart', "import 'main.dart';\n// r3\n");
      // La cuarta escritura (journal publicado) falla tras el rename.
      box.storeWrap = (real) => FailingStore(real, 4);
      final observed = await box.run(AssessmentOperation.observe);
      expect(observed.retiredRevision, 1);
      box.storeWrap = null;
      final result = await recover();
      expect(result.retiredRevision, 1);
      expect(diagnosticCodes(result), contains('revision_retired'));
    });
  });
}

/// Agrega un salto de línea a `project.json`: sigue válido, con otra huella.
void _touchContext(AssessServiceBox box) {
  final file = File(box.path('shipflow/project.json'));
  file.writeAsStringSync('${file.readAsStringSync()}\n');
}

/// Un almacén real que, después del rename, falla en cualquier lectura; o
/// que, después de retirar el journal, falla o devuelve bytes que no
/// decodifican al leer el documento.
final class _AfterRename extends CrashingStore {
  _AfterRename(ContextStore real, this.failure, {this.afterJournal = false})
    : super(real, 1 << 30);

  static const failing = 'failing';
  static const garbage = 'garbage';

  final String failure;
  final bool afterJournal;
  var _armed = false;

  @override
  Future<void> publishRelative(
    String path,
    List<int> bytes, {
    required String? expectedSha256,
  }) async {
    await real.publishRelative(path, bytes, expectedSha256: expectedSha256);
    if (path == assessmentPath && !afterJournal) _armed = true;
  }

  @override
  Future<void> removeRelative(
    String path, {
    required String expectedSha256,
  }) async {
    await real.removeRelative(path, expectedSha256: expectedSha256);
    if (path == assessmentJournalPath && afterJournal) _armed = true;
  }

  @override
  Future<List<int>?> readRelative(String path, {required int maxBytes}) {
    if (_armed && (path == assessmentPath || !afterJournal)) {
      if (failure == failing) throw const ContextStoreFailure('io');
      return Future.value('{roto'.codeUnits);
    }
    return real.readRelative(path, maxBytes: maxBytes);
  }
}
