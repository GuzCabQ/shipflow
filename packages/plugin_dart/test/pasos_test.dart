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
import 'package:plugin_fake/plugin_fake.dart';
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

/// Un ejecutor que **cambia el árbol mientras la herramienta corre**.
///
/// Existe para una sola pregunta: si el alcance se mira dos veces —una antes y
/// otra después del `await`— el testigo puede afirmar dos cosas incompatibles.
class _EjecutorQueCreaUnArchivo implements EjecutorDeProceso {
  final String donde;
  final ResultadoDeProceso resultado;
  _EjecutorQueCreaUnArchivo(this.donde, this.resultado);

  @override
  Future<ResultadoDeProceso> correr(String programa, List<String> args,
      {required String directorio, required Duration presupuesto}) async {
    File('$donde/aparecio.dart').writeAsStringSync('void main() {}\n');
    return resultado;
  }
}

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
    test('el paso NO mira el árbol por su cuenta: le pregunta al observador',
        () async {
      // Si el paso siguiera decidiendo qué es suyo, seguiría siendo juez de su
      // propia incumbencia. Con un observador que declara `lib` ajeno, el
      // paso no puede invocar nada, por más que `lib` exista y tenga fuentes.
      final falso = ObservadorDeAlcanceFalso(observados: {
        'lib': ObservedSubject(
            subject: 'lib',
            ofStack: false,
            files: 0,
            reason: 'el observador dice que no'),
      });
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final paso = PasoDeFormato(
          ejecutor: ejecutor, directorio: raiz.path, observador: falso);
      await paso.run(['lib']);
      expect(ejecutor.invocaciones, isEmpty);
      expect(falso.llamadas, hasLength(1),
          reason: 'una sola foto del árbol por corrida de paso');
    });

    test('lo descartado NO llega a la herramienta', () async {
      // `separar` clasificaba bien y la invocación se armaba igual con TODOS
      // los pedidos: `verify README.md` le daba el markdown a la herramienta
      // del stack, que intentaba parsearlo y devolvía diagnósticos sobre un
      // archivo que no es de su incumbencia. Afecta a cualquier cambio normal
      // que mezcle código y documentación. Lo cobró un review.
      File('${raiz.path}/lib/LEEME.md').writeAsStringSync('# prosa\n');
      final paso = PasoDeFormato(
          ejecutor: EjecutorDeclarado(salida(estandar: formatoLimpio)),
          directorio: raiz.path);
      final r = await paso.run(['lib/a.dart', 'lib/LEEME.md']);

      expect(r.witness!.invocation, contains('lib/a.dart'));
      expect(r.witness!.invocation, isNot(contains('LEEME.md')),
          reason: 'lo descartado no puede llegar a la toolchain');
      expect(r.witness!.omitted.join(' '), contains('LEEME.md'),
          reason: 'pero sigue declarado: sale de cubierto, no del reporte');
    });

    test('un código de salida desconocido deja el conteo en «no sé»', () async {
      // Una herramienta que devuelve algo que no entendemos no dice «no tuve
      // nada que hacer»: dice «no sé». Dejar ahí el conteo del alcance
      // permitía que un paso con la herramienta devolviendo basura se
      // clasificara como saltado, y el ruido desapareciera. Lo pidió una
      // mutación.
      //
      // Con sujetos utilizables: si no los hay no se invoca nada, y entonces
      // no hay ningún código de salida que no entender.
      final paso = PasoDeFormato(
          ejecutor: EjecutorDeclarado(salida(codigo: 64)),
          directorio: raiz.path);
      final r = await paso.run(['lib']);
      expect(r.witness!.ownSubjects, isNull,
          reason: 'había sujetos, pero la herramienta no se entendió');
      expect(r.verdict, Verdict.noConcluyente);
    });

    test('el testigo sale de UNA sola foto del árbol', () async {
      // Si el alcance se mira dos veces —una para el conteo y otra para la
      // cobertura, con un `await` en el medio— el testigo puede afirmar «cero
      // elementos propios» y «cubrí lib» a la vez. Lo reprodujo un review con un
      // ejecutor que creaba un archivo durante la espera.
      // Sobre un alcance CON archivos, para que la herramienta se invoque de
      // verdad y el `await` exista.
      final paso = PasoDeFormato(
          ejecutor: _EjecutorQueCreaUnArchivo(
              '${raiz.path}/lib', salida(estandar: formatoLimpio)),
          directorio: raiz.path);
      final r = await paso.run(['lib']);

      final w = r.witness!;
      expect(w.ownSubjects == 0 && w.subjects.isNotEmpty, isFalse,
          reason: 'no puede decir «no había nada mío» y «cubrí esto» a la vez');
    });

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

    test('el PROGRAMA también se captura una vez, no dos', () async {
      // `argumentos` se capturaba una vez y `programa` se leía dos: una para
      // el texto del testigo y otra para la invocación real. Con las
      // implementaciones de hoy no falla —las dos devuelven una constante—,
      // así que sin un paso que cambie no habría forma de que este guardia
      // dispare nunca. Un control que no puede fallar no está probado.
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final paso =
          _ProgramaInestable(ejecutor: ejecutor, directorio: raiz.path);
      final o = await paso.run(['lib/']);
      expect(o.witness!.invocation, ejecutor.invocaciones.single,
          reason: 'el testigo tiene que nombrar el programa que se invocó, no '
              'otra lectura del mismo getter');
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

  group('FormatCheck · la cuenta se reconcilia, no se toma como suficiente',
      () {
    // Que la herramienta haya mirado ALGO no dice que haya mirado lo que se le
    // pidió. Un review lo reprodujo: dos sujetos de un archivo cada uno y un
    // resumen que decía «1 file» certificaba los dos.
    setUp(() {
      Directory('${raiz.path}/dos').createSync();
      File('${raiz.path}/dos/b.dart').writeAsStringSync('void main() {}\n');
    });

    test('miró menos archivos de los que hay: no se certifica ninguno',
        () async {
      final o = await formato(salida(
              estandar: 'Formatted 1 file (0 changed) in 0.00 seconds.\n'))
          .run(['lib/', 'dos']);
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness!.subjects, isEmpty);
      expect(o.witness!.omitted.join(), contains('No cierra'));
    });

    test('miró todos: certifica los dos sujetos', () async {
      final o = await formato(salida(
              estandar: 'Formatted 2 files (0 changed) in 0.00 seconds.\n'))
          .run(['lib/', 'dos']);
      expect(o.verdict, Verdict.verde);
      expect(o.witness!.subjects, ['lib/', 'dos']);
    });

    test('los que no parsean cuentan del lado de la herramienta', () async {
      // La herramienta los salta, así que no entran en «Formatted N». Sin
      // sumarlos de vuelta, todo archivo corrupto volvería no concluyente el
      // alcance entero.
      File('${raiz.path}/dos/roto.dart').writeAsStringSync('void main( {\n');
      final o = await formato(salida(
        codigo: 65,
        estandar: 'Formatted 2 files (0 changed) in 0.00 seconds.\n',
        error: 'Could not format because the source could not be parsed:\n'
            "line 2, column 1 of dos/roto.dart: Expected to find '}'.\n"
            "line 2, column 1 of dos/roto.dart: Expected an identifier.\n",
      )).run(['lib/', 'dos']);
      expect(o.verdict, Verdict.rojo,
          reason: 'tres archivos: dos formateados y uno que no parsea');
      expect(o.witness!.subjects, ['lib/', 'dos']);
      expect(o.witness!.omitted.join(), contains('no parsean'));
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

/// Un paso cuyo `programa` cambia en cada lectura. Existe para que el guardia
/// de «capturar una vez» tenga cómo fallar.
final class _ProgramaInestable extends PasoDeCascada {
  _ProgramaInestable({required super.ejecutor, required super.directorio});

  int _lecturas = 0;

  @override
  String get id => 'ProgramaInestable';

  @override
  String get programa => 'herramienta-${_lecturas++}';

  @override
  List<String> argumentos(List<String> sujetos) => ['format', ...sujetos];

  @override
  Set<int> get codigosDeCorrida => const {0};

  @override
  DiagnosticNormalizer get normalizador => const NormalizadorDeFormato();

  @override
  String ensamblar(ResultadoDeProceso r) => r.salidaEstandar;

  @override
  Cobertura cobertura(Alcance alcance, QuotedText salida) =>
      (cubierto: alcance.sanos, omitido: const []);
}
