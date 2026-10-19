/// Inventario AST de los cuerpos de más de 30 líneas y los archivos de más
/// de 300, para clasificar cada exceso. No modifica fuentes.
///
///     cd tool/analisis
///     dart run bin/v1_test_lengths.dart ../../packages
///
/// Escribe un JSON con `path`, `line`, `function`, `kind` y `lines` por
/// exceso, y `exempt: true` sólo para los cuerpos de `main` y de `group` en
/// archivos de prueba: la excepción aprobada para registros cohesionados.
/// Todo lo demás —callbacks de `test`, hooks, helpers y producción— queda
/// `exempt: false`. Sale 1 si hay algún exceso no exceptuado.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

const _maxBodyLines = 30;
const _maxFileLines = 300;
const _hooks = {'setUp', 'tearDown', 'setUpAll', 'tearDownAll'};

void main(List<String> arguments) {
  final files = [
    for (final argument in arguments.isEmpty ? ['.'] : arguments)
      ..._dartFiles(argument),
  ]..sort();
  final excesses = <Map<String, Object>>[];
  final longFiles = <Map<String, Object>>[];
  for (final path in files) {
    final content = File(path).readAsStringSync();
    final unit = parseString(content: content, path: path).unit;
    unit.accept(_Bodies(path, unit, excesses));
    final lines = unit.lineInfo.lineCount - (content.endsWith('\n') ? 1 : 0);
    if (lines > _maxFileLines) longFiles.add({'path': path, 'lines': lines});
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'maxBodyLines': _maxBodyLines,
      'maxFileLines': _maxFileLines,
      'files': files.length,
      'excesses': excesses,
      'longFiles': longFiles,
    }),
  );
  final unexcused = excesses.where((e) => e['exempt'] == false);
  if (unexcused.isNotEmpty || longFiles.isNotEmpty) exitCode = 1;
}

Iterable<String> _dartFiles(String root) sync* {
  if (FileSystemEntity.isFileSync(root)) {
    yield root;
    return;
  }
  for (final entity in Directory(root).listSync(recursive: true)) {
    final path = entity.path;
    if (entity is File &&
        path.endsWith('.dart') &&
        !path.contains('/.dart_tool/') &&
        !path.contains('/fixtures/')) {
      yield path;
    }
  }
}

/// Mide cada cuerpo desde su apertura, sin firma ni inicializadores.
final class _Bodies extends RecursiveAstVisitor<void> {
  _Bodies(this.path, this.unit, this.excesses);

  final String path;
  final CompilationUnit unit;
  final List<Map<String, Object>> excesses;

  bool get _isTest => path.contains('/test/');

  void _measure(String function, String kind, FunctionBody body) {
    final first = unit.lineInfo.getLocation(body.offset).lineNumber;
    final lines = unit.lineInfo.getLocation(body.end).lineNumber - first + 1;
    if (lines <= _maxBodyLines) return;
    excesses.add({
      'path': path,
      'line': first,
      'function': function,
      'kind': kind,
      'lines': lines,
      'exempt': _isTest && (kind == 'main' || kind == 'group'),
    });
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    _measure(
      name,
      name == 'main' ? 'main' : 'function',
      node.functionExpression.body,
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _measure(node.name.lexeme, 'method', node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _measure(node.name?.lexeme ?? '<constructor>', 'constructor', node.body);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.parent is! FunctionDeclaration) {
      final invocation = _invocationReceiving(node);
      final callee = invocation?.methodName.name ?? 'callback';
      _measure(
        '<$callee${_description(invocation)}>',
        _kindOf(callee),
        node.body,
      );
    }
    super.visitFunctionExpression(node);
  }

  /// La invocación de la que [node] es argumento directo, o null: una
  /// clausura local dentro de un `group` no hereda su excepción.
  MethodInvocation? _invocationReceiving(FunctionExpression node) {
    final argument = node.parent is NamedExpression ? node.parent! : node;
    final list = argument.parent;
    return list is ArgumentList && list.parent is MethodInvocation
        ? list.parent! as MethodInvocation
        : null;
  }

  /// La descripción literal de un `group` o `test`, si la tiene.
  String _description(MethodInvocation? invocation) {
    final first = invocation?.argumentList.arguments.firstOrNull;
    return first is StringLiteral && first.stringValue != null
        ? ': ${first.stringValue}'
        : '';
  }

  String _kindOf(String callee) => switch (callee) {
    'group' => 'group',
    'test' => 'test',
    _ when _hooks.contains(callee) => 'hook',
    _ => 'callback',
  };
}
