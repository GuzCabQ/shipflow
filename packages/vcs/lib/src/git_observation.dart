import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

/// La regla que decide si una ruta propia está ignorada: su archivo, ya
/// absoluto, su línea y su patrón. Negada si el patrón empieza con `!`.
final class IgnoreMatch {
  const IgnoreMatch({
    required this.source,
    required this.line,
    required this.pattern,
  });

  final String source;
  final int line;
  final String pattern;

  bool get negated => pattern.startsWith('!');
}

/// Lo que se observó de Git para una raíz. Sólo [GitState.available] trae
/// vínculo, exclude y rutas; [GitState.unavailable] trae su [code]. Nunca
/// se infiere ausencia de un error.
final class GitObservation {
  GitObservation({
    required this.root,
    required this.ownPaths,
    required this.state,
    required this.processesStarted,
    this.code,
    this.binding,
    this.excludePath,
    List<String> tracked = const [],
    Map<String, IgnoreMatch> matches = const {},
  }) : tracked = List.unmodifiable(tracked),
       matches = Map.unmodifiable(matches);

  final Directory root;
  final List<String> ownPaths;
  final GitState state;
  final String? code;
  final GitBinding? binding;

  /// El exclude local que corresponde a esta raíz, absoluto.
  final String? excludePath;

  /// Las rutas propias que Git ya sigue.
  final List<String> tracked;

  /// La regla que alcanza a cada ruta propia, ignorándola o negándola.
  final Map<String, IgnoreMatch> matches;
  final int processesStarted;

  /// Las rutas propias que una regla no negada ignora.
  Map<String, IgnoreMatch> get ignoredBy => {
    for (final e in matches.entries)
      if (!e.value.negated) e.key: e.value,
  };

  /// Si la administración es común a otras copias de trabajo.
  bool get linkedWorktree =>
      binding != null && binding!.gitDir != binding!.commonDir;
}

/// El resultado de comprobar una elección contra lo observado ahora.
final class SharingCheck {
  const SharingCheck(this.effective, {this.code, this.rule});

  final SharingEffective effective;

  /// `already_tracked`, `not_excluded`, `ignored_by_rule` o el código de
  /// Git que impidió comprobarla.
  final String? code;
  final IgnoreMatch? rule;
}

/// Las rutas que `rev-parse` informa de un worktree.
typedef RevParsePaths = ({
  String top,
  String gitDir,
  String commonDir,
  String exclude,
  String prefix,
});

/// Las líneas de `rev-parse`: toplevel, git-dir, common-dir, exclude y
/// prefix, en ese orden; null si no son exactamente esas.
RevParsePaths? parseRevParse(List<int> stdout) {
  final text = utf8.decode(stdout, allowMalformed: true);
  if (!text.endsWith('\n')) return null;
  final lines = text.substring(0, text.length - 1).split('\n');
  if (lines.length != 5) return null;
  final [top, gitDir, commonDir, exclude, prefix] = lines;
  if (![top, gitDir, commonDir, exclude].every((p) => p.startsWith('/'))) {
    return null;
  }
  return (
    top: top,
    gitDir: gitDir,
    commonDir: commonDir,
    exclude: exclude,
    prefix: prefix,
  );
}

/// Las rutas separadas por NUL de `ls-files -z`.
List<String> parseNulList(List<int> stdout) => [
  for (final path in utf8.decode(stdout, allowMalformed: true).split('\u0000'))
    if (path.isNotEmpty) path,
];

/// Los registros de `check-ignore -v -n -z`: fuente, línea, patrón y ruta.
/// Una fuente relativa lo es a [top]; una ruta sin regla no aparece.
Map<String, IgnoreMatch> parseCheckIgnore(List<int> stdout, String top) {
  final fields = utf8.decode(stdout, allowMalformed: true).split('\u0000');
  final matches = <String, IgnoreMatch>{};
  for (var i = 0; i + 3 < fields.length; i += 4) {
    final [source, line, pattern, path] = fields.sublist(i, i + 4);
    if (source.isEmpty) continue;
    matches[path] = IgnoreMatch(
      source: source.startsWith('/') ? source : '$top/$source',
      line: int.tryParse(line) ?? 0,
      pattern: pattern,
    );
  }
  return matches;
}
