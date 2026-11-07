import 'dart:io';

import 'package:cli/src/basis/basis_canonical.dart';
import 'package:cli/src/basis/basis_preconditions.dart';
import 'package:cli/src/basis/basis_preflight.dart';
import 'package:cli/src/basis/basis_sources.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';

final _limits = BasisLimits.forProfile(BasisProfile.standard);

void main() {
  late ServiceSandbox box;
  setUp(() => box = ServiceSandbox.create());
  tearDown(() => box.dispose());

  Future<BasisEnvironment> environment() async {
    final store = await SecureContextStore.open(box.root);
    try {
      return await readBasisEnvironment(store);
    } finally {
      await store.close();
    }
  }

  Future<void> init() async {
    box.project();
    expect((await box.run(ContextOperation.init)).exitCode, 0);
  }

  test('absent_assess_does_not_block_base', () async {
    await init();
    final env = await environment();
    expect(env.context, BasisIntegrity.valid);
    expect(isUuidV4(env.projectId!), isTrue);
    expect(
      env.contextDigest,
      bytesDigest(File(box.path('shipflow/project.json')).readAsBytesSync()),
    );
    expect(env.assessmentRecoveryPending, isFalse);
    expect(env.contextRecoveryPending, isFalse);
  });

  test('an absent or invalid context is reported, never invented', () async {
    expect((await environment()).context, BasisIntegrity.absent);
    box.file('shipflow/project.json', '{"roto":');
    final env = await environment();
    expect(env.context, BasisIntegrity.invalid);
    expect(env.projectId, isNull);
  });

  test('same_project_refresh_does_not_revoke_rule', () async {
    await init();
    final before = await environment();
    box.file('pubspec.yaml', 'name: app\n# cambio\n');
    expect((await box.run(ContextOperation.refresh)).exitCode, 0);
    final after = await environment();
    expect(after.projectId, before.projectId);
    expect(after.contextDigest, isNot(before.contextDigest));
  });

  test('a pending init transaction is visible', () async {
    await init();
    box.file('pubspec.yaml', 'name: app\n# cambio\n');
    await expectLater(
      box.run(ContextOperation.refresh, wrap: (real) => CrashingStore(real, 1)),
      throwsA(isA<SimulatedCrash>()),
    );
    expect((await environment()).contextRecoveryPending, isTrue);
  });

  test('reading the environment never writes the tree', () async {
    await init();
    final before = box.snapshot();
    await environment();
    expect(box.snapshot(), before);
  });

  group('preconditions', () {
    late BasisEnvironment env;
    late List<BasisSourceReading> reads;
    setUp(() async {
      await init();
      box.file('docs/a.md', 'a\n');
      env = await environment();
      reads = [
        BasisSourceReading(
          path: 'docs/a.md',
          digest: bytesDigest(File(box.path('docs/a.md')).readAsBytesSync()),
        ),
      ];
    });

    Future<BasisDiagnostic?> check({
      String? current,
      String? expected,
      String? context,
    }) async {
      final store = await SecureContextStore.open(box.root);
      try {
        return await checkBasisPreconditions(
          BasisPreconditions(
            state: await readBasisEnvironment(store),
            projectId: env.projectId!,
            currentBasisDigest: current,
            expectedBasisDigest: expected,
            contextProjectDigest: context ?? env.contextDigest!,
            sourceReads: reads,
            reader: BasisSourceReader(store),
            limits: _limits,
          ),
        );
      } finally {
        await store.close();
      }
    }

    test('unchanged base, context and sources pass', () async {
      expect(await check(), isNull);
    });

    test('another basis digest is base_changed', () async {
      final failure = await check(current: 'sha256:${'1' * 64}');
      expect(failure?.code, 'base_changed');
      expect(failure?.path, 'shipflow/basis.json');
    });

    test('another context digest is base_changed', () async {
      final failure = await check(context: 'sha256:${'2' * 64}');
      expect(failure?.code, 'base_changed');
      expect(failure?.path, 'shipflow/project.json');
    });

    test('a source changed after preparing is source_changed', () async {
      box.file('docs/a.md', 'b\n');
      final failure = await check();
      expect(failure?.code, 'source_changed');
      expect(failure?.path, 'docs/a.md');
      File(box.path('docs/a.md')).deleteSync();
      expect((await check())?.code, 'source_changed');
    });
  });
}
