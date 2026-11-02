import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/src/assessment/directive_extractor.dart';
import 'package:plugin_dart/src/assessment/parser_worker.dart';
import 'package:test/test.dart';

import 'assessment_support.dart';

void main() {
  final box = AssessSandbox()..register();
  final standard = AssessmentLimits.forProfile(AssessmentProfile.standard);

  AssessmentLimits limited({
    int? files,
    int? sourceBytes,
    int? claims,
    int? entries,
    int? depth,
  }) => AssessmentLimits(
    profile: standard.profile,
    maxEntries: entries ?? standard.maxEntries,
    maxDepth: depth ?? standard.maxDepth,
    maxSourceFiles: files ?? standard.maxSourceFiles,
    maxSourceBytes: sourceBytes ?? standard.maxSourceBytes,
    maxTotalSourceBytes: standard.maxTotalSourceBytes,
    maxClaims: claims ?? standard.maxClaims,
    maxSnapshotBytes: standard.maxSnapshotBytes,
    maxObservationMillis: standard.maxObservationMillis,
    maxParseMillis: standard.maxParseMillis,
  );

  void sources() {
    box.package('.', 'app');
    box.place('lib/a.dart', "import 'b.dart';\nimport 'c.dart';\n");
    box.place('lib/b.dart', 'class B {}\n');
    box.place('lib/c.dart', 'class C {}\n');
  }

  test('sources over the file budget are listed but not read', () async {
    sources();
    final o = await box.observe(limits: limited(files: 2));
    final c = inputAt(o, 'lib/c.dart', AssessmentInputKind.source);
    expect((c.state, c.reason), (AssessmentInputState.limit, 'source_budget'));
    expect(fileAt(o, 'lib/c.dart').parseState, AssessmentParseState.notRun);
    expect(o.inventoryComplete, isTrue);
  });

  test('a source over its byte limit is not read nor truncated', () async {
    sources();
    final o = await box.observe(limits: limited(sourceBytes: 12));
    final a = inputAt(o, 'lib/a.dart', AssessmentInputKind.source);
    expect(
      (a.state, a.reason),
      (AssessmentInputState.limit, 'source_too_large'),
    );
  });

  test('claims are admitted whole per file or not at all', () async {
    sources();
    final o = await box.observe(limits: limited(claims: 1));
    expect(fileAt(o, 'lib/a.dart').parseState, AssessmentParseState.notRun);
    expect(claimsFromIds(o, 'lib/a.dart'), isEmpty);
    expect(diagnosticCodes(o), contains('claims_budget'));
  });

  test('an entry budget cut leaves the inventory incomplete', () async {
    sources();
    final o = await box.observe(limits: limited(entries: 2));
    expect(o.inventoryComplete, isFalse);
    expect(
      o.inputs.where((i) => i.state == AssessmentInputState.limit),
      isNotEmpty,
    );
  });

  test('a directory beyond the depth limit is not listed', () async {
    sources();
    box.place('lib/x/y/z.dart', 'class Z {}\n');
    final o = await box.observe(limits: limited(depth: 2));
    final deep = inputAt(o, 'lib/x/y', AssessmentInputKind.directory);
    expect(
      (deep.state, deep.reason),
      (AssessmentInputState.limit, 'depth_budget'),
    );
    expect(o.inventoryComplete, isFalse);
  });

  test('a parse deadline leaves the file not run, never empty', () async {
    sources();
    final o = await box.observe(
      parser: (content, path, deadline) async => path == 'lib/a.dart'
          ? const ParseTimedOut()
          : extractDirectives(content, path),
    );
    expect(fileAt(o, 'lib/a.dart').parseState, AssessmentParseState.notRun);
    expect(diagnosticCodes(o), contains('parse_deadline'));
    expect(fileAt(o, 'lib/b.dart').parseState, AssessmentParseState.parsed);
  });

  test('the isolate worker is killed at its deadline and replaced', () async {
    final worker = IsolateDirectiveParser();
    addTearDown(worker.close);
    final source = "import 'a.dart';\n" * 2000;
    expect(
      await worker(source, 'lib/a.dart', Duration.zero),
      isA<ParseTimedOut>(),
    );
    final next = await worker(
      "import 'b.dart';\n",
      'lib/b.dart',
      const Duration(seconds: 30),
    );
    expect((next as ParsedDirectives).directives.single.uri, 'b.dart');
  });

  test('invalid UTF-8 is a failed parse, not an empty file', () async {
    sources();
    File('${box.root.path}/lib/b.dart').writeAsBytesSync([0x63, 0xff, 0xfe]);
    final o = await box.observe();
    expect(fileAt(o, 'lib/b.dart').parseState, AssessmentParseState.failed);
    expect(diagnosticCodes(o), contains('parse_failed'));
  });
}

List<AssessmentClaim> claimsFromIds(AssessmentObservation o, String path) {
  final id = fileAt(o, path).id;
  return [
    for (final c in o.claims)
      if (c.sourceFileId == id) c,
  ];
}
