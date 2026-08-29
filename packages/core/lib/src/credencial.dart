/// El único tipo del dominio que NO es serializable, a propósito.
library;

/// Una credencial. **Opaca por construcción** (INV-5).
///
/// No tiene `toJson` ni `fromJson`, y eso no es un olvido: está declarado en
/// `arquitectura.json` bajo la regla `credencial-opaca`, y un check falla si
/// alguien se los agrega. Sin esa declaración, «no serializa» sería
/// indistinguible de «nadie escribió todavía la serialización».
///
/// El secreto no es accesible como propiedad. Se usa dentro de [use], que lo
/// presta por el tiempo de una llamada y no lo devuelve:
///
/// ```
/// final encabezado = credencial.use((secreto) => 'Bearer $secreto');
/// ```
///
/// **Lo que este tipo NO puede impedir**, y queda declarado: que el resultado
/// de [use] se guarde, se registre o se serialice. La barrera es contra el
/// descuido —una interpolación, un `toString` en un log, un volcado de
/// estado—, no contra alguien decidido. Ese residuo es del revisor.
class Credential {
  final String _secret;

  /// Cómo se la nombra en mensajes y trazas. **Nunca es el secreto.**
  final String label;

  const Credential(this._secret, {required this.label});

  /// Presta el secreto por el tiempo de [f] y devuelve lo que [f] produzca.
  T use<T>(T Function(String secret) f) => f(_secret);

  /// `true` si el secreto está vacío. Preguntable sin exponerlo.
  bool get isEmpty => _secret.isEmpty;

  /// Enmascarado, siempre. Es lo que aparece en una interpolación, en un log
  /// y en el mensaje de una excepción.
  @override
  String toString() => '***';

  /// Dos credenciales son la misma si su secreto lo es. La comparación no
  /// expone nada: devuelve un booleano.
  @override
  bool operator ==(Object other) =>
      other is Credential && other._secret == _secret && other.label == label;

  @override
  int get hashCode => Object.hash(_secret, label);
}
