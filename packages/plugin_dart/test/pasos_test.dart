/// Los pasos de cascada, con el ejecutor declarado.
///
/// Acá se prueban las terminaciones que no se pueden provocar de verdad —una
/// herramienta ausente, un presupuesto agotado— y sobre todo **los casos que
/// un review encontró**: la cobertura por sujeto, la lista que muta durante el
/// `await`, y las terminaciones que el paso reescribía.
library;

import 'dart:io';

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

const formatoLimpio = 'Formatted 1 file (0 changed) in 0.00 seconds.\n';
const analisisLimpio = '{"version":1,"diagnostics":[]}';

void main() {
  late Directory raiz;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('pasos_');
    Directory('${raiz.path}/lib').createSync();
    File('${raiz.path}/lib/a.dart').writeAsStringSync('void main() {}\n');
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  PasoDeFormato formato(ResultadoDeProceso r) =>
      PasoDeFormato(ejecutor: EjecutorDeclarado(r), directorio: raiz.path);
  PasoDeAnalisis analisis(ResultadoDeProceso r) =>
      PasoDeAnalisis(ejecutor: EjecutorDeclarado(r), directorio: raiz.path);

  group('lo que vale para cualquier paso', () {
    test('sin sujetos no se invoca nada, y el testigo NO nombra un comando',
        () async {
      final ejecutor = EjecutorDeclarado(salida());
      final o = await PasoDeFormato(ejecutor: ejecutor, directorio: raiz.path)
          .run([]);
      expect(o.verdict, Verdict.noConcluyente);
      expect(ejecutor.invocaciones, isEmpty);
      // Nombraba el comando que se habría corrido. La cláusula 4 pide que el
      // testigo nombre la invocación que de verdad se hizo, y acá no hubo.
      expect(o.witness!.invocation, isEmpty);
      expect(o.witness!.omitted, isNotEmpty);
    });

    test('la herramienta ausente no es «no encontró nada»', () async {
      final o = await formato(salida(
              terminacion: Termination.herramientaAusente,
              codigo: -1,
              error: 'No such file or directory'))
          .run(['lib/']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.termination, Termination.herramientaAusente);
    });

    test('el presupuesto agotado declara que puede haber dejado descendientes',
        () async {
      final o = await analisis(
              salida(terminacion: Termination.tiempoAgotado, codigo: -1))
          .run(['lib/']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.termination, Termination.tiempoAgotado);
      expect(o.witness!.omitted.join(), contains('descendientes'),
          reason: 'el ejecutor no los rastrea, y eso va en la evidencia');
    });

    test('un código desconocido NO reescribe la terminación', () async {
      // La herramienta corrió y produjo un resultado: eso es `completa`, por
      // definición. Que no sepamos interpretarlo es nuestro problema y va en
      // `omitted`. El veredicto sale no concluyente igual, porque no hay
      // sujetos cubiertos — no porque falseemos el hecho.
      final o = await formato(salida(codigo: 111, estandar: formatoLimpio))
          .run(['lib/']);
      expect(o.witness!.termination, Termination.completa);
      expect(o.witness!.exitCode, 111);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.omitted.join(), contains('111'));
    });

    test('una salida ilegible tampoco reescribe la terminación', () async {
      final o =
          await formato(salida(estandar: 'basura sin resumen')).run(['lib/']);
      expect(o.witness!.termination, Termination.completa);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.diagnostics, isEmpty,
          reason: 'culpar al código del usuario de que el arnés no sepa leer '
              'sería mentir sobre dónde está la falla');
    });

    test('la lista del llamador no puede cambiar la evidencia', () async {
      // El review lo reprodujo: la lista mutaba durante el `await` y el
      // testigo terminaba nombrando una invocación sobre un alcance y
      // declarando cobertura sobre otro.
      final lista = ['lib/'];
      final o = await PasoDeFormato(
        ejecutor: _MutaDurante(lista, salida(estandar: formatoLimpio)),
        directorio: raiz.path,
      ).run(lista);
      expect(o.witness!.subjects, ['lib/']);
      expect(o.witness!.invocation, contains('lib/'));
      expect(o.witness!.invocation, isNot(contains('no/existe')));
    });

    test('el testigo nombra la invocación que de verdad se hizo', () async {
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final o = await PasoDeFormato(ejecutor: ejecutor, directorio: raiz.path)
          .run(['lib/']);
      expect(ejecutor.invocaciones.single, o.witness!.invocation);
    });

    test('un alcance que no se puede mirar es un dato, no una excepción',
        () async {
      // Un directorio sin permisos hacía que `run` lanzara y el paso no
      // devolviera testigo ninguno, rompiendo la primera cláusula del puerto.
      final vedado = Directory('${raiz.path}/vedado')..createSync();
      Process.runSync('chmod', ['000', vedado.path]);
      addTearDown(() => Process.runSync('chmod', ['755', vedado.path]));
      final o =
          await analisis(salida(estandar: analisisLimpio)).run(['vedado']);
      expect(o.witness, isNotNull);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.omitted.join(), contains('no se pudo mirar'));
    }, onPlatform: const {'windows': Skip('los permisos POSIX no aplican')});
  });

  group('cobertura POR SUJETO, no agregada', () {
    test('un alcance mixto no certifica el sujeto que no existe', () async {
      // El falso verde que encontró el review: la herramienta miraba un
      // archivo y el paso devolvía TODOS los sujetos como cubiertos.
      final o = await formato(salida(estandar: formatoLimpio))
          .run(['lib/', 'no/existe']);
      expect(o.witness!.subjects, ['lib/'],
          reason:
              'certificar una ruta que la herramienta dijo que no encuentra '
              'es exactamente lo que ADR-011 prohíbe');
      expect(o.witness!.omitted.join(), contains('no/existe'));
    });

    test('si NINGÚN sujeto es utilizable, no hay cobertura y no hay verde',
        () async {
      final o = await formato(salida(estandar: formatoLimpio))
          .run(['no/existe', 'tampoco/esta']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.subjects, isEmpty);
      expect(o.witness!.omitted.length, greaterThanOrEqualTo(2));
    });

    test('un directorio que existe pero no tiene fuentes se declara omitido',
        () async {
      Directory('${raiz.path}/vacio').createSync();
      final o = await analisis(salida(estandar: analisisLimpio))
          .run(['lib/', 'vacio']);
      expect(o.witness!.subjects, ['lib/']);
      expect(o.witness!.omitted.join(), contains('vacio'));
    });
  });

  group('FormatCheck · sí puede ver su propia ceguera', () {
    test('cero archivos mirados NO es verde, aunque el código sea 0', () async {
      final o = await formato(salida(
        estandar: 'Formatted no files in 0.00 seconds.\n',
        error: 'No file or directory found at "lib/".\n',
      )).run(['lib/']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.subjects, isEmpty);
      expect(o.witness!.omitted.join(), contains('NINGÚN archivo'));
    });

    test('un archivo mirado y limpio sí es verde', () async {
      final o = await formato(salida(estandar: formatoLimpio)).run(['lib/']);
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
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.diagnostics.single.ruleId, 'formato/no-parsea');
    });
  });

  group('StaticAnalysis · NO puede, y lo declara', () {
    test('declara siempre que no sabe qué archivos leyó la herramienta',
        () async {
      final o = await analisis(salida(estandar: analisisLimpio)).run(['lib/']);
      expect(
          o.witness!.omitted.join(), contains('no informa qué archivos leyó'));
      expect(o.verdict, Verdict.verde,
          reason: 'declarar un residuo no invalida lo que sí cubrió');
    });
  });
}

/// Muta la lista del llamador mientras el proceso está suspendido.
class _MutaDurante implements EjecutorDeProceso {
  final List<String> lista;
  final ResultadoDeProceso respuesta;
  _MutaDurante(this.lista, this.respuesta);

  @override
  Future<ResultadoDeProceso> correr(String e, List<String> a,
      {required String directorio, required Duration presupuesto}) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    lista
      ..clear()
      ..add('no/existe');
    return respuesta;
  }
}
