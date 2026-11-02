@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';
import 'support/context_service_support.dart';

/// Regresión de REV-V3-002 R7b: un journal V2 que aparece antes de que
/// recover tome el lock deja dos transacciones activas; es un conflicto que
/// conserva ambas, nunca un aborto que limpia la de assess.
void main() {
  late AssessServiceBox box;
  late File v2Journal;
  late List<int> v2Bytes;
  setUp(() async {
    box = await AssessServiceBox.initialized();
    await box.run(AssessmentOperation.observe);
    box.box.file('packages/third/pubspec.yaml', 'name: third\n');
    await expectLater(
      box.box.run(
        ContextOperation.refresh,
        wrap: (real) => CrashingStore(real, 1),
      ),
      throwsA(isA<SimulatedCrash>()),
    );
    v2Journal = File(box.path('shipflow/local/transaction.json'));
    v2Bytes = v2Journal.readAsBytesSync();
    v2Journal.deleteSync();
    Directory(box.path('packages/third')).deleteSync(recursive: true);
  });
  tearDown(() => box.dispose());

  /// Recover con el journal V2 puesto justo al tomar el lock: el estado y
  /// la respuesta deben conservar las dos transacciones.
  Future<void> expectBothKept(String why) async {
    final journal = File(box.path(assessmentJournalPath)).readAsBytesSync();
    final document = box.document.readAsBytesSync();
    box.storeWrap = (real) => _JournalOnLock(real, v2Journal.path, v2Bytes);
    final result = await box.run(AssessmentOperation.recover);
    expect(result.exitCode, 75, reason: why);
    expect(diagnosticCodes(result), contains('recovery_conflict'));
    expect(result.effects.removed, isEmpty);
    expect(result.effects.published, isFalse);
    expect(v2Journal.readAsBytesSync(), v2Bytes);
    expect(File(box.path(assessmentJournalPath)).readAsBytesSync(), journal);
    expect(box.document.readAsBytesSync(), document);
  }

  test(
    'R7b: before the commit, both journals and the candidate stay',
    () async {
      await interruptPublication(box);
      final candidates = Directory(
        box.path('shipflow/local/assessment-staging'),
      ).listSync(recursive: true).whereType<File>().toList();
      await expectBothKept('prepared');
      expect(candidates.every((f) => f.existsSync()), isTrue);
    },
  );

  test('R7b: after the commit, the assess journal is not cleaned', () async {
    // La cuarta escritura (journal publicado) falla después del rename: el
    // documento ya está en su versión preparada y el journal sigue.
    box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
    box.storeWrap = (real) => FailingStore(real, 4);
    expect((await box.run(AssessmentOperation.observe)).exitCode, 74);
    await expectBothKept('published');
  });
}

/// Pone [bytes] en [path] justo al tomar el lock de publicación, como una
/// operación V2 que dejó su journal antes de que recover entrara.
final class _JournalOnLock extends CrashingStore {
  _JournalOnLock(ContextStore real, this.path, this.bytes)
    : super(real, 1 << 30);

  final String path;
  final List<int> bytes;

  @override
  Future<ContextLease> acquirePublication(
    List<ContextResource> resources,
  ) async {
    final lease = await real.acquirePublication(resources);
    File(path).writeAsBytesSync(bytes);
    return lease;
  }
}
