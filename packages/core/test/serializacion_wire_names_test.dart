import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('serializes every status with its specified wire name', () {
    test('estado del reconocimiento', () {
      expect(RecognitionStatus.values.map((s) => s.toWireName()), [
        'recognized',
        'ambiguous',
        'unsupported',
        'invalid_root',
      ]);
      for (final status in RecognitionStatus.values) {
        expect(RecognitionStatus.fromWireName(status.toWireName()), status);
      }
    });

    test('estado y relación del repositorio', () {
      expect(RepositoryStatus.values.map((s) => s.toWireName()), [
        'detected',
        'absent',
        'indeterminate',
      ]);
      expect(RepositoryRelation.values.map((r) => r.toWireName()), [
        'same',
        'ancestor',
        'none',
      ]);
    });

    test('un nombre desconocido se rechaza', () {
      expect(
        () => RecognitionStatus.fromWireName('invalidRoot'),
        throwsFormatException,
      );
      expect(() => RepositoryStatus.fromWireName('x'), throwsFormatException);
      expect(() => RepositoryRelation.fromWireName('x'), throwsFormatException);
    });
  });
}
