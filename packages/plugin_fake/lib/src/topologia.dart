import 'package:core/core.dart';

/// Devuelve la topología que se le dio. Nada más.
///
/// Su valor no es lo que calcula —no calcula nada— sino que **otro paquete
/// pueda probarse sin tocar el disco ni una toolchain**. Si además tuviera que
/// descubrir paquetes, sería una segunda implementación del real con los
/// mismos errores.
class TopologiaFalsa implements ProjectTopology {
  final List<Package> _paquetes;

  /// `retraso` existe para que los tests de orquestación puedan ejercer el
  /// caso asincrónico de verdad, no la ilusión de que todo responde ya.
  final Duration retraso;

  TopologiaFalsa(List<Package> paquetes, {this.retraso = Duration.zero})
      : _paquetes = List.unmodifiable(paquetes);

  @override
  Future<List<Package>> packages() async {
    if (retraso > Duration.zero) await Future<void>.delayed(retraso);
    return _paquetes;
  }
}
