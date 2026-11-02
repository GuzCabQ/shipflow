import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

/// La versión del parser fijada en el pubspec del plugin.
const parserVersion = '14.1.0';

/// Una alternativa condicional de una directiva: su condición en forma
/// segura, o null si no es representable, y su URI literal, o null.
final class ExtractedAlternative {
  const ExtractedAlternative({
    required this.conditionText,
    required this.uri,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
  });

  final String? conditionText;
  final String? uri;
  final int offset;
  final int length;
  final int line;
  final int column;
}

/// Una directiva de referencia: `import`, `export`, `part` o `part_of`,
/// con su URI literal (null si no lo es), el nombre de su biblioteca para un
/// `part of` nombrado, su ubicación y sus alternativas.
final class ExtractedDirective {
  const ExtractedDirective({
    required this.directive,
    required this.uri,
    required this.ownerName,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
    required this.alternatives,
  });

  final String directive;
  final String? uri;
  final String? ownerName;
  final int offset;
  final int length;
  final int line;
  final int column;
  final List<ExtractedAlternative> alternatives;
}

/// Lo que se obtuvo de un archivo: sus directivas, o por qué no aporta
/// ninguna. Un archivo fallido no es un archivo sin referencias.
sealed class DirectiveBatch {
  const DirectiveBatch();
}

final class ParsedDirectives extends DirectiveBatch {
  const ParsedDirectives(this.directives);

  final List<ExtractedDirective> directives;
}

/// El parser informó al menos un diagnóstico: `syntax`. Nunca se guarda su
/// mensaje.
final class ParseFailed extends DirectiveBatch {
  const ParseFailed(this.reason);

  final String reason;
}

/// El análisis no terminó dentro de su plazo.
final class ParseTimedOut extends DirectiveBatch {
  const ParseTimedOut();
}

/// Las directivas de [content] por su árbol sintáctico, sin resolver nada:
/// ni SDK, ni `package_config`, ni el análisis del proyecto.
DirectiveBatch extractDirectives(String content, String relativePath) {
  final result = parseString(
    content: content,
    path: relativePath,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) return const ParseFailed('syntax');
  final lines = result.lineInfo;
  return ParsedDirectives([
    for (final directive in result.unit.directives)
      ?_directive(directive, lines),
  ]);
}

ExtractedDirective? _directive(Directive node, LineInfo lines) {
  final at = lines.getLocation(node.offset);
  ExtractedDirective of(String kind, String? uri, [String? owner]) =>
      ExtractedDirective(
        directive: kind,
        uri: uri,
        ownerName: owner,
        offset: node.offset,
        length: node.length,
        line: at.lineNumber,
        column: at.columnNumber,
        alternatives: node is NamespaceDirective
            ? [for (final c in node.configurations) _alternative(c, lines)]
            : const [],
      );
  return switch (node) {
    ImportDirective() => of('import', node.uri.stringValue),
    ExportDirective() => of('export', node.uri.stringValue),
    PartDirective() => of('part', node.uri.stringValue),
    PartOfDirective() => of(
      'part_of',
      node.uri?.stringValue,
      node.libraryName == null ? null : _dotted(node.libraryName!),
    ),
    _ => null,
  };
}

ExtractedAlternative _alternative(Configuration node, LineInfo lines) {
  final at = lines.getLocation(node.offset);
  return ExtractedAlternative(
    conditionText: _condition(node),
    uri: node.uri.stringValue,
    offset: node.offset,
    length: node.length,
    line: at.lineNumber,
    column: at.columnNumber,
  );
}

final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$');
final _value = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');

/// La condición como variable con puntos y, si la tiene, su comparación
/// con un valor simple; null si alguna parte no es representable sin
/// copiar un valor arbitrario.
String? _condition(Configuration node) {
  final name = _dotted(node.name);
  if (!name.split('.').every(_identifier.hasMatch)) return null;
  final value = node.value;
  if (value == null) return name;
  final text = value.stringValue;
  return text != null && _value.hasMatch(text) ? '$name == "$text"' : null;
}

/// Los identificadores de [name] unidos por puntos: sus tokens incluyen los
/// puntos mismos.
String _dotted(DottedName name) => [
  for (final t in name.tokens)
    if (t.lexeme != '.') t.lexeme,
].join('.');
