import 'package:core/core.dart';

/// Qué archivos son generados y cuáles se pueden editar, en un proyecto
/// Dart o Flutter.
///
/// Los patrones **no se inventaron acá**: son `N1-02` y `N1-03` del registro
/// semilla del corpus, y a su vez vienen del intento anterior bajo el rótulo
/// *código recolectado que NO es arquitectura del producto* `[O]`.
///
/// POR QUÉ IMPORTA QUE ESTÉ ACÁ Y NO EN EL ARNÉS
///     `*.g.dart` no significa nada fuera de este ecosistema. Si el arnés
///     conociera ese patrón, cambiar de stack exigiría cambiar el arnés — que
///     es exactamente la fuga que `D-014` busca.
class PoliticaDeArtefactosDart implements ArtifactPolicy {
  /// `N1-02`: generados por la toolchain. No se leen ni se editan.
  static const sufijosGenerados = ['.g.dart', '.freezed.dart', '.mocks.dart'];

  /// `N1-02`, segunda mitad: lo generado por directorio, no por sufijo.
  static const directoriosGenerados = ['lib/l10n/'];

  /// `N1-03`: artefactos de build, excluidos de lectura.
  static const directoriosDeBuild = ['build/', '.dart_tool/'];

  const PoliticaDeArtefactosDart();

  @override
  bool isGenerated(String path) {
    final p = _normalizar(path);
    return sufijosGenerados.any(p.endsWith) ||
        directoriosGenerados.any((d) => p.startsWith(d) || p.contains('/$d'));
  }

  /// Editable es **la negación de dos cosas distintas**, y por eso no es una
  /// lista aparte: lo generado se regenera, y lo de build no es fuente. Tener
  /// una tercera lista permitiría declarar algo generado y editable a la vez,
  /// que es un estado sin significado.
  @override
  bool isEditable(String path) {
    final p = _normalizar(path);
    if (p.isEmpty) return false;
    if (isGenerated(p)) return false;
    return !directoriosDeBuild.any((d) => p.startsWith(d) || p.contains('/$d'));
  }

  String _normalizar(String path) {
    final p = path.replaceAll(r'\', '/').trim();
    return p.startsWith('./') ? p.substring(2) : p;
  }
}
