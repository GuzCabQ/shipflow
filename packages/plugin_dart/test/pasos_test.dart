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

  group('el desenlace de un alcance sin sujetos utilizables', () {
    test('un alcance sin sujetos utilizables es precondición violada',
        () async {
      // Antes devolvía un testigo con terminación interrumpida y código -1
      // sobre una herramienta que nunca corrió. La cascada no puede pasarle
      // esto: si llega, es error del arnés, no un desenlace del cambio.
      final paso = PasoDeFormato(
          ejecutor: EjecutorDeclarado(salida()), directorio: raiz.path);
      expect(() => paso.run(const []), throwsArgumentError);
    });

    test('si NINGÚN sujeto es utilizable, también es precondición violada',
        () async {
      // Dos sujetos que no existen: ninguno del stack, ninguno mirable.
      expect(
          () => formato(salida(estandar: formatoLimpio))
              .run(['no/existe', 'tampoco/esta']),
          throwsArgumentError);
    });

    test(
        'un alcance que no se puede mirar por completo es precondición '
        'violada, no un dato', () async {
      // Un directorio sin permisos hacía que `run` devolviera un testigo
      // «no concluyente»; ahora, si ES EL ÚNICO sujeto pedido, no hay ningún
      // sujeto utilizable y la corrida ni empieza.
      final vedado = Directory('${raiz.path}/vedado')..createSync();
      Process.runSync('chmod', ['000', vedado.path]);
      addTearDown(() => Process.runSync('chmod', ['755', vedado.path]));
      expect(() => analisis(salida(estandar: analisisLimpio)).run(['vedado']),
          throwsArgumentError);
    }, onPlatform: const {'windows': Skip('los permisos POSIX no aplican')});
  });

  group('lo que vale para cualquier paso', () {
    test('el paso NO mira el árbol por su cuenta: le pregunta al observador',
        () async {
      // Si el paso siguiera decidiendo qué es suyo, seguiría siendo juez de su
      // propia incumbencia. Con un observador que declara `lib` ajeno, no
      // queda ningún sujeto utilizable: la corrida ni invoca nada.
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
      await expectLater(() => paso.run(['lib']), throwsArgumentError);
      expect(ejecutor.invocaciones, isEmpty);
      expect(falso.llamadas, hasLength(1),
          reason: 'una sola foto del árbol por corrida de paso');
    });

    test(
        'el ABORTO por discrepancia nombra los sujetos en el orden en que se '
        'PIDIERON, no el orden en que el observador los clasificó', () async {
      // Antes esta prueba comprobaba el orden de las OMISIONES de un
      // `Executed`: `separar` recorría los pedidos uno por uno, y agrupar
      // `observed`/`unobserved` como dos bloques separados invertía ese
      // orden apenas una corrida mezclaba un sujeto ajeno con uno
      // inobservable.
      //
      // Con la tarea 8b ninguno de los dos llega a una omisión: 'fantasma'
      // (inobservable) y 'ajeno' (no es del stack) son, los dos, sujetos que
      // la propia observación del paso no reconoce como utilizables, y eso
      // ahora aborta la corrida entera en vez de saldar su obligación en
      // silencio. Lo que sigue valiendo es que el orden en la evidencia sale
      // del pedido, no de cómo el observador los clasificó.
      final falso = ObservadorDeAlcanceFalso(
        observados: {
          'ajeno': ObservedSubject(
              subject: 'ajeno',
              ofStack: false,
              files: 0,
              reason: 'el observador dice que no es del stack'),
          'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
        },
        noObservados: {'fantasma': 'el observador dice que no se pudo mirar'},
      );
      final paso = PasoDeFormato(
          ejecutor: EjecutorDeclarado(salida(estandar: formatoLimpio)),
          directorio: raiz.path,
          observador: falso);
      final o = await paso.run(['fantasma', 'ajeno', 'lib']);
      expect(o, isA<Aborted>());
      final nota = (o as Aborted).attempt.note;
      expect(nota, contains('fantasma'));
      expect(nota, contains('ajeno'));
      expect(nota.indexOf('fantasma'), lessThan(nota.indexOf('ajeno')),
          reason: 'el pedido nombró primero a fantasma; si el paso agrupara '
              'por clasificación en vez de recorrer el pedido, este orden '
              'saldría invertido y ninguna otra prueba lo notaría');
    });

    test('un sujeto ajeno al stack ABORTA la corrida: no llega ni él ni nada',
        () async {
      // `separar` clasificaba bien y la invocación se armaba igual con TODOS
      // los pedidos: `verify README.md` le daba el markdown a la herramienta
      // del stack, que intentaba parsearlo y devolvía diagnósticos sobre un
      // archivo que no es de su incumbencia. Afecta a cualquier cambio normal
      // que mezcle código y documentación. Lo cobró un review.
      //
      // La corrección original dejaba seguir al paso, certificando
      // 'lib/a.dart' e invocando la herramienta solo sobre lo utilizable. La
      // tarea 8b endurece esto: un sujeto que la propia observación del paso
      // encuentra ajeno es la misma señal de alcance incoherente que un
      // sujeto que cambió, así que ahora aborta ANTES de invocar nada — ni
      // siquiera sobre 'lib/a.dart', que sí era del stack.
      File('${raiz.path}/lib/LEEME.md').writeAsStringSync('# prosa\n');
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final paso = PasoDeFormato(ejecutor: ejecutor, directorio: raiz.path);
      final o = await paso.run(['lib/a.dart', 'lib/LEEME.md']);

      expect(o, isA<Aborted>());
      expect((o as Aborted).attempt.note, contains('lib/LEEME.md'),
          reason: 'la evidencia tiene que nombrar el sujeto que discrepó');
      expect(ejecutor.invocaciones, isEmpty,
          reason: 'no se invoca la herramienta sobre un alcance incoherente, '
              'ni siquiera sobre el sujeto que sí era del stack');
    });

    test('un código de salida desconocido deja el resultado no concluyente',
        () async {
      // Una herramienta que devuelve algo que no entendemos no dice «no tuve
      // nada que hacer»: dice «no sé». Lo pidió una mutación.
      final o = await formato(salida(codigo: 64)).run(['lib']) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness.omitted.map((x) => x.reason).join(), contains('64'));
    });

    test('el testigo sale de UNA sola foto del árbol', () async {
      // Si el alcance se mira dos veces —una para el conteo y otra para la
      // cobertura, con un `await` en el medio— el testigo puede reconciliar
      // contra un archivo que apareció DESPUÉS de la foto. Lo reprodujo un
      // review con un ejecutor que creaba un archivo durante la espera:
      // si la cuenta se repitiera, el resumen «Formatted 1 file» dejaría de
      // cerrar contra los DOS archivos que habría entonces, y el paso se
      // volvería no concluyente en vez de verde.
      final paso = PasoDeFormato(
          ejecutor: _EjecutorQueCreaUnArchivo(
              '${raiz.path}/lib', salida(estandar: formatoLimpio)),
          directorio: raiz.path);
      final o = await paso.run(['lib']) as Executed;
      expect(o.verdict, Verdict.verde);
      expect(o.witness.subjects, ['lib']);
    });

    test('la herramienta ausente devuelve Abortado, no un testigo', () async {
      final o = await formato(salida(
              terminacion: Termination.herramientaAusente,
              codigo: -1,
              error: 'No such file or directory'))
          .run(['lib']);
      expect(o, isA<Aborted>());
      expect(
          (o as Aborted).attempt.termination, Termination.herramientaAusente);
      expect(o.attempt.note, isNotEmpty);
    });

    test('el presupuesto agotado declara los descendientes en la nota',
        () async {
      final o = await analisis(
              salida(terminacion: Termination.tiempoAgotado, codigo: -1))
          .run(['lib']);
      expect(o, isA<Aborted>());
      expect((o as Aborted).attempt.note, contains('descendientes'));
    });

    test('un código desconocido es Ejecutado no concluyente, con su omisión',
        () async {
      // La herramienta corrió y produjo un resultado: eso es completa por
      // definición. Que no sepamos leerlo es nuestro problema, y va en la
      // omisión — no se falsea la terminación.
      final o = await formato(salida(codigo: 111, estandar: formatoLimpio))
          .run(['lib']);
      expect(o, isA<Executed>());
      final e = o as Executed;
      expect(e.verdict, Verdict.noConcluyente);
      expect(e.witness.omitted.map((x) => x.reason).join(), contains('111'));
    });

    test(
        'una salida ilegible tampoco es una terminación distinta: sigue '
        'siendo Executed', () async {
      final o = await formato(salida(estandar: 'basura sin resumen'))
          .run(['lib']) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.diagnostics, isEmpty,
          reason: 'culpar al código del usuario de que el arnés no sepa leer '
              'sería mentir sobre dónde está la falla');
    });

    test('la lista del llamador no puede cambiar la evidencia', () async {
      // El review lo reprodujo: la lista mutaba durante el `await` y el
      // testigo terminaba nombrando una invocación sobre un alcance y
      // declarando cobertura sobre otro.
      final lista = ['lib'];
      final o = await PasoDeFormato(
        ejecutor: _MutaDurante(lista, salida(estandar: formatoLimpio)),
        directorio: raiz.path,
      ).run(lista) as Executed;
      expect(o.witness.subjects, ['lib']);
      expect(o.witness.invocation, contains('lib'));
      expect(o.witness.invocation, isNot(contains('no/existe')));
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
      final o = await paso.run(['lib']) as Executed;
      expect(o.witness.invocation, ejecutor.invocaciones.single,
          reason: 'el testigo tiene que nombrar el programa que se invocó, no '
              'otra lectura del mismo getter');
    });

    test('el testigo nombra la invocación que de verdad se hizo', () async {
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final o = await PasoDeFormato(ejecutor: ejecutor, directorio: raiz.path)
          .run(['lib']) as Executed;
      expect(ejecutor.invocaciones.single, o.witness.invocation);
    });
  });

  group('el paso no puede contradecir en silencio a la cascada', () {
    test('si la observación del paso discrepa de lo que le entregaron, ABORTA',
        () async {
      // La cascada observa una vez y entrega solo los sujetos utilizables. Si
      // el paso vuelve a mirar y ve otra cosa, el árbol cambió entre las dos
      // lecturas y la evidencia de la corrida dejó de ser coherente.
      //
      // Lo que NO puede hacer es descartar el sujeto y declararlo como
      // omisión con su sujeto: eso SALDA la obligación de ese par
      // paso-sujeto, y el sujeto queda sin verificar con la corrida en verde.
      // Falla abierto.
      final discrepante = ObservadorDeAlcanceFalso(observados: {
        'lib/a.dart':
            ObservedSubject(subject: 'lib/a.dart', ofStack: true, files: 1),
        'lib/b.dart': ObservedSubject(
            subject: 'lib/b.dart',
            ofStack: false,
            files: 0,
            reason: 'el árbol cambió entre las dos lecturas'),
      });
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final paso = PasoDeFormato(
          ejecutor: ejecutor, directorio: raiz.path, observador: discrepante);

      final o = await paso.run(['lib/a.dart', 'lib/b.dart']);

      expect(o, isA<Aborted>(),
          reason: 'no se puede concluir sobre un alcance que cambió debajo');
      expect((o as Aborted).attempt.termination, Termination.interrumpida);
      expect(o.attempt.note, contains('lib/b.dart'),
          reason: 'la evidencia tiene que nombrar el sujeto que discrepó');
      expect(ejecutor.invocaciones, isEmpty,
          reason: 'no se invoca la herramienta sobre un alcance incoherente');
    });

    test('y sin discrepancia sigue ejecutando normalmente', () async {
      // El control negativo: sin esto, un paso que abortara SIEMPRE pasaría
      // la prueba de arriba por la vía de no funcionar.
      final coherente = ObservadorDeAlcanceFalso(observados: {
        'lib/a.dart':
            ObservedSubject(subject: 'lib/a.dart', ofStack: true, files: 1),
      });
      final o = await PasoDeFormato(
              ejecutor: EjecutorDeclarado(salida(estandar: formatoLimpio)),
              directorio: raiz.path,
              observador: coherente)
          .run(['lib/a.dart']);
      expect(o, isA<Executed>());
      expect((o as Executed).verdict, Verdict.verde);
    });
  });

  group('cobertura POR SUJETO, no agregada', () {
    test('un sujeto que ya no existe ABORTA en vez de certificar lo demás',
        () async {
      // El falso verde que encontró el review: la herramienta miraba un
      // archivo y el paso devolvía TODOS los sujetos como cubiertos. La
      // corrección de entonces certificaba solo 'lib' y omitía 'no/existe'
      // con su nombre.
      //
      // La tarea 8b va más allá: una omisión con sujeto SALDA la obligación
      // de ese par paso-sujeto, así que 'no/existe' quedaría declarado sin
      // haber sido verificado de verdad. Que la propia observación del paso
      // ya no lo vea es la misma señal de alcance incoherente que un sujeto
      // que cambió entre las dos lecturas: aborta, y no certifica ni
      // siquiera 'lib'.
      final o = await formato(salida(estandar: formatoLimpio))
          .run(['lib', 'no/existe']);
      expect(o, isA<Aborted>());
      expect((o as Aborted).attempt.note, contains('no/existe'),
          reason: 'la evidencia tiene que nombrar el sujeto que discrepó');
    });

    test('un directorio que existe pero no tiene fuentes ABORTA la corrida',
        () async {
      // 'vacio' es justo el tipo de sujeto que la cascada no debería haber
      // entregado como utilizable: que la propia observación del paso lo
      // encuentre sin fuentes es la misma incoherencia de alcance que
      // cualquier otra discrepancia, y por eso aborta en vez de certificar
      // 'lib' y saldar la obligación de 'vacio' con una omisión que nadie
      // verificó.
      Directory('${raiz.path}/vacio').createSync();
      final o = await analisis(salida(estandar: analisisLimpio))
          .run(['lib', 'vacio']);
      expect(o, isA<Aborted>());
      expect((o as Aborted).attempt.note, contains('vacio'));
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
          .run(['lib', 'dos']) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness.subjects, isEmpty);
      expect(
          o.witness.omitted.map((x) => x.reason).join(), contains('No cierra'));
    });

    test('miró todos: certifica los dos sujetos', () async {
      final o = await formato(salida(
              estandar: 'Formatted 2 files (0 changed) in 0.00 seconds.\n'))
          .run(['lib', 'dos']) as Executed;
      expect(o.verdict, Verdict.verde);
      expect(o.witness.subjects, ['lib', 'dos']);
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
      )).run(['lib', 'dos']) as Executed;
      expect(o.verdict, Verdict.rojo,
          reason: 'tres archivos: dos formateados y uno que no parsea');
      expect(o.witness.subjects, ['lib', 'dos']);
      expect(o.witness.omitted.map((x) => x.reason).join(),
          contains('no parsean'));
    });
  });

  group('FormatCheck · sí puede ver su propia ceguera', () {
    test('cero archivos mirados NO es verde, aunque el código sea 0', () async {
      final o = await formato(salida(
        estandar: 'Formatted no files in 0.00 seconds.\n',
        error: 'No file or directory found at "lib".\n',
      )).run(['lib']) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness.subjects, isEmpty);
      expect(o.witness.omitted.map((x) => x.reason).join(),
          contains('NINGÚN archivo'));
    });

    test('un archivo mirado y limpio sí es verde', () async {
      final o = await formato(salida(estandar: formatoLimpio)).run(['lib'])
          as Executed;
      expect(o.verdict, Verdict.verde);
      expect(o.witness.subjects, ['lib']);
      expect(o.witness.omitted, isEmpty);
    });

    test('un archivo sin formatear pone el paso en rojo', () async {
      final o = await formato(salida(
              estandar: 'Changed lib/a.dart\n'
                  'Formatted 1 file (1 changed) in 0.0 seconds.\n'))
          .run(['lib']) as Executed;
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
      )).run(['lib']) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.diagnostics.single.ruleId, 'formato/no-parsea');
    });
  });

  group('StaticAnalysis · NO puede, y lo declara', () {
    test('declara siempre que no sabe qué archivos leyó la herramienta',
        () async {
      final o = await analisis(salida(estandar: analisisLimpio)).run(['lib'])
          as Executed;
      expect(o.witness.omitted.map((x) => x.reason).join(),
          contains('no informa qué archivos leyó'));
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
