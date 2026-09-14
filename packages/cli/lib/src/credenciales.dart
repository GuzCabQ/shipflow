import 'package:core/core.dart';

/// El `CredentialSource` de este arnés: lee del entorno capturado en la raíz.
///
/// **Es delgado a propósito.** Toda la decisión —qué variables son secretas,
/// cómo se convierte una en [Credential], y que el mapa que baja a los hijos ya
/// no la tenga— vive en [EntornoDelProceso], que es puro y se prueba sin tocar
/// el mundo. Acá solo queda el puerto.
class FuenteDeEntorno implements CredentialSource {
  final EntornoDelProceso _entorno;

  const FuenteDeEntorno(this._entorno);

  @override
  Future<Credential?> read(String key) async => _entorno.credencial(key);
}
