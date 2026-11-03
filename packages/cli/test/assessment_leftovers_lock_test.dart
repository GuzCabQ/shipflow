@Timeout(Duration(minutes: 2))
library;

import 'package:cli/src/context/native/posix_api.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';
import 'support/context_service_support.dart';

/// Retirar un candidato sin journal ocurre con el lock tomado: el lint
/// `unawaited_return_in_try_block` de Dart stable mostró que la liberación
/// del `finally` no lo esperaba.
void main() {
  test('leftovers are removed while the lock is still held', () async {
    final box = await AssessServiceBox.initialized();
    addTearDown(box.dispose);
    await box.run(AssessmentOperation.observe);
    box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
    // Muere tras escribir el candidato y antes del journal.
    box.storeWrap = (real) => CrashingStore(real, 1);
    await expectLater(
      box.run(AssessmentOperation.observe),
      throwsA(isA<SimulatedCrash>()),
    );
    box.storeWrap = null;
    final posix = _LockOrder();
    box.posix = posix;
    final result = await box.run(AssessmentOperation.recover);
    expect(result.exitCode, 0, reason: '${diagnosticCodes(result)}');
    expect(posix.removedCandidates, isNotEmpty);
    expect(posix.removedWithoutLock, isEmpty);
  });
}

/// Las llamadas POSIX reales, anotando si cada candidato se retiró con un
/// lock tomado.
final class _LockOrder extends NativePosix {
  _LockOrder() : super(currentPosixAbi());

  final _held = <int>{};
  final removedCandidates = <String>[];
  final removedWithoutLock = <String>[];

  @override
  bool tryLock(int fd) {
    final taken = super.tryLock(fd);
    if (taken) _held.add(fd);
    return taken;
  }

  @override
  void unlock(int fd) {
    _held.remove(fd);
    super.unlock(fd);
  }

  @override
  void unlinkat(int dirFd, String name) {
    if (name == 'candidate.json') {
      removedCandidates.add(name);
      if (_held.isEmpty) removedWithoutLock.add(name);
    }
    super.unlinkat(dirFd, name);
  }
}
