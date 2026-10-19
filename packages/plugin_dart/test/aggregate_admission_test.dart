import 'dart:collection';

import 'package:core/core.dart';
import 'package:plugin_dart/src/derived_observation_budget.dart';
import 'package:plugin_dart/src/evidence_draft.dart';
import 'package:plugin_dart/src/toolchain_observer.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

/// Una lista que cuenta cada lectura de sus elementos.
final class CountingList<T> extends ListBase<T> {
  CountingList(this._values);

  final List<T> _values;
  var reads = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('sólo lectura');

  @override
  T operator [](int index) {
    reads++;
    return _values[index];
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('sólo lectura');
}

ConstraintEvidence constraint(int i) => ConstraintEvidence(
  EvidenceDraft(
    kind: 'manifest.sdk_constraint',
    path: 'packages/p$i/pubspec.yaml',
    value: '${i % 2 + 1}.0.0',
    fingerprint: 'sha256:${'0' * 64}',
  ),
  Version(i % 2 + 1, 0, 0),
);

ToolchainMarker marker(int i) => ToolchainMarker(
  EvidenceDraft(
    kind: 'toolchain.fvm',
    path: 'm$i',
    value: '$i.0.0',
    fingerprint: 'sha256:${'0' * 64}',
  ),
  Version(i, 0, 0),
);

// Saber si las restricciones son disjuntas exige leerlas todas una vez. Lo
// que sigue —partes del mensaje y referencias— se admite de a una antes de
// construirse: sin presupuesto no se lee ninguna más. Expandirlas antes de
// admitir las leería todas otra vez (o dos).
void main() {
  test('un agregado de restricciones disjuntas se admite antes de '
      'expandirse', () {
    final constraints = CountingList([
      for (var i = 0; i < 4000; i++) constraint(i),
    ]);
    expect(
      () => toolchainConflicts(
        markers: const [],
        flutterConstraints: const [],
        sdkConstraints: constraints,
        budget: DerivedObservationBudget(
          const ReportLimits(maxDerivedItems: 0, maxDerivedTextBytes: 0),
        ),
      ),
      throwsA(isA<ReportLimitExceeded>()),
    );
    expect(constraints.reads, lessThanOrEqualTo(4000));
  });

  test('con presupuesto para k referencias se leen a lo sumo k + 1 más', () {
    final constraints = CountingList([
      for (var i = 0; i < 4000; i++) constraint(i),
    ]);
    expect(
      () => toolchainConflicts(
        markers: const [],
        flutterConstraints: const [],
        sdkConstraints: constraints,
        budget: DerivedObservationBudget(
          const ReportLimits(maxDerivedItems: 11),
        ),
      ),
      throwsA(
        isA<ReportLimitExceeded>().having(
          (e) => e.dimension,
          'dimension',
          ReportLimitDimension.items,
        ),
      ),
    );
    expect(constraints.reads, lessThanOrEqualTo(4000 + 11));
  });

  test('los marcadores que discrepan también se admiten de a uno', () {
    final markers = CountingList([for (var i = 1; i <= 3000; i++) marker(i)]);
    expect(
      () => toolchainConflicts(
        markers: markers,
        flutterConstraints: const [],
        sdkConstraints: const [],
        budget: DerivedObservationBudget(
          const ReportLimits(maxDerivedItems: 0),
        ),
      ),
      throwsA(isA<ReportLimitExceeded>()),
    );
    // Una lectura por marcador para saber si discrepan; ninguna más.
    expect(markers.reads, lessThanOrEqualTo(3000));
  });
}
