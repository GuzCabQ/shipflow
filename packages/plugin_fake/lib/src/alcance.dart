/// Un observador de alcance que responde de una tabla. **No toca el disco.**
///
/// Existe para que `orchestration` y el CLI puedan probar la clasificación sin
/// toolchain ni árbol, y para que el puerto tenga la segunda implementación
/// que lo vuelve un contrato en vez de una indirección.
library;

import 'package:core/core.dart';

class ObservadorDeAlcanceFalso implements ScopeObserver {
  /// Qué se sabe de cada sujeto que sí se pudo mirar.
  final Map<String, ObservedSubject> observados;

  /// Sujeto a causa, para los que no se pudieron mirar.
  final Map<String, String> noObservados;

  /// Qué se le pidió, para poder comprobar que se llamó una sola vez.
  final List<List<String>> llamadas = [];

  ObservadorDeAlcanceFalso({
    required Map<String, ObservedSubject> observados,
    Map<String, String> noObservados = const {},
  })  : observados = Map.unmodifiable(observados),
        noObservados = Map.unmodifiable(noObservados);

  @override
  Future<ScopeObservation> observe(List<String> requested) async {
    llamadas.add(List.unmodifiable(requested));
    final vistos = <ObservedSubject>[];
    final ciegos = <UnobservedSubject>[];
    for (final s in requested) {
      final causa = noObservados[s];
      if (causa != null) {
        ciegos.add(UnobservedSubject(subject: s, cause: causa));
        continue;
      }
      final o = observados[s];
      // **Un sujeto que la tabla no declara no se inventa como ajeno.** Sería
      // el fake decidiendo, que es justo lo que el puerto vino a impedir.
      if (o == null) {
        throw ArgumentError.value(s, 'requested',
            'El fake no tiene declarado este sujeto. Declaralo en `observados` '
            'o en `noObservados`: adivinar sería clasificar por su cuenta');
      }
      vistos.add(o);
    }
    return ScopeObservation(
      requested: requested,
      observed: vistos,
      unobserved: ciegos,
      observedAt: DateTime.utc(2026),
    );
  }
}
