/// Los pasos de cascada, con el ejecutor declarado.
///
/// Acá se prueban las terminaciones que no se pueden provocar de verdad —una
/// herramienta ausente, un presupuesto agotado— y sobre todo **el caso que
/// esta rebanada existe para cerrar**: la herramienta sale con codigo 0, no
/// mira ni un archivo, y el paso NO da verde.
library;

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

ResultadoDeProceso salida({
  Termination terminacion = Termination.completa,
  int codigo = 0,
  String estandar = '',
  String error = '',
}) =>
    ResultadoDeProceso(
      terminacion: terminacion,
      codigo: codigo,
      salidaEstandar: estandar,
      salidaDeError: error,
    );

PasoDeFormato formato(ResultadoDeProceso r) =>
    PasoDeFormato(ejecutor: EjecutorDeclarado(r), directorio: '/no/importa');

PasoDeAnalisis analisis(ResultadoDeProceso r) =>
    PasoDeAnalisis(ejecutor: EjecutorDeclarado(r), directorio: '/no/importa');

void main() {
  group('lo que vale para cualquier paso', () {
    test('sin sujetos no se invoca nada, y no es verde', () async {
      final ejecutor = EjecutorDeclarado(salida());
      final paso = PasoDeFormato(ejecutor: ejecutor, directorio: '/no/importa');
      final o = await paso.run([]);
      expect(o.verdict, Verdict.noConcluyente);
      expect(ejecutor.invocaciones, isEmpty,
          reason: 'invocar la herramienta sin sujeto es gastar por nada');
      expect(o.witness!.omitted, isNotEmpty,
          reason: 'un no concluyente sin motivo no se puede accionar');
    });

    test('la herramienta ausente no es «no encontro nada»', () async {
      final o = await formato(salida(
              terminacion: Termination.herramientaAusente,
              codigo: -1,
              error: 'No such file or directory'))
          .run(['lib/']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.termination, Termination.herramientaAusente);
    });

    test('el presupuesto agotado tampoco', () async {
      final o = await analisis(
              salida(terminacion: Termination.tiempoAgotado, codigo: -1))
          .run(['lib/']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.termination, Termination.tiempoAgotado);
    });

    test('un codigo de salida fuera de la lista blanca no se supone benigno',
        () async {
      // Una ruta que no existe le hace devolver 64 al analizador. Es el unico
      // caso ciego que esa herramienta si delata, y esto es lo que lo atrapa.
      final o = await analisis(salida(codigo: 64)).run(['no/existe']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.omitted.single, contains('64'));
    });

    test(
        'una salida que no se puede interpretar no es un hallazgo contra el '
        'codigo del usuario', () async {
      final o =
          await formato(salida(estandar: 'basura sin resumen')).run(['lib/']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.diagnostics, isEmpty,
          reason: 'culpar al codigo del usuario de que el arnes no sepa leer '
              'seria mentir sobre donde esta la falla');
      expect(o.witness!.omitted.single, contains('denominador'));
    });

    test('el testigo nombra la invocacion que de verdad se hizo', () async {
      final ejecutor = EjecutorDeclarado(
          salida(estandar: 'Formatted 1 file (0 changed) in 0.0 seconds.\n'));
      final paso = PasoDeFormato(ejecutor: ejecutor, directorio: '/no/importa');
      final o = await paso.run(['lib/']);
      expect(ejecutor.invocaciones.single, o.witness!.invocation,
          reason: 'un testigo que nombra una invocacion que no ocurrio es peor '
              'que no tener testigo');
    });
  });

  group('FormatCheck · si puede ver su propia ceguera', () {
    test('cero archivos mirados NO es verde, aunque el codigo sea 0', () async {
      // El hallazgo medido que motiva toda esta rebanada: con un directorio
      // que no existe, la herramienta sale con codigo 0 y dice «no files».
      final o = await formato(salida(
        codigo: 0,
        estandar: 'Formatted no files in 0.00 seconds.\n',
        error: 'No file or directory found at "lib/".\n',
      )).run(['lib/']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.subjects, isEmpty,
          reason: 'sin sujetos cubiertos el testigo no atestigua, y el '
              'veredicto se deriva solo: nadie tiene que acordarse');
      expect(o.witness!.omitted.single, contains('NINGUN archivo'));
    });

    test('un archivo mirado y limpio si es verde', () async {
      final o = await formato(salida(
              estandar: 'Formatted 1 file (0 changed) in 0.0 seconds.\n'))
          .run(['lib/']);
      expect(o.verdict, Verdict.verde);
      expect(o.witness!.subjects, ['lib/']);
      expect(o.witness!.omitted, isEmpty);
    });

    test('un archivo sin formatear pone el paso en rojo', () async {
      final o = await formato(salida(
              estandar: 'Changed lib/a.dart\n'
                  'Formatted 1 file (1 changed) in 0.0 seconds.\n'))
          .run(['lib/']);
      expect(o.verdict, Verdict.rojo);
      expect(o.diagnostics.single.file, 'lib/a.dart');
    });

    test('S4 · el archivo que no parsea se reporta Y se declara omitido',
        () async {
      final o = await formato(salida(
        codigo: 65,
        estandar: 'Formatted no files in 0.0 seconds.\n',
        error: 'Could not format because the source could not be parsed:\n'
            "line 2, column 1 of lib/roto.dart: Expected to find '}'.\n",
      )).run(['lib/']);
      // Miro cero archivos formateables, asi que no puede atestiguar cobertura
      // — y aun asi el diagnostico del archivo corrupto esta. Las dos cosas
      // son ciertas a la vez y ninguna tapa a la otra.
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.diagnostics.single.ruleId, 'formato/no-parsea');
    });
  });

  group('StaticAnalysis · NO puede, y lo declara', () {
    test('declara siempre que no sabe que archivos leyo la herramienta',
        () async {
      // ADR-011 corolario 5 como dato y no como comentario: el paso que no
      // puede detectar una omision tiene que decirlo en su testigo.
      final o =
          await analisis(salida(estandar: '{"version":1,"diagnostics":[]}'))
              .run(['.']);
      expect(
          o.witness!.omitted.single, contains('no informa que archivos leyo'));
    });

    test('un alcance sin archivos de fuente deja el paso sin cobertura',
        () async {
      final o =
          await analisis(salida(estandar: '{"version":1,"diagnostics":[]}'))
              .run(['no/existe/en/ningun/lado']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.subjects, isEmpty);
    });
  });
}
