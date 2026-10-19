import 'dart:io';

import 'path_probe.dart';

/// Dónde queda una referencia local, resuelta como la resolvería el sistema.
sealed class ReferencePlacement {
  const ReferencePlacement();
}

/// Dentro de la raíz, por directorios reales sin enlaces. [exists] es false
/// si algún tramo falta: pertenecer a la raíz no prueba que exista.
final class ReferenceInside extends ReferencePlacement {
  const ReferenceInside(this.path, {required this.exists});

  /// Relativa a la raíz; `.` es la raíz.
  final String path;
  final bool exists;
}

/// El trayecto sale de la raíz, aunque después vuelva a entrar.
final class ReferenceOutside extends ReferencePlacement {
  const ReferenceOutside();
}

/// No se puede decidir sin suponer: un tramo sin permiso, un NUL, un tramo
/// debajo de algo que no es un directorio o un `..` detrás de un tramo
/// inexistente.
final class ReferenceUnresolved extends ReferencePlacement {
  const ReferenceUnresolved();
}

/// Una forma de ruta que este corte no interpreta; no se resuelve.
final class ReferenceUnsupported extends ReferencePlacement {
  const ReferenceUnsupported(this.reason);

  final String reason;
}

/// Algún tramo es un enlace: no se sigue para corroborar.
final class ReferenceLinked extends ReferencePlacement {
  const ReferenceLinked(this.link);

  final String link;
}

/// El trayecto entra en un árbol que no se recorrió; no se reabre.
final class ReferenceExcluded extends ReferencePlacement {
  const ReferenceExcluded(this.tree);

  /// La raíz del árbol omitido, relativa a la raíz.
  final String tree;
}

/// Dónde queda [declared], desde el directorio [from] relativo a [root],
/// que ya se recorrió como directorio real. Mira tramo a tramo sin seguir
/// enlaces y se detiene en la primera frontera: un enlace, la salida de la
/// raíz, un árbol que [omittedTree] nombra o algo que no es un directorio.
/// Como todo lo recorrido son directorios reales, un `..` sube sin
/// suponer. Lo que no existe sólo alarga la ruta. Nunca mira más allá de
/// la frontera ni lo que hay dentro de lo que encuentra.
ReferencePlacement placeReference(
  Directory root,
  String from,
  String declared, {
  required String? Function(String path) omittedTree,
}) {
  if (declared.contains('\x00')) return const ReferenceUnresolved();
  final relative = declared.startsWith('/')
      ? _belowRoot(root.path, declared)
      : [if (from != '.') ...from.split('/'), ...declared.split('/')];
  if (relative == null) return const ReferenceOutside();
  final walk = _Walk(root.path, omittedTree);
  for (final (i, segment) in relative.indexed) {
    if (walk.step(segment, last: i == relative.length - 1) case final stop?) {
      return stop;
    }
  }
  return walk.placement();
}

/// Los tramos de [absolute] debajo de [root], o null si no empieza por
/// ella: entonces está fuera y no hace falta mirarla. Sólo se ignoran
/// tramos vacíos y `.`; un `..` antes de llegar a la raíz es salir.
List<String>? _belowRoot(String root, String absolute) {
  final prefix = root.split('/').where((s) => s.isNotEmpty).toList();
  final segments = absolute.split('/');
  var matched = 0;
  for (final (i, segment) in segments.indexed) {
    if (matched == prefix.length) return segments.sublist(i);
    if (segment.isEmpty || segment == '.') continue;
    if (segment != prefix[matched]) return null;
    matched++;
  }
  return matched == prefix.length ? const [] : null;
}

final class _Walk {
  _Walk(this.root, this.omittedTree) : current = root;

  final String root;
  final String? Function(String path) omittedTree;
  String current; // un directorio real dentro de la raíz, o lo que falta
  var missing = false;

  String get _relative =>
      current == root ? '.' : current.substring(root.length + 1);

  /// Null para seguir, o dónde se detiene el trayecto.
  ReferencePlacement? step(String segment, {required bool last}) {
    if (segment.isEmpty || segment == '.') return null;
    if (segment != '..') return _descend(segment, last: last);
    if (missing) return const ReferenceUnresolved();
    if (current == root) return const ReferenceOutside();
    current = current.substring(0, current.lastIndexOf('/'));
    return null;
  }

  /// Un tramo omitido se reconoce por su ruta, antes de mirarlo: aunque sea
  /// un enlace, no se consulta. Algo que no es un directorio sólo puede ser
  /// el último tramo: debajo de él no existe nada.
  ReferencePlacement? _descend(String segment, {required bool last}) {
    current = '$current/$segment';
    if (missing) return null;
    if (omittedTree(_relative) case final tree?) return ReferenceExcluded(tree);
    return switch (FileSystemEntity.typeSync(current, followLinks: false)) {
      FileSystemEntityType.directory => null,
      FileSystemEntityType.link => ReferenceLinked(current),
      FileSystemEntityType.notFound => _absent(),
      _ => last ? null : const ReferenceUnresolved(),
    };
  }

  ReferencePlacement? _absent() {
    if (!isAbsentPath(current)) return const ReferenceUnresolved();
    missing = true;
    return null;
  }

  ReferencePlacement placement() =>
      ReferenceInside(_relative, exists: !missing);
}
