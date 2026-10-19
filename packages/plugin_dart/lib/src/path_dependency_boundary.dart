import 'dart:io';

import 'path_probe.dart';

/// Dónde queda una referencia local, resuelta como la resolvería el sistema.
sealed class ReferencePlacement {
  const ReferencePlacement();
}

/// Dentro de la raíz, por tramos reales sin enlaces. [exists] es false si
/// algún tramo falta: pertenecer a la raíz no prueba que exista.
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

/// No se puede decidir sin suponer: un enlace roto, un tramo sin permiso, un
/// NUL o un `..` detrás de un tramo inexistente.
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

/// Dónde queda [declared], desde el directorio [from] relativo a [root].
/// Sólo resuelve rutas y enlaces, tramo a tramo: cada tramo que existe se
/// resuelve con sus enlaces antes de aplicar el siguiente `..`, que sube
/// desde el destino real. Lo que no existe sólo alarga la ruta. Nunca lee
/// lo que hay del otro lado ni entra en un árbol que [omittedTree] nombra.
ReferencePlacement placeReference(
  Directory root,
  String from,
  String declared, {
  required String? Function(String path) omittedTree,
}) {
  if (declared.contains('\x00')) return const ReferenceUnresolved();
  final walk = _Walk(root.path, omittedTree);
  final start = from == '.' ? root.path : '${root.path}/$from';
  for (final segment
      in (declared.startsWith('/') ? declared : '$start/$declared').split(
        '/',
      )) {
    if (walk.step(segment) case final stop?) return stop;
  }
  return walk.placement();
}

final class _Walk {
  _Walk(this.root, this.omittedTree);

  final String root;
  final String? Function(String path) omittedTree;
  var current = ''; // canónica; vacía es `/`
  var missing = false;
  var wasInside = false;
  var left = false;
  String? link;

  bool get _inside => current == root || current.startsWith('$root/');

  String get _relative =>
      current == root ? '.' : current.substring(root.length + 1);

  ReferencePlacement? step(String segment) {
    if (segment.isEmpty || segment == '.') return null;
    if (segment == '..') {
      if (missing) return const ReferenceUnresolved();
      if (current.isNotEmpty) {
        current = current.substring(0, current.lastIndexOf('/'));
      }
    } else if (_descend(segment) case final stop?) {
      return stop;
    }
    if (!_inside) {
      left = left || wasInside;
      return null;
    }
    wasInside = true;
    final tree = omittedTree(_relative);
    return tree == null ? null : ReferenceExcluded(tree);
  }

  ReferencePlacement? _descend(String segment) {
    current = '$current/$segment';
    if (missing) return null;
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (!isAbsentPath(current)) return const ReferenceUnresolved();
      missing = true;
      return null;
    }
    if (type == FileSystemEntityType.link) link ??= current;
    try {
      current = File(current).resolveSymbolicLinksSync();
    } on FileSystemException {
      return const ReferenceUnresolved();
    }
    return null;
  }

  ReferencePlacement placement() {
    if (left || !_inside) return const ReferenceOutside();
    if (link case final link?) return ReferenceLinked(link);
    return ReferenceInside(_relative, exists: !missing);
  }
}
