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

  test('un alcance que NO existe sale con código 0 y aun así no es verde',
      () async {
    // El hallazgo entero de esta rebanada, contra la herramienta real.
    final o = await formato().run(['no/existe/']);
    expect(o.witness!.exitCode, 0,
        reason: 'si esto dejara de ser 0, la herramienta cambió y este paso '
            'necesita menos defensa de la que tiene');
    expect(o.verdict, Verdict.noConcluyente);
    expect(o.witness!.subjects, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('el analizador sí delata el alcance inexistente, con su código',
      () async {
    final o = await analisis().run(['no/existe/']);
    expect(o.verdict, Verdict.noConcluyente);
    expect(o.witness!.exitCode, 64,
        reason: 'es el único caso ciego que esta herramienta delata sola');
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

  test('la herramienta que no está no se lee como «no encontró nada»',
      () async {
    final paso = PasoDeFormato(
        ejecutor: const EjecutorDelSistema(),
        directorio: raiz.path,
        presupuesto: const Duration(seconds: 30));
    // Se cambia el programa por uno que no existe usando el mismo ejecutor
    // real: es la única forma de probar que el ejecutor real mapea la ausencia.
    final r = await const EjecutorDelSistema().correr(
        'no-existe-esta-herramienta', const [],
        directorio: raiz.path, presupuesto: const Duration(seconds: 30));
    expect(r.terminacion, Termination.herramientaAusente);
    expect(paso.id, 'FormatCheck');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
