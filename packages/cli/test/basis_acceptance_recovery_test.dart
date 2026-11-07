@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/basis/basis_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'init_process_support.dart';
import 'support/basis_process_support.dart';
import 'support/basis_service_support.dart';
import 'support/context_service_support.dart';

void main() {
  final process = InitProcessSandbox()..register();
  late BasisWalk walk;
  setUp(() async {
    dartPackage.files.forEach(process.place);
    expect((await process.run(['init', '--json'])).exitCode, 0);
    walk = BasisWalk(process);
  });

  /// La misma raíz desde el servicio en proceso, para morir en una
  /// escritura exacta de la aceptación.
  BasisBox inProcess() =>
      BasisBox.on(ServiceSandbox.at(process.root.parent, process.root));

  Future<RunResult> piped(List<String> arguments, String stdin) async {
    final started = await Process.start(
      process.binary,
      arguments,
      workingDirectory: process.root.path,
      environment: {'HOME': process.home.path, 'TMPDIR': process.temp.path},
      includeParentEnvironment: false,
    );
    started.stdin.add(utf8.encode(stdin));
    await started.stdin.close();
    final out = await started.stdout.transform(utf8.decoder).join();
    final err = await started.stderr.transform(utf8.decoder).join();
    return RunResult(await started.exitCode, out, err);
  }

  test(
    'without a terminal the guide asks nothing and writes nothing',
    () async {
      final before = treeSnapshot(process.root);
      final human = await walk.raw(['bootstrap']);
      expect(human.exitCode, 65);
      expect(human.stdout, isNot(contains('?\n>')));
      final json = await walk.bootstrap([]);
      expect(json.outcome, BasisOutcome.choiceRequired);
      expect(codesOf(json), ['choice_required']);
      final answered = await piped(['bootstrap'], 'aceptar\n');
      expect(answered.exitCode, 65);
      expect(treeSnapshot(process.root), before);
    },
  );

  test('a proposal piped as JSON is prepared, never accepted', () async {
    final input = utf8.decode(
      encodeBasisInput(walk.inputOf([create('regla', ruleOf())])),
    );
    final run = await piped(['bootstrap', '--input', '-', '--json'], input);
    final prepared = walk.decoded(run);
    expect(prepared.outcome, BasisOutcome.draftPrepared);
    expect(walk.basis.existsSync(), isFalse);
    final accepted = await walk.bootstrap(['--accept', prepared.draftDigest!]);
    expect(accepted.published, isTrue);
  });

  test('S1: accepting over a changed source publishes nothing', () async {
    final prepared = await walk.prepare(ruleWithSource('docs/politica.md'));
    final source = File('${process.root.path}/docs/politica.md');
    source.writeAsStringSync('Otra política.\n');
    final accepted = await walk.bootstrap(['--accept', prepared.draftDigest!]);
    expect(accepted.exitCode, 75);
    expect(codesOf(accepted), ['source_changed']);
    expect(walk.basis.existsSync(), isFalse);
    final draft = await walk.bootstrap(['--show', '--draft']);
    expect(draft.draftDigest, prepared.draftDigest);
  });

  test(
    'S2: a crash before the rename is finished by another process',
    () async {
      final digest = await interruptBasis(inProcess(), [
        create('regla', ruleOf()),
      ]);
      expect(walk.basis.existsSync(), isFalse);
      final blocked = await walk.prepare([create('otra', pendingOf())]);
      expect(blocked.exitCode, 75);
      final recovered = await walk.bootstrap(['--recover']);
      expect(
        (recovered.outcome, recovered.published),
        (BasisOutcome.recovered, true),
      );
      expect(walk.document.events.single.draftDigest, digest);
      final again = await walk.bootstrap(['--recover']);
      expect(again.outcome, BasisOutcome.noChanges);
    },
  );

  test('S2: a crash after the rename only cleans up natively', () async {
    final box = inProcess();
    final prepared = await box.prepare(box.input([create('regla', ruleOf())]));
    box.storeWrap = (real) => CrashingStore(real, 3);
    await expectLater(
      box.accept(prepared.draftDigest!),
      throwsA(isA<SimulatedCrash>()),
    );
    final bytes = walk.basis.readAsBytesSync();
    final recovered = await walk.bootstrap(['--recover']);
    expect(recovered.outcome, BasisOutcome.recovered);
    expect(walk.basis.readAsBytesSync(), bytes);
    expect(walk.document.revision, 1);
    final shown = await walk.bootstrap(['--show']);
    expect(shown.exitCode, 0);
    expect(shown.storageIntegrity.transaction, BasisIntegrity.absent);
  });
}
