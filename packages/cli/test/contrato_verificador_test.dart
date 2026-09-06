/// Suite de contrato de `Verifier`, contra las DOS implementaciones reales.
///
/// **Acá no hay fake, y es a propósito.** El motivo por el que un puerto pide
/// dos implementaciones es que una sola es una indirección que todavía no se
/// contradijo; ese motivo ya está cubierto por dos pasos REALES que difieren
/// en lo que importa: uno puede comprobar su propia cobertura y el otro no.
/// Esa divergencia produjo una cláusula del puerto —la quinta— igual que la
/// ruta vacía produjo las de `ArtifactPolicy`.
///
/// **Hueco declarado:** falta un `Verifier` falso para que `orchestration`
/// pueda probar la cascada sin toolchain. Llega con la fase que lo necesite;
/// hoy no existe y no se finge que sí.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

ResultadoDeProceso _salida({
  Termination terminacion = Termination.completa,
  int codigo = 0,
  String estandar = '',
}) =>
    ResultadoDeProceso(
      terminacion: terminacion,
      codigo: codigo,
      salidaEstandar: estandar,
      salidaDeError: '',
    );

/// Cada implementación con una salida SUYA que significa «corrí y todo bien».
/// La suite no conoce ningún formato: cada caso trae el propio.
typedef Construir = Verifier Function(EjecutorDeProceso, String directorio);

final implementaciones = <String, (Construir, String)>{
  'real · FormatCheck': (
    (e, d) => PasoDeFormato(ejecutor: e, directorio: d),
    'Formatted 1 file (0 changed) in 0.00 seconds.\n',
  ),
  'real · StaticAnalysis': (
    (e, d) => PasoDeAnalisis(ejecutor: e, directorio: d),
    '{"version":1,"diagnostics":[]}',
  ),
};

void main() {
  // Un sujeto de verdad en disco. `StaticAnalysis` cuenta los archivos del
  // alcance porque su herramienta no informa cuáles leyó, así que un alcance
  // inventado le da no concluyente — con razón. Que esta suite lo descubriera
  // en su primera corrida es la cláusula 5 funcionando.
  late Directory raiz;
  setUp(() {
    raiz = Directory.systemTemp.createTempSync('contrato_verificador_');
    Directory('${raiz.path}/lib').createSync();
    File('${raiz.path}/lib/a.dart').writeAsStringSync('void main() {}\n');
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  test('la suite corre contra DOS implementaciones, y las dos son reales', () {
    expect(implementaciones, hasLength(2));
    expect(
        implementaciones.keys.where((k) => k.startsWith('real')), hasLength(2));
  });

  for (final entrada in implementaciones.entries) {
    final (construir, limpio) = entrada.value;

    group(entrada.key, () {
      Verifier paso(EjecutorDeProceso e) => construir(e, raiz.path);

      test('cláusula 1 · devuelve Ejecutado o Abortado, nunca otra cosa',
          () async {
        final o = await paso(EjecutorDeclarado(_salida(estandar: limpio)))
            .run(['lib']);
        expect(o, anyOf(isA<Executed>(), isA<Aborted>()));
      });

      test('cláusula 2 · un alcance sin sujetos utilizables lanza', () async {
        final ejecutor = EjecutorDeclarado(_salida());
        expect(() => paso(ejecutor).run(const []), throwsArgumentError);
        expect(ejecutor.invocaciones, isEmpty);
      });

      test('cláusula 3 · una terminación incompleta es Abortado', () async {
        for (final t in [
          Termination.herramientaAusente,
          Termination.tiempoAgotado,
          Termination.interrumpida,
        ]) {
          final o =
              await paso(EjecutorDeclarado(_salida(terminacion: t, codigo: -1)))
                  .run(['lib']);
          expect(o, isA<Aborted>(), reason: 'terminación $t');
          expect((o as Aborted).attempt.termination, t);
        }
      });

      test('cláusula 4 · el testigo nombra la invocación que se hizo',
          () async {
        final ejecutor = EjecutorDeclarado(_salida(estandar: limpio));
        final o = await paso(ejecutor).run(['lib']) as Executed;
        expect(ejecutor.invocaciones, hasLength(1));
        expect(o.witness.invocation, ejecutor.invocaciones.single);
      });

      test('cláusula 5 · un código desconocido no se supone benigno', () async {
        final o = await paso(
                EjecutorDeclarado(_salida(codigo: 111, estandar: limpio)))
            .run(['lib']) as Executed;
        expect(o.verdict, Verdict.noConcluyente);
        expect(o.witness.omitted.map((x) => x.reason).join(), contains('111'));
      });

      test('cláusula 6 · el testigo no nombra sujetos que no recibió',
          () async {
        final o = await paso(EjecutorDeclarado(_salida(estandar: limpio)))
            .run(['lib']) as Executed;
        expect(o.witness.subjects.every((s) => s == 'lib'), isTrue);
      });

      test(
          'cláusula 7 · y SÍ da verde cuando de verdad corrió y no encontró '
          'nada', () async {
        // Sin esto, un paso que devolviera no concluyente siempre pasaría
        // todas las cláusulas de arriba, por la vía de no funcionar.
        final o = await paso(EjecutorDeclarado(_salida(estandar: limpio)))
            .run(['lib']) as Executed;
        expect(o.verdict, Verdict.verde);
        expect(o.witness.subjects, isNotEmpty);
      });
    });
  }
}
