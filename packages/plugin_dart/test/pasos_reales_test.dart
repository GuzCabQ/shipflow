/// Los pasos contra la toolchain de verdad.
///
/// **Esto cierra el residuo declarado de la suite de contrato.** Ahí las
/// muestras son salida capturada pero congelada: si la herramienta cambiara de
/// formato, aquella suite seguiría verde contra un formato que ya nadie emite.
/// Acá la salida la produce la herramienta instalada, ahora.
///
/// Y prueba de punta a punta el hallazgo que motiva la rebanada: **con un
/// alcance que no existe, el formateador sale con código 0** — y el paso NO da
/// verde. Eso no se puede probar con un ejecutor declarado, porque el ejecutor
/// declarado es justamente donde uno escribiría lo que cree que pasa.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory raiz;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('pasos_reales_');
    File('${raiz.path}/pubspec.yaml')
        .writeAsStringSync('name: sujeto\nenvironment:\n  sdk: ^3.0.0\n');
    Directory('${raiz.path}/lib').createSync();
  });

  tearDown(() => raiz.deleteSync(recursive: true));

  void fuente(String nombre, String contenido) =>
      File('${raiz.path}/lib/$nombre').writeAsStringSync(contenido);

  PasoDeFormato formato() => PasoDeFormato(
      ejecutor: const EjecutorDelSistema(),
      directorio: raiz.path,
      presupuesto: const Duration(minutes: 2));

  PasoDeAnalisis analisis() => PasoDeAnalisis(
      ejecutor: const EjecutorDelSistema(),
      directorio: raiz.path,
      presupuesto: const Duration(minutes: 2));

  test('la herramienta calla sobre lo que no existe, y el paso no', () async {
    // **La premisa, medida contra la herramienta real y no supuesta.** Es la
    // razón de ser de toda la defensa: sobre una ruta inexistente esta
    // herramienta sale con CERO, así que creerle al código de salida sería un
    // verde sobre algo que nadie miró. Si esto dejara de ser 0, la herramienta
    // cambió y este paso necesita menos defensa de la que tiene.
    final r = await const EjecutorDelSistema().correr(
        'dart', const ['format', '--output=none', 'no/existe/'],
        directorio: raiz.path, presupuesto: const Duration(minutes: 2));
    expect(r.codigo, 0);

    // Y la propiedad: el paso no le cree. Ya ni siquiera la invoca — descarta
    // el sujeto antes— pero lo que se comprueba es el desenlace, no el
    // mecanismo: un test que fija el mecanismo convierte toda mejora en una
    // falsa alarma.
    final o = await formato().run(['no/existe/']);
    expect(o.verdict, Verdict.noConcluyente);
    expect(o.witness!.subjects, isEmpty);
    expect(o.witness!.ownSubjects, isNull,
        reason: 'no se pudo establecer cuántos había: no es cero');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('un alcance inexistente lo delata el ARNÉS, no la herramienta',
      () async {
    // Antes esto se apoyaba en que el analizador saliera con código 64: la
    // ruta inexistente le llegaba a la herramienta y ella se quejaba. Ahora el
    // arnés la descarta antes de invocar —un sujeto descartado no puede llegar
    // a la toolchain— y lo delata por su propia cuenta.
    //
    // Es más fuerte, no menos: el caso ciego deja de depender de que una
    // herramienta ajena se moleste en avisar. Lo que se comprueba es la
    // propiedad, no el mecanismo.
    final o = await analisis().run(['no/existe/']);
    expect(o.verdict, Verdict.noConcluyente);
    expect(o.witness!.ownSubjects, isNull,
        reason: 'no se pudo establecer cuántos había: no es cero');
    expect(o.witness!.omitted.join(' '), contains('no existe'));
    expect(o.witness!.invocation, isEmpty,
        reason: 'no había nada utilizable que pasarle a la herramienta');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('código limpio y formateado da verde en los dos pasos', () async {
    fuente('bien.dart', 'void main() {\n  print(1);\n}\n');
    expect((await formato().run(['lib/'])).verdict, Verdict.verde);
    expect((await analisis().run(['lib/'])).verdict, Verdict.verde);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('un archivo sin formatear lo encuentra el paso real', () async {
    fuente('feo.dart', 'void a(){int   x=1;print(x);}\n');
    final o = await formato().run(['lib/']);
    expect(o.verdict, Verdict.rojo);
    expect(o.diagnostics.single.file, contains('feo'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('S4 · un archivo que no parsea produce diagnóstico, no salto silencioso',
      () async {
    fuente('roto.dart', 'void main( {\n');
    final o = await formato().run(['lib/']);
    expect(o.diagnostics.map((d) => d.ruleId), contains('formato/no-parsea'),
        reason: 'es el criterio de salida S4 de la fase, contra la '
            'herramienta de verdad');
    expect(o.verdict, isNot(Verdict.verde));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('el analizador real encuentra un error de tipos y lo pone en rojo',
      () async {
    fuente('malo.dart', 'void main() {\n  String x = 3;\n  print(x);\n}\n');
    final o = await analisis().run(['lib/']);
    expect(o.verdict, Verdict.rojo);
    expect(o.diagnostics.single.severity, Severity.bloquea);
    expect(o.diagnostics.single.line, 2);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('alcance mixto real: no certifica lo que la herramienta no encontró',
      () async {
    // La reproducción exacta del review, contra la toolchain instalada.
    fuente('bien.dart', 'void main() {\n  print(1);\n}\n');
    final o = await formato().run(['lib/', 'no/existe']);
    expect(o.witness!.exitCode, 0,
        reason: 'la herramienta no delata el sujeto que falta; el paso sí');
    expect(o.witness!.subjects, ['lib/']);
    expect(o.witness!.omitted.join(), contains('no/existe'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('la reconciliación cierra contra la toolchain de verdad', () async {
    // El test que atrapa un error en la REGLA de conteo. Los unitarios usan un
    // resumen que yo escribo; acá el número lo pone la herramienta, así que si
    // mi forma de contar el alcance no coincide con la suya, esto se pone rojo
    // en vez de dejar todo no concluyente en silencio.
    fuente('uno.dart', 'void main() {\n  print(1);\n}\n');
    Directory('${raiz.path}/otro').createSync();
    File('${raiz.path}/otro/dos.dart')
        .writeAsStringSync('void main() {\n  print(2);\n}\n');
    // Lo que cuelga de una carpeta oculta la herramienta lo salta; el arnés
    // tiene que saltarlo igual o la cuenta no cierra nunca.
    Directory('${raiz.path}/otro/.escondido').createSync();
    File('${raiz.path}/otro/.escondido/tres.dart')
        .writeAsStringSync('void  main( ){}\n');

    final o = await formato().run(['lib/', 'otro']);
    expect(o.verdict, Verdict.verde);
    expect(o.witness!.subjects, ['lib/', 'otro']);
  }, timeout: const Timeout(Duration(minutes: 3)));

  group('EjecutorDelSistema', () {
    test('una herramienta que no está no se lee como «no encontró nada»',
        () async {
      final r = await const EjecutorDelSistema().correr(
          'no-existe-esta-herramienta', const [],
          directorio: raiz.path, presupuesto: const Duration(seconds: 30));
      expect(r.terminacion, Termination.herramientaAusente);
      expect(r.codigo, -1,
          reason: 'no hubo código: la marca es la terminación');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('el presupuesto agotado mata el proceso Y espera a que muera',
        () async {
      // Antes devolvía sin esperar el código de salida ni el drenado de las
      // corrientes, así que la evidencia decía «tiempo agotado» mientras el
      // proceso todavía estaba vivo.
      final reloj = Stopwatch()..start();
      final r = await const EjecutorDelSistema().correr(
          'sh', const ['-c', 'sleep 30'],
          directorio: raiz.path,
          presupuesto: const Duration(milliseconds: 200));
      reloj.stop();
      expect(r.terminacion, Termination.tiempoAgotado);
      expect(reloj.elapsed, lessThan(const Duration(seconds: 10)),
          reason: 'la limpieza es acotada: no puede colgar la corrida');
    },
        timeout: const Timeout(Duration(minutes: 2)),
        onPlatform: const {'windows': Skip('sh no está')});

    test('una salida que no se puede decodificar no se degrada en silencio',
        () async {
      // Reemplazaba los bytes inválidos, y eso contradice a QuotedText, que
      // promete el texto «tal cual llegó». El invariante es el del tipo, NO
      // INV-6: INV-6 dice que el texto externo se encapsula, que es contra la
      // inyección y no sobre fidelidad de bytes. Un review lo citó mal y esta
      // línea lo repetía.
      //
      // **Los bytes los escribe Dart, no el shell.** La versión anterior hacía
      // `printf "\xff\xfe"` y eso NO es portable: `bash` en modo sh
      // interpreta la secuencia y emite dos bytes inválidos; `dash` —que es el
      // `sh` de la máquina de CI— la emite literal, ocho caracteres ASCII
      // perfectamente decodificables. El fixture nunca produjo lo que decía
      // producir, y el test pasaba en una plataforma y fallaba en la otra por
      // una razón que no era la que enunciaba.
      final archivo = File('${raiz.path}/bytes.bin')
        ..writeAsBytesSync(const [0xff, 0xfe, 0xff]);

      // **El fixture comprueba su propia premisa.** Sin esto puede volver a
      // pasar —o fallar— por la razón equivocada, y nadie se entera.
      expect(() => const Utf8Decoder().convert(archivo.readAsBytesSync()),
          throwsFormatException,
          reason:
              'si estos bytes fueran decodificables, lo de abajo no estaría '
              'probando lo que dice probar');

      final r = await const EjecutorDelSistema().correr('cat', [archivo.path],
          directorio: raiz.path, presupuesto: const Duration(seconds: 30));
      expect(r.terminacion, Termination.interrumpida);
      expect(r.salidaDeError, contains('No se pudo leer'));
    },
        timeout: const Timeout(Duration(minutes: 2)),
        onPlatform: const {'windows': Skip('cat no está')});
  });
}
