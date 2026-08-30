import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('un carrito vacío suma cero', () {
    expect(Carrito(const []).total, equals(0));
    expect(Carrito(const []).vacio, isTrue);
  });

  test('suma los precios', () {
    expect(Carrito(const [100, 250, 3]).total, equals(353));
  });
}
