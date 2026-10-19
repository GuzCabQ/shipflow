import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

const _huge = 1 << 30;

/// El menor valor en `1..high` que [fits] acepta; [fits] es monótona.
Future<int> smallest(Future<bool> Function(int limit) fits, int high) async {
  var (low, top) = (1, high);
  while (low < top) {
    final middle = (low + top) ~/ 2;
    if (await fits(middle)) {
      top = middle;
    } else {
      low = middle + 1;
    }
  }
  return low;
}

Future<bool> accepts(Future<Object?> Function() run) async {
  try {
    await run();
    return true;
  } on ReportLimitExceeded {
    return false;
  }
}

void main() {
  final sandbox = ScanSandbox()..register();

  Future<RecognitionContribution> produce(ReportLimits limits) =>
      recognizeDartProject(
        sandbox.root,
        reportLimits: limits,
        contextSources: candidateCatalogue,
      );

  RecognitionReport assemble(RecognitionContribution c, ReportLimits limits) =>
      assembleRecognition(
        requestedRoot: sandbox.root.path,
        resolvedRoot: sandbox.root.path,
        repository: const RepositoryContext(
          status: RepositoryStatus.absent,
          root: null,
          relation: RepositoryRelation.none,
        ),
        contributions: [c],
        limits: limits,
      );

  /// Lo que el ensamblador agrega a lo producido: el alcance y, si es
  /// elegible, las acciones de la propuesta y su plugin.
  (int, int) assemblyExtra(RecognitionReport report) => (
    report.proposal.actions.length,
    utf8Length(report.recognitionScope) +
        [
          for (final a in report.proposal.actions) ...[a.code, a.description],
          ...report.proposal.pluginIds,
        ].fold(0, (sum, t) => sum + utf8Length(t)),
  );

  /// El menor elemento y el menor texto que [run] acepta.
  Future<(int, int)> frontier(
    Future<Object?> Function(ReportLimits limits) run,
  ) async => (
    await smallest(
      (n) => accepts(() => run(ReportLimits(maxDerivedItems: n))),
      4096,
    ),
    await smallest(
      (n) => accepts(() => run(ReportLimits(maxDerivedTextBytes: n))),
      1 << 20,
    ),
  );

  Future<void> expectParity() async {
    final (producedItems, producedText) = await frontier(produce);
    final contribution = await produce(
      const ReportLimits(maxDerivedItems: _huge, maxDerivedTextBytes: _huge),
    );
    final (extraItems, extraText) = assemblyExtra(
      assemble(contribution, const ReportLimits()),
    );
    final (assembledItems, assembledText) = await frontier(
      (limits) async => assemble(contribution, limits),
    );
    expect(assembledItems, producedItems + extraItems);
    expect(assembledText, producedText + extraText);
  }

  test(
    'an eligible report with every new list recounts what was charged',
    () async {
      sandbox.place('pubspec.yaml', '''
name: app
description: "Una app ñandú"
workspace:
  - packages/b
dependencies:
  flutter:
    sdk: flutter
  b: {path: packages/b}
flutter:
  assets:
    - assets/images/
''');
      sandbox.place('packages/b/pubspec.yaml', 'name: b\n');
      sandbox.place('README.md', 'x');
      sandbox.directory('assets/images');
      sandbox.directory('ios/Flutter/ephemeral');
      sandbox.directory('.git');
      final report = assemble(
        await produce(const ReportLimits()),
        const ReportLimits(),
      );
      expect(report.proposal.eligible, isTrue);
      expect(report.omissions, hasLength(3));
      await expectParity();
    },
  );

  test('a blocked report with every diagnostic recounts too', () async {
    sandbox.place('pubspec.yaml', '''
name: app
description: [no, texto]
dependencies:
  x: {path: packages/b}
  c: {path: ../c}
  d: {path: vendor/d}
''');
    sandbox.place('packages/b/pubspec.yaml', 'name: b\n');
    Link('${sandbox.root.path}/AGENTS.md').createSync('README.md');
    final report = assemble(
      await produce(const ReportLimits()),
      const ReportLimits(),
    );
    expect(report.proposal.eligible, isFalse);
    expect(report.conflicts.single.code, 'local_dependency_name_mismatch');
    await expectParity();
  });
}
