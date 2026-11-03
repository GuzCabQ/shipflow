@Timeout(Duration(minutes: 3))
library;

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/context/native/posix_api.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';

/// Regresión de REV-V3-004 R10b: con el almacén nativo real, un EIO en la
/// confirmación posterior al rename del documento no borra que se publicó,
/// aunque la relectura también falle; uno antes del rename nunca declara
/// publicación.
void main() {
  late AssessServiceBox box;
  setUp(() async {
    box = await AssessServiceBox.initialized();
    await box.run(AssessmentOperation.observe);
  });
  tearDown(() => box.dispose());

  /// Deja preparada la segunda revisión para [operation].
  Future<void> prepare(AssessmentOperation operation) async {
    if (operation == AssessmentOperation.recover) {
      await interruptPublication(box);
    } else {
      box.box.file('lib/other.dart', "import 'main.dart';\n// r2\n");
    }
  }

  for (final operation in [
    AssessmentOperation.observe,
    AssessmentOperation.recover,
  ]) {
    for (final rereadFails in [false, true]) {
      test('$operation: fsync after the rename fails, reread fails: '
          '$rereadFails', () async {
        await prepare(operation);
        final posix = _EioAroundRename(
          afterRename: true,
          rereadFails: rereadFails,
        );
        box.posix = posix;
        final result = await box.run(operation);
        expect(posix.renamed, isTrue);
        expect(decodeAssessment(box.document.readAsBytesSync()).revision, 2);
        expect(result.exitCode, 74);
        expect(result.effects.published, isTrue);
        expect(result.effects.replaced, contains(assessmentPath));
      });
    }

    test('$operation: a failure before the rename publishes nothing', () async {
      await prepare(operation);
      final before = box.document.readAsBytesSync();
      final posix = _EioAroundRename(afterRename: false, rereadFails: false);
      box.posix = posix;
      final result = await box.run(operation);
      expect(posix.renamed, isFalse);
      expect(box.document.readAsBytesSync(), before);
      expect(result.exitCode, 74);
      expect(result.effects.published, isFalse);
      expect(result.effects.replaced, isEmpty);
    });
  }
}

/// Las llamadas POSIX reales, con un EIO inyectado una sola vez: en el
/// fsync del temporal de `assessment.json` (antes del rename) o en el
/// fsync de su directorio justo después del rename; y, si [rereadFails],
/// en cada apertura posterior del documento.
final class _EioAroundRename extends NativePosix {
  _EioAroundRename({required this.afterRename, required this.rereadFails})
    : super(currentPosixAbi());

  static const _eio = PosixError(PosixErrorKind.other, 5);

  final bool afterRename;
  final bool rereadFails;
  var renamed = false;
  var _armed = true;
  int? _target;

  @override
  int createExclusive(int dirFd, String name, int mode) {
    final fd = super.createExclusive(dirFd, name, mode);
    if (!afterRename && name.startsWith('.assessment.json.')) _target = fd;
    return fd;
  }

  @override
  void renameat(int fromDir, String from, int toDir, String to) {
    super.renameat(fromDir, from, toDir, to);
    if (to != 'assessment.json') return;
    renamed = true;
    if (afterRename) _target = toDir;
  }

  @override
  void fsync(int fd) {
    if (_armed && fd == _target) {
      _armed = false;
      throw _eio;
    }
    super.fsync(fd);
  }

  @override
  int openRead(int dirFd, String name) {
    if (renamed && rereadFails && name == 'assessment.json') throw _eio;
    return super.openRead(dirFd, name);
  }
}
