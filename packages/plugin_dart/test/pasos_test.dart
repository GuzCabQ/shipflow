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

/// El alcance como lo observaría la cascada. **Los pasos ya no observan:
/// reciben** — cláusula 5 de `Verifier`.
Future<ScopeObservation> _alc(String raiz, List<String> sujetos) =>
    ObservadorDeAlcanceDart(directorio: raiz).observe(sujetos);

/// Una observación de la nada: partición válida de la lista vacía.
ScopeObservation _vacio() => ScopeObservation(
    requested: const [],
    observed: const [],
    unobserved: const [],
    observedAt: DateTime.utc(2026));

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
      expect(() => paso.run(_vacio()), throwsArgumentError);
    });

    test('si NINGÚN sujeto es utilizable, también es precondición violada',
        () async {
      // Dos sujetos que no existen: ninguno del stack, ninguno mirable.
      final alc = await _alc(raiz.path, const ['no/existe', 'tampoco/esta']);
      expect(() => formato(salida(estandar: formatoLimpio)).run(alc),
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
      final alc = await _alc(raiz.path, const ['vedado']);
      expect(() => analisis(salida(estandar: analisisLimpio)).run(alc),
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
      final paso = PasoDeFormato(ejecutor: ejecutor, directorio: raiz.path);
      final alc = await falso.observe(const ['lib']);
      await expectLater(() => paso.run(alc), throwsArgumentError);
      expect(ejecutor.invocaciones, isEmpty);
      expect(falso.llamadas, hasLength(1),
          reason: 'la ÚNICA foto del árbol la sacó quien compone; el paso no '
              'tiene con qué sacar otra');
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
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final paso = PasoDeFormato(ejecutor: ejecutor, directorio: raiz.path);
      final o = await paso
          .run(await falso.observe(const ['fantasma', 'ajeno', 'lib']));

      // **El paso invoca sobre lo utilizable y sobre nada más.** No aborta ni
      // omite: 'fantasma' y 'ajeno' no son incumbencia suya, y qué significan
      // lo decide la cascada —ADR-011 corolario 4—, que los tiene en
      // `unobserved` y entre los ajenos de esta misma observación.
      expect(o, isA<Executed>());
      expect((o as Executed).witness.invocation, contains('lib'));
      expect(o.witness.invocation, isNot(contains('fantasma')));
      expect(o.witness.invocation, isNot(contains('ajeno')));
      expect(ejecutor.invocaciones, hasLength(1));
    });

    test('un sujeto ajeno al stack no llega a la herramienta', () async {
      // `separar` clasificaba bien y la invocación se armaba igual con TODOS
      // los pedidos: `verify README.md` le daba el markdown a la herramienta
      // del stack, que intentaba parsearlo y devolvía diagnósticos sobre un
      // archivo que no es de su incumbencia. Lo cobró un review.
      //
      // Hubo una versión que endurecía esto hasta abortar la corrida entera
      // ante un ajeno. Era defensa contra un llamador que entregara sujetos
      // que él mismo había clasificado como no utilizables, y ese llamador ya
      // no se puede escribir: el paso recibe la observación y saca lo
      // utilizable de ahí. Un ajeno no es incoherencia, es la partición
      // haciendo su trabajo.
      File('${raiz.path}/lib/LEEME.md').writeAsStringSync('# prosa\n');
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final paso = PasoDeFormato(ejecutor: ejecutor, directorio: raiz.path);
      final o =
          await paso.run(await _alc(raiz.path, ['lib/a.dart', 'lib/LEEME.md']));

      expect(o, isA<Executed>());
      expect((o as Executed).witness.invocation, contains('lib/a.dart'));
      expect(o.witness.invocation, isNot(contains('LEEME.md')),
          reason: 'la herramienta del stack no parsea lo que no es suyo');
    });

    test('un código de salida desconocido deja el resultado no concluyente',
        () async {
      // Una herramienta que devuelve algo que no entendemos no dice «no tuve
      // nada que hacer»: dice «no sé». Lo pidió una mutación.
      final o = await formato(salida(codigo: 64))
          .run(await _alc(raiz.path, ['lib'])) as Executed;
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
      final o = await paso.run(await _alc(raiz.path, ['lib'])) as Executed;
      expect(o.verdict, Verdict.verde);
      expect(o.witness.subjects, ['lib']);
    });

    test('la herramienta ausente devuelve Abortado, no un testigo', () async {
      final o = await formato(salida(
              terminacion: Termination.herramientaAusente,
              codigo: -1,
              error: 'No such file or directory'))
          .run(await _alc(raiz.path, ['lib']));
      expect(o, isA<Aborted>());
      expect(
          (o as Aborted).attempt.termination, Termination.herramientaAusente);
      expect(o.attempt.note, isNotEmpty);
    });

    test('el presupuesto agotado declara los descendientes en la nota',
        () async {
      final o = await analisis(
              salida(terminacion: Termination.tiempoAgotado, codigo: -1))
          .run(await _alc(raiz.path, ['lib']));
      expect(o, isA<Aborted>());
      expect((o as Aborted).attempt.note, contains('descendientes'));
    });

    test('un código desconocido es Ejecutado no concluyente, con su omisión',
        () async {
      // La herramienta corrió y produjo un resultado: eso es completa por
      // definición. Que no sepamos leerlo es nuestro problema, y va en la
      // omisión — no se falsea la terminación.
      final o = await formato(salida(codigo: 111, estandar: formatoLimpio))
          .run(await _alc(raiz.path, ['lib']));
      expect(o, isA<Executed>());
      final e = o as Executed;
      expect(e.verdict, Verdict.noConcluyente);
      expect(e.witness.omitted.map((x) => x.reason).join(), contains('111'));
    });

    test(
        'una salida ilegible tampoco es una terminación distinta: sigue '
        'siendo Executed', () async {
      final o = await formato(salida(estandar: 'basura sin resumen'))
          .run(await _alc(raiz.path, ['lib'])) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.diagnostics, isEmpty,
          reason: 'culpar al código del usuario de que el arnés no sepa leer '
              'sería mentir sobre dónde está la falla');
    });

    test('la lista del llamador no puede cambiar la evidencia', () async {
      // El review lo reprodujo: la lista mutaba durante el `await` y el
      // testigo terminaba nombrando una invocación sobre un alcance y
      // declarando cobertura sobre otro.
      // **Ahora lo cierra el tipo.** `ScopeObservation` congela sus listas al
      // construirse, así que el paso ya no necesita copia defensiva: lo que
      // recibe no lo puede mutar nadie mientras él espera en el `await`.
      final lista = ['lib'];
      final alc = await _alc(raiz.path, lista);
      final o = await PasoDeFormato(
        ejecutor: _MutaDurante(lista, salida(estandar: formatoLimpio)),
        directorio: raiz.path,
      ).run(alc) as Executed;
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
      final o = await paso.run(await _alc(raiz.path, ['lib'])) as Executed;
      expect(o.witness.invocation, ejecutor.invocaciones.single,
          reason: 'el testigo tiene que nombrar el programa que se invocó, no '
              'otra lectura del mismo getter');
    });

    test('el testigo nombra la invocación que de verdad se hizo', () async {
      final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
      final o = await PasoDeFormato(ejecutor: ejecutor, directorio: raiz.path)
          .run(await _alc(raiz.path, ['lib'])) as Executed;
      expect(ejecutor.invocaciones.single, o.witness.invocation);
    });
  });

  // **Acá vivía el grupo «el paso no puede contradecir en silencio a la
  // cascada», y se fue con el mecanismo que probaba.** Sus dos pruebas
  // comprobaban que el paso abortara cuando su PROPIA observación discrepaba
  // de la que la cascada le había entregado. Ese abort existía solamente
  // porque el paso volvía a mirar el árbol, y era además una salvaguarda
  // falsa: comparaba nombres y no tamaños, así que un árbol de otro tamaño
  // con el sujeto todavía utilizable no divergía y la corrida salía verde
  // reportando un alcance que nadie había verificado.
  //
  // Con una sola lectura no hay dos fotos que reconciliar. Lo que la reemplaza
  // no es otra guardia: es la firma de `Verifier.run`, que no le da al paso
  // con qué pedir una segunda observación, y la prueba de integración sobre
  // `cascadaPorDefecto` que cuenta las lecturas de una corrida entera.

  group('cobertura POR SUJETO, no agregada', () {
    test('un sujeto que no se pudo observar no lo certifica ni lo decide',
        () async {
      // El falso verde que encontró el review: la herramienta miraba un
      // archivo y el paso devolvía TODOS los sujetos como cubiertos.
      //
      // Hubo una versión que abortaba ante 'no/existe'. Ya no: el paso no
      // decide qué significa un sujeto que no se pudo mirar —eso sería juzgar
      // su propia incumbencia, ADR-011 corolario 4—. Verifica lo utilizable y
      // no dice nada del resto. **Quien no lo deja pasar es la cascada**, que
      // con un `unobserved` no vacío levanta `alcanceNoObservable` y la
      // corrida entera deja de ser verde aunque este paso haya ejecutado
      // limpio. Esa mitad se prueba en `cascada_test`.
      final o = await formato(salida(estandar: formatoLimpio))
          .run(await _alc(raiz.path, ['lib', 'no/existe'])) as Executed;
      expect(o.witness.subjects, ['lib']);
      expect(o.witness.invocation, isNot(contains('no/existe')),
          reason: 'no se invoca la herramienta sobre lo que no se pudo mirar');
    });

    test('un directorio sin fuentes es ajeno, y el paso lo trata como tal',
        () async {
      // Medido con el observador de verdad: un directorio que existe y no
      // tiene ningún archivo de fuente vuelve OBSERVADO y no del stack, con
      // el motivo escrito. No es un sujeto que no se pudo mirar: se miró y no
      // había nada nuestro. El paso verifica 'lib' y no invoca sobre 'vacio'.
      Directory('${raiz.path}/vacio').createSync();
      final o = await analisis(salida(estandar: analisisLimpio))
          .run(await _alc(raiz.path, ['lib', 'vacio'])) as Executed;
      expect(o.witness.subjects, ['lib']);
      expect(o.witness.invocation, isNot(contains('vacio')));
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
          .run(await _alc(raiz.path, ['lib', 'dos'])) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness.subjects, isEmpty);
      expect(
          o.witness.omitted.map((x) => x.reason).join(), contains('No cierra'));
    });

    test('miró todos: certifica los dos sujetos', () async {
      final o = await formato(salida(
              estandar: 'Formatted 2 files (0 changed) in 0.00 seconds.\n'))
          .run(await _alc(raiz.path, ['lib', 'dos'])) as Executed;
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
      )).run(await _alc(raiz.path, ['lib', 'dos'])) as Executed;
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
      )).run(await _alc(raiz.path, ['lib'])) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.witness.subjects, isEmpty);
      expect(o.witness.omitted.map((x) => x.reason).join(),
          contains('NINGÚN archivo'));
    });

    test('un archivo mirado y limpio sí es verde', () async {
      final o = await formato(salida(estandar: formatoLimpio))
          .run(await _alc(raiz.path, ['lib'])) as Executed;
      expect(o.verdict, Verdict.verde);
      expect(o.witness.subjects, ['lib']);
      expect(o.witness.omitted, isEmpty);
    });

    test('un archivo sin formatear pone el paso en rojo', () async {
      final o = await formato(salida(
              estandar: 'Changed lib/a.dart\n'
                  'Formatted 1 file (1 changed) in 0.0 seconds.\n'))
          .run(await _alc(raiz.path, ['lib'])) as Executed;
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
      )).run(await _alc(raiz.path, ['lib'])) as Executed;
      expect(o.verdict, Verdict.noConcluyente);
      expect(o.diagnostics.single.ruleId, 'formato/no-parsea');
    });
  });

  group('StaticAnalysis · NO puede, y lo declara', () {
    test('declara siempre que no sabe qué archivos leyó la herramienta',
        () async {
      final o = await analisis(salida(estandar: analisisLimpio))
          .run(await _alc(raiz.path, ['lib'])) as Executed;
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
