import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

Matcher exceeds(ReportLimitDimension dimension) => throwsA(
  isA<ReportLimitExceeded>().having((e) => e.dimension, 'dimension', dimension),
);

void main() {
  group('los dos perfiles', () {
    test('standard es el de omisión', () {
      const limits = ReportLimits();
      expect(limits.maxDerivedItems, 16384);
      expect(limits.maxDerivedTextBytes, 1048576);
      expect(limits.maxReportJsonBytes, 2097152);
    });

    test('extended amplía las tres cotas juntas', () {
      const limits = ReportLimits.extended();
      expect(limits.maxDerivedItems, 18432);
      expect(limits.maxDerivedTextBytes, 1835008);
      expect(limits.maxReportJsonBytes, 2359296);
    });
  });

  for (final (name, limits) in [
    ('standard', const ReportLimits()),
    ('extended', const ReportLimits.extended()),
  ]) {
    group('admitDerivedUsage en $name', () {
      test('admite exactamente el máximo de elementos', () {
        final used = admitDerivedUsage(
          const DerivedUsage(),
          limits,
          items: limits.maxDerivedItems,
          textBytes: 0,
        );
        expect(used.items, limits.maxDerivedItems);
        expect(
          () => admitDerivedUsage(used, limits, items: 1, textBytes: 0),
          exceeds(ReportLimitDimension.items),
        );
      });

      test('admite exactamente el máximo de texto', () {
        final used = admitDerivedUsage(
          const DerivedUsage(),
          limits,
          items: 0,
          textBytes: limits.maxDerivedTextBytes,
        );
        expect(used.textBytes, limits.maxDerivedTextBytes);
        expect(
          () => admitDerivedUsage(used, limits, items: 0, textBytes: 1),
          exceeds(ReportLimitDimension.textBytes),
        );
      });

      test('si ambos se exceden a la vez, elementos va primero', () {
        final full = DerivedUsage(
          items: limits.maxDerivedItems,
          textBytes: limits.maxDerivedTextBytes,
        );
        expect(
          () => admitDerivedUsage(full, limits, items: 1, textBytes: 1),
          exceeds(ReportLimitDimension.items),
        );
      });
    });
  }

  test('lo que se rechaza no cambia lo ya usado', () {
    const used = DerivedUsage(items: 3, textBytes: 5);
    expect(
      () => admitDerivedUsage(
        used,
        const ReportLimits(maxDerivedItems: 3),
        items: 1,
        textBytes: 0,
      ),
      exceeds(ReportLimitDimension.items),
    );
    expect([used.items, used.textBytes], [3, 5]);
  });

  test('un cobro negativo es un error de programación', () {
    for (final (items, textBytes) in [(-1, 0), (0, -1)]) {
      expect(
        () => admitDerivedUsage(
          const DerivedUsage(),
          const ReportLimits(),
          items: items,
          textBytes: textBytes,
        ),
        throwsArgumentError,
      );
    }
  });

  group('reportLimitReached', () {
    const repository = RepositoryContext(
      status: RepositoryStatus.detected,
      root: '/repo',
      relation: RepositoryRelation.ancestor,
    );

    RecognitionReport reached(ReportLimitDimension dimension, bool extended) =>
        reportLimitReached(
          requestedRoot: '/alias',
          resolvedRoot: '/real',
          repository: repository,
          dimension: dimension,
          extended: extended,
        );

    test('conserva raíces y Git y descarta el inventario', () {
      final report = reached(ReportLimitDimension.items, false);
      expect(report.status, RecognitionStatus.ambiguous);
      expect(report.requestedRoot, '/alias');
      expect(report.resolvedRoot, '/real');
      expect(report.repository.toJson(), repository.toJson());
      expect(report.candidates, isEmpty);
      expect(report.units, isEmpty);
      expect(report.evidence, isEmpty);
      expect(report.conflicts, isEmpty);
      expect(report.proposal.eligible, isFalse);
      expect(report.proposal.actions, isEmpty);
      expect(report.effects.toJson(), RecognitionEffects.none.toJson());
      final limitation = report.limitations.single;
      expect(limitation.code, 'report_limit_reached');
      expect(limitation.blocking, isTrue);
      expect(limitation.path, isNull);
    });

    for (final (dimension, extended, message) in [
      (
        ReportLimitDimension.items,
        false,
        'El reconocimiento alcanzó el límite de elementos del reporte del '
            'perfil normal; no se publica un inventario parcial. Puedes '
            'repetir con shipflow init --dry-run --report-budget=extended. El '
            'perfil ampliado puede consumir más recursos.',
      ),
      (
        ReportLimitDimension.textBytes,
        true,
        'El reconocimiento alcanzó el límite de texto del reporte del perfil '
            'ampliado; no se publica un inventario parcial. Se alcanzó el '
            'máximo disponible en esta versión. Inspecciona una raíz '
            'tecnológica más acotada; esto cambia el alcance de la inspección.',
      ),
      (
        ReportLimitDimension.jsonBytes,
        false,
        'El reconocimiento alcanzó el límite de tamaño JSON del reporte del '
            'perfil normal; no se publica un inventario parcial. Puedes '
            'repetir con shipflow init --dry-run --report-budget=extended. El '
            'perfil ampliado puede consumir más recursos.',
      ),
    ]) {
      test('explica $dimension en ${extended ? 'ampliado' : 'normal'}', () {
        expect(
          reached(dimension, extended).limitations.single.message,
          message,
        );
      });
    }
  });

  group('assembleRecognition vuelve a contar con un contador propio', () {
    // Una evidencia, un candidato y una unidad que la citan, y al ser
    // reconocido las dos acciones de la propuesta: 7 elementos.
    final contribution = RecognitionContribution(
      candidates: [
        StackCandidate(
          id: 'c',
          displayName: 'C',
          pluginId: 'p',
          evidenceIds: const ['e0001'],
        ),
      ],
      units: [
        ProjectUnit(
          id: 'u0001',
          name: 'añ',
          kind: 'k',
          path: '.',
          evidenceIds: const ['e0001'],
        ),
      ],
      evidence: const [
        RecognitionEvidence(
          id: 'e0001',
          kind: 'kind',
          path: 'manifest',
          value: 'añ',
          fingerprint: 'sha256:x',
        ),
      ],
      conflicts: const [],
      limitations: const [],
    );
    final textBytes = [
      'e0001', 'kind', 'manifest', 'añ', 'sha256:x', // evidencia
      'c', 'C', 'p', 'e0001', // candidato y su referencia
      'u0001', 'añ', 'k', '.', 'e0001', // unidad y su referencia
      recordProjectIdentity.code, recordProjectIdentity.description,
      enableStackPlugin.code, enableStackPlugin.description,
      'p', // pluginIds de la propuesta
    ].fold(0, (sum, text) => sum + utf8.encode(text).length);

    RecognitionReport assemble(ReportLimits limits) => assembleRecognition(
      requestedRoot: '/r',
      resolvedRoot: '/r',
      repository: const RepositoryContext(
        status: RepositoryStatus.absent,
        root: null,
        relation: RepositoryRelation.none,
      ),
      contributions: [contribution],
      limits: limits,
    );

    test('7 elementos caben y 6 no', () {
      expect(
        assemble(const ReportLimits(maxDerivedItems: 7)).status,
        RecognitionStatus.recognized,
      );
      expect(
        () => assemble(const ReportLimits(maxDerivedItems: 6)),
        exceeds(ReportLimitDimension.items),
      );
    });

    test('su texto exacto cabe y un byte menos no', () {
      assemble(ReportLimits(maxDerivedTextBytes: textBytes));
      expect(
        () => assemble(ReportLimits(maxDerivedTextBytes: textBytes - 1)),
        exceeds(ReportLimitDimension.textBytes),
      );
    });
  });

  test('utf8Length coincide con el encoder, incluso fuera del BMP', () {
    for (final text in ['', 'abc', 'ñandú', '漢字', '😀x', 'a\u{D800}b']) {
      expect(utf8Length(text), utf8.encode(text).length, reason: text);
    }
  });
}
