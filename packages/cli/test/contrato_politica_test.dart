/// Suite de contrato de `ArtifactPolicy`, contra las DOS implementaciones.
///
/// El sujeto acá no es un proyecto sino un conjunto de rutas, y eso cambia qué
/// puede probar la suite. La real las clasifica con los patrones de `N1-02` y
/// `N1-03`; la falsa recibe las respuestas ya dadas.
///
/// **Por eso la falsa NO reimplementa los patrones.** Si lo hiciera, un error
/// en ellos estaría en las dos y la suite lo confirmaría en verde: dos copias
/// del mismo error se ponen de acuerdo. Lo que esta suite prueba es que el
/// CONTRATO —incluidos sus bordes— sea el mismo, no que los patrones estén
/// bien. Que los patrones estén bien lo sostiene el registro semilla, que los
/// declara con su origen `[O]`.
library;

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';

/// Las rutas del sujeto, con lo que cada una ES. Se declara una vez y las dos
/// implementaciones se miden contra lo mismo.
const generadas = [
  'lib/modelo.g.dart',
  'lib/modelo.freezed.dart',
  'test/servicio.mocks.dart',
  'lib/l10n/app_es.dart',
];
const deBuild = ['build/salida.txt', '.dart_tool/package_config.json'];
const fuente = ['lib/modelo.dart', 'test/modelo_test.dart', 'pubspec.yaml'];

final implementaciones = <String, ArtifactPolicy Function()>{
  'real · clasifica con los patrones de N1-02 y N1-03': () =>
      const PoliticaDeArtefactosDart(),
  'falsa · se le declaran las respuestas': () => PoliticaDeArtefactosFalsa(
        generados: generadas.toSet(),
        noEditables: deBuild.toSet(),
      ),
};

void main() {
  test('la suite corre contra DOS implementaciones, no una', () {
    expect(implementaciones, hasLength(2));
    expect(
        implementaciones.keys.where((k) => k.startsWith('real')), hasLength(1),
        reason: 'sin la implementación real esto no es una suite de contrato');
  });

  for (final entrada in implementaciones.entries) {
    group(entrada.key, () {
      late ArtifactPolicy puerto;
      setUp(() => puerto = entrada.value());

      for (final ruta in generadas) {
        test('«$ruta» es generado y por lo tanto no editable', () {
          expect(puerto.isGenerated(ruta), isTrue);
          // No son dos hechos: el segundo se sigue del primero. Que puedan
          // contradecirse sería un estado sin significado.
          expect(puerto.isEditable(ruta), isFalse);
        });
      }

      for (final ruta in deBuild) {
        test('«$ruta» no es editable, y tampoco es «generado»', () {
          expect(puerto.isEditable(ruta), isFalse);
          expect(puerto.isGenerated(ruta), isFalse,
              reason: 'un artefacto de build no es código generado: son dos '
                  'categorías distintas de N1-02 y N1-03');
        });
      }

      for (final ruta in fuente) {
        test('«$ruta» es fuente: editable y no generado', () {
          expect(puerto.isGenerated(ruta), isFalse);
          expect(puerto.isEditable(ruta), isTrue);
        });
      }

      test('la ruta vacía no es editable', () {
        // Un borde que las dos tienen que responder igual. Devolver `true`
        // acá dejaría al arnés intentando escribir en ninguna parte.
        expect(puerto.isEditable(''), isFalse);
      });
    });
  }
}
