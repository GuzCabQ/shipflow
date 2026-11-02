import 'package:plugin_dart/src/assessment/directive_extractor.dart';
import 'package:test/test.dart';

void main() {
  List<ExtractedDirective> directivesOf(String content) =>
      (extractDirectives(content, 'lib/a.dart') as ParsedDirectives).directives;

  test('comments and strings that look like directives do not count', () {
    final found = directivesOf('''
// import 'falso.dart';
/* export 'otro.dart'; */
const texto = "import 'tampoco.dart';";
''');
    expect(found, isEmpty);
  });

  test('every directive kind is extracted with its literal', () {
    final found = directivesOf('''
library biblioteca;
import 'a.dart';
export 'package:b/b.dart';
part 'c.dart';
''');
    expect(
      [for (final d in found) (d.directive, d.uri)],
      [
        ('import', 'a.dart'),
        ('export', 'package:b/b.dart'),
        ('part', 'c.dart'),
      ],
    );
  });

  test('part of keeps its uri or only its owner name', () {
    final byUri = directivesOf("part of 'biblioteca.dart';\n").single;
    expect(
      (byUri.directive, byUri.uri, byUri.ownerName),
      ('part_of', 'biblioteca.dart', null),
    );
    final byName = directivesOf('part of mi.biblioteca;\n').single;
    expect((byName.uri, byName.ownerName), (null, 'mi.biblioteca'));
  });

  test('a conditional import keeps the fallback and every branch', () {
    const source = '''
import 'base.dart'
    if (dart.library.io) 'io.dart'
    if (dart.library.html == "true") 'web.dart';
''';
    final directive = directivesOf(source).single;
    expect(directive.uri, 'base.dart');
    expect(
      [for (final a in directive.alternatives) (a.conditionText, a.uri)],
      [
        ('dart.library.io', 'io.dart'),
        ('dart.library.html == "true"', 'web.dart'),
      ],
    );
    final branch = directive.alternatives.first;
    expect(
      source.substring(branch.offset, branch.offset + branch.length),
      "if (dart.library.io) 'io.dart'",
    );
    expect((branch.line, branch.column), (2, 5));
  });

  test('an unrepresentable condition keeps its branch without the value', () {
    final directive = directivesOf('''
import 'base.dart' if (flag == "a b;rm") 'otro.dart';
''').single;
    expect(directive.alternatives.single.conditionText, isNull);
    expect(directive.alternatives.single.uri, 'otro.dart');
  });

  test('only a boolean comparison keeps its compared value', () {
    final directive = directivesOf('''
import 'base.dart'
    if (env.secret == "PRIVATE_TEST_VALUE_123") 'a.dart'
    if (env.mode == "release") 'b.dart'
    if (env.flag == "false") 'c.dart';
''').single;
    expect(
      [for (final a in directive.alternatives) (a.conditionText, a.uri)],
      [(null, 'a.dart'), (null, 'b.dart'), ('env.flag == "false"', 'c.dart')],
    );
  });

  test('deferred, prefixes and combinators do not change the reference', () {
    final found = directivesOf('''
import 'a.dart' deferred as diferida show Algo hide Otro;
''');
    expect([for (final d in found) d.uri], ['a.dart']);
  });

  test('offsets count UTF-16 units and lines start at one', () {
    const source = '// ñandú 😀\nimport \'a.dart\';\n';
    final directive = directivesOf(source).single;
    expect(directive.offset, source.indexOf('import'));
    expect((directive.line, directive.column), (2, 1));
    expect(
      source.substring(directive.offset, directive.offset + directive.length),
      "import 'a.dart';",
    );
  });

  test('an interpolated uri is kept without a literal', () {
    final directive = directivesOf(r"import 'a$b.dart';").single;
    expect(directive.uri, isNull);
  });

  test('S2: invalid syntax is a failed parse, not zero references', () {
    final batch = extractDirectives("import 'a.dart'\nclass {", 'lib/a.dart');
    expect(batch, isA<ParseFailed>());
    expect((batch as ParseFailed).reason, 'syntax');
  });
}
