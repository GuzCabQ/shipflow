import 'package:app/app.dart';
import 'package:dominio/dominio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra el total del carrito', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TotalDelCarrito(carrito: Carrito(const [10, 32])),
      ),
    );
    expect(find.text('42'), findsOneWidget);
  });
}
