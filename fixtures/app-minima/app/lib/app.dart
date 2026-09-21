import 'package:dominio/dominio.dart';
import 'package:flutter/widgets.dart';

/// Muestra el total de un carrito. Es el mínimo que obliga a que el arnés
/// distinga una capa que depende de la UI de una que no.
class TotalDelCarrito extends StatelessWidget {
  const TotalDelCarrito({required this.carrito, super.key});

  final Carrito carrito;

  @override
  Widget build(BuildContext context) => Text('${carrito.total}');
}
