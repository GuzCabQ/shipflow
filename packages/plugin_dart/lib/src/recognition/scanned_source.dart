import '../observation/source_catalog.dart';
import '../stable_file_reader.dart';

/// Una fuente aceptada: estable, dentro de sus límites y sin parsear todavía.
final class ScannedSource {
  const ScannedSource(this.path, this.kind, this.read);

  /// Relativa a la raíz.
  final String path;
  final SourceKind kind;
  final StableSource read;
}
