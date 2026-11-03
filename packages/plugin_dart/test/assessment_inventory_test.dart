import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'assessment_support.dart';

void main() {
  final box = AssessSandbox()..register();

  void twoUnits() {
    box.package('.', 'app');
    box.package('packages/widgets', 'widgets');
    box.place('lib/main.dart', "import 'package:app/a.dart';\n");
    box.place('lib/a.dart', 'class A {}\n');
    box.place('packages/widgets/lib/w.dart', 'class W {}\n');
  }

  test('each file is scanned once and owned by its deepest unit', () async {
    twoUnits();
    final observation = await box.observe();
    final paths = [for (final f in observation.files) f.path];
    expect(paths.toSet(), hasLength(paths.length));
    final widgets = observation.units.singleWhere((u) => u.label == 'widgets');
    expect(
      fileAt(observation, 'packages/widgets/lib/w.dart').unitId,
      widgets.id,
    );
    expect(
      observation.units.map((u) => u.path),
      containsAll(['.', 'packages/widgets']),
    );
  });

  test('tests are classified by place and suffix, not executed', () async {
    twoUnits();
    box.place('test/a_test.dart', 'void main() {}\n');
    box.place('test/helper.dart', 'void ayuda() {}\n');
    box.place('integration_test/flow_test.dart', 'void main() {}\n');
    box.place('lib/x_test.dart', 'void x() {}\n');
    final observation = await box.observe();
    AssessmentFileRole role(String path) => fileAt(observation, path).role;
    expect(role('test/a_test.dart'), AssessmentFileRole.test);
    expect(role('integration_test/flow_test.dart'), AssessmentFileRole.test);
    expect(role('test/helper.dart'), AssessmentFileRole.source);
    expect(role('lib/x_test.dart'), AssessmentFileRole.source);
  });

  test('excluded trees are recorded and never walked', () async {
    twoUnits();
    box.place('build/gen.dart', 'class G {}\n');
    box.place('.dart_tool/x.dart', 'class X {}\n');
    final observation = await box.observe();
    final excluded = inputAt(
      observation,
      'build',
      AssessmentInputKind.excluded,
    );
    expect(
      (excluded.state, excluded.reason),
      (AssessmentInputState.excluded, 'baseline_exclusion'),
    );
    expect(
      observation.files.map((f) => f.path),
      isNot(contains('build/gen.dart')),
    );
    expect(
      observation.inputs.map((i) => i.path),
      isNot(contains('.dart_tool/x.dart')),
    );
  });

  test('links and special files are not followed nor opened', () async {
    // V2 no reconoce un universo con enlaces; aparecen después de init.
    twoUnits();
    final context = await box.context();
    Link('${box.root.path}/lib/enlace.dart').createSync('a.dart');
    await Process.run('mkfifo', ['${box.root.path}/lib/tubo.dart']);
    final observation = await observeDartSources(
      box.root,
      context,
      AssessmentLimits.forProfile(AssessmentProfile.standard),
    );
    final files = observation.files.map((f) => f.path);
    expect(files, isNot(contains('lib/enlace.dart')));
    expect(files, isNot(contains('lib/tubo.dart')));
    expect(
      diagnosticCodes(observation),
      containsAll(['symlink_not_followed', 'special_file_skipped']),
    );
  });

  test(
    'generated files present are observed and never declared editable',
    () async {
      twoUnits();
      box.place('lib/a.g.dart', "part of 'a.dart';\n");
      final observation = await box.observe();
      expect(fileAt(observation, 'lib/a.g.dart').editable, 'unknown');
    },
  );

  test('recognition sources are sealed, including new ones', () async {
    twoUnits();
    box.place('tools/pubspec.yaml', 'name: tools\n');
    final observation = await box.observe();
    for (final path in [
      'pubspec.yaml',
      'packages/widgets/pubspec.yaml',
      'tools/pubspec.yaml',
    ]) {
      final input = inputAt(
        observation,
        path,
        AssessmentInputKind.recognitionSource,
      );
      expect(input.state, AssessmentInputState.read);
      expect(input.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
  });

  test('the shared inventory sees additions without any parser', () async {
    twoUnits();
    final context = await box.context();
    final limits = AssessmentLimits.forProfile(AssessmentProfile.standard);
    final first = await observeDartInputs(box.root, context, limits);
    final observed = await box.observe();
    expect(
      [for (final i in first) i.toJson()],
      [for (final i in observed.inputs) i.toJson()],
    );
    box.place('lib/nuevo.dart', 'class N {}\n');
    final second = await observeDartInputs(box.root, context, limits);
    expect(second.map((i) => i.path), contains('lib/nuevo.dart'));
    expect(
      inputsByPath(second)['lib']!.sha256,
      isNot(inputsByPath(first)['lib']!.sha256),
    );
  });

  test(
    'S2: an unreadable source with a reference is not zero references',
    () async {
      twoUnits();
      Process.runSync('chmod', ['000', '${box.root.path}/lib/main.dart']);
      final observation = await box.observe();
      final input = inputAt(
        observation,
        'lib/main.dart',
        AssessmentInputKind.source,
      );
      expect(
        (input.state, input.reason),
        (AssessmentInputState.unreadable, 'source_unreadable'),
      );
      expect(
        fileAt(observation, 'lib/main.dart').parseState,
        AssessmentParseState.notRun,
      );
      expect(diagnosticCodes(observation), contains('source_unreadable'));
    },
  );
}

Map<String, AssessmentInput> inputsByPath(List<AssessmentInput> inputs) => {
  for (final i in inputs)
    if (i.kind == AssessmentInputKind.directory) i.path: i,
};
