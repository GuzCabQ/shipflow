import 'package:core/core.dart';

/// Una ruta del catálogo de fuentes candidatas, relativa a cada raíz de
/// unidad. La CLI la entrega desde su raíz de composición; el plugin sólo
/// consulta sus metadatos y nunca abre su contenido.
final class ContextSourceRule {
  const ContextSourceRule({
    required this.relativePath,
    required this.kind,
    required this.expectsDirectory,
  });

  /// Sin `/` final; puede tener varios tramos, como `.github/workflows`.
  final String relativePath;
  final ContextSourceKind kind;

  /// Si la ruta nombra un directorio: entonces un enlace con ese nombre
  /// sigue bloqueando el recorrido, como cualquier otro.
  final bool expectsDirectory;
}
