import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('lee la credencial declarada del entorno capturado', () async {
    final fuente = FuenteDeEntorno(
      EntornoDelProceso(const {'SHIPFLOW_GITHUB_TOKEN': 'ghp_x'}),
    );
    final c = await fuente.read('SHIPFLOW_GITHUB_TOKEN');
    expect(c, isNotNull);
    expect(c!.use((secreto) => secreto), 'ghp_x');
    expect(c.label, 'SHIPFLOW_GITHUB_TOKEN');
  });

  test('sin la variable no hay credencial, y eso no es un error', () async {
    final fuente = FuenteDeEntorno(EntornoDelProceso(const {}));
    expect(await fuente.read('SHIPFLOW_GITHUB_TOKEN'), isNull);
  });

  test('una clave que el repositorio no declaró secreta no se sirve', () {
    final fuente = FuenteDeEntorno(EntornoDelProceso(const {'PATH': '/bin'}));
    expect(() => fuente.read('PATH'), throwsArgumentError);
  });

  test('es un CredentialSource y NO un CredentialStore', () {
    final fuente = FuenteDeEntorno(EntornoDelProceso(const {}));
    expect(fuente, isA<CredentialSource>());
    expect(fuente, isNot(isA<CredentialStore>()));
  });
}
