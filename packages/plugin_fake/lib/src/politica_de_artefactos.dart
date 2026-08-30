import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;

/// Clasifica por listas dadas, no por reglas propias.
///
/// **Deliberadamente no reimplementa los patrones del real.** Si los copiara,
/// un error en esos patrones estaría en las dos implementaciones y la suite de
/// contrato lo confirmaría en verde: dos copias del mismo error se ponen de
/// acuerdo.
class PoliticaDeArtefactosFalsa implements ArtifactPolicy {
  final Set<String> _generados;
  final Set<String> _noEditables;

  PoliticaDeArtefactosFalsa({
    Set<String> generados = const {},
    Set<String> noEditables = const {},
  })  : _generados = Set.unmodifiable(generados),
        _noEditables = Set.unmodifiable(noEditables);

  /// Compara NORMALIZADO, igual que el real. Normalizar una ruta no es
  /// conocimiento de ningún ecosistema —es semántica de rutas— así que
  /// honrarlo es cumplir el contrato, no copiar la implementación.
  static String _n(String p) {
    final s = p.replaceAll(r'\', '/').trim();
    return s.isEmpty ? '' : rutas.posix.normalize(s);
  }

  @override
  bool isGenerated(String path) => _generados.map(_n).contains(_n(path));

  /// Un archivo generado nunca es editable: eso NO es una lista aparte, es una
  /// consecuencia. Tenerlas independientes permitiría declarar algo generado y
  /// editable a la vez, que es un estado que no significa nada.
  /// Honra las dos cláusulas del contrato —lo generado no es editable, y la
  /// ruta vacía tampoco—. **Eso no lo vuelve una copia del real**: son
  /// cláusulas del puerto, válidas en cualquier stack, no los patrones de
  /// NINGÚN ecosistema. Los patrones siguen sin estar acá, que es el punto —
  /// y el check de cadenas cazó este mismo comentario cuando nombraba uno.
  ///
  /// La divergencia la encontró la suite de contrato en su primera corrida:
  /// este fake devolvía `true` para la ruta vacía.
  @override
  bool isEditable(String path) =>
      path.trim().isNotEmpty &&
      !isGenerated(path) &&
      !_noEditables.map(_n).contains(_n(path));
}
