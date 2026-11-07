import 'package:core/core.dart';

import '../context/context_prompt.dart';

/// La entrada se cerró durante la guía: nada se acepta.
final class GuideCancelled implements Exception {
  const GuideCancelled();
}

const _maxAttempts = 20;

/// La respuesta a [question], recortada; vacía sólo si [optional]. Una
/// entrada cerrada cancela la guía.
Future<String> ask(
  ContextPromptIO io,
  String question, {
  bool optional = false,
}) async {
  for (var attempt = 0; attempt < _maxAttempts; attempt++) {
    io.show('$question\n> ');
    final line = await io.readLine();
    if (line == null) throw const GuideCancelled();
    final answer = line.trim();
    if (answer.isNotEmpty || optional) return answer;
  }
  throw const GuideCancelled();
}

/// Sí o no; cualquier otra respuesta se vuelve a preguntar.
Future<bool> yesNo(ContextPromptIO io, String question) async {
  for (var attempt = 0; attempt < _maxAttempts; attempt++) {
    switch ((await ask(io, '$question (s/n)')).toLowerCase()) {
      case 's' || 'si' || 'sí':
        return true;
      case 'n' || 'no':
        return false;
    }
  }
  throw const GuideCancelled();
}

/// El ámbito elegido explícitamente: «proyecto», prefijos separados por
/// comas o, si [unknownAllowed], «?». Vacío no es global.
Future<BasisScope> askScope(
  ContextPromptIO io,
  String question, {
  required bool unknownAllowed,
}) async {
  final hint = unknownAllowed
      ? '«proyecto», rutas separadas por comas o «?» si todavía no se sabe'
      : '«proyecto» o rutas separadas por comas';
  for (var attempt = 0; attempt < _maxAttempts; attempt++) {
    final answer = await ask(io, '$question ($hint)', optional: true);
    final scope = _scopeOf(answer, unknownAllowed: unknownAllowed);
    if (scope != null) return scope;
    io.show(
      answer.isEmpty
          ? 'Falta: elige el alcance explícitamente; no se deduce.\n'
          : 'No es un ámbito válido: usa rutas relativas como lib/pagos.\n',
    );
  }
  throw const GuideCancelled();
}

BasisScope? _scopeOf(String answer, {required bool unknownAllowed}) {
  if (answer == 'proyecto') return BasisScope.project();
  if (answer == '?') return unknownAllowed ? BasisScope.unknown() : null;
  final paths = [
    for (final p in answer.split(',')) p.trim(),
  ].where((p) => p.isNotEmpty).toSet().toList();
  if (paths.isEmpty || !paths.every(isBasisPrefix)) return null;
  return BasisScope(kind: BasisScopeKind.paths, paths: paths);
}

/// Una de las opciones numeradas de [options].
Future<T> choose<T>(
  ContextPromptIO io,
  String question,
  List<(String, T)> options,
) async {
  final listed = [
    for (final (i, (label, _)) in options.indexed) '  ${i + 1}) $label',
  ].join('\n');
  for (var attempt = 0; attempt < _maxAttempts; attempt++) {
    final answer = int.tryParse(await ask(io, '$question\n$listed'));
    if (answer != null && answer >= 1 && answer <= options.length) {
      return options[answer - 1].$2;
    }
  }
  throw const GuideCancelled();
}
