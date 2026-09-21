/// Reglas de negocio del fixture. Deliberadamente aburridas: lo que se prueba
/// acá no es este código, es que el arnés sepa leer el proyecto que lo
/// contiene.
library;

/// Un carrito con su total. Existe para que haya algo que testear y algo que
/// romper a propósito.
class Carrito {
  final List<int> precios;

  Carrito(List<int> precios) : precios = List.unmodifiable(precios);

  int get total => precios.fold(0, (a, b) => a + b);

  bool get vacio => precios.isEmpty;
}
