/// Dobles y ayudantes que comparten las suites del CLI.
library;

import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_fake/plugin_fake.dart';

/// Un testigo, con lo mínimo para que el invariante no lo rechace: si no
/// cubre ningún sujeto, tiene que traer al menos una omisión.
Witness testigo({
  List<String> sujetos = const ['.'],
  List<Omission> omite = const [],
}) =>
    Witness(
      invocation: 'herramienta --sobre ${sujetos.join(" ")}',
      subjects: sujetos,
      omitted: omite,
      exitCode: 0,
      finishedAt: DateTime.utc(2026),
    );

/// Un paso de doble propósito: sus fábricas cubren `subjects` tal como
/// llegan, así que sirven con cualquier alcance que la corrida les dé, no
/// solo con uno fijado de antemano.
class Paso implements Verifier {
  @override
  final String id;
  final List<Diagnostic> diagnosticos;
  final bool ciego;
  final String? nota;
  final Object? lanza;

  Paso(
    this.id, {
    this.diagnosticos = const [],
    this.ciego = false,
    this.nota,
    this.lanza,
  });

  factory Paso.verde(String id) => Paso(id);

  /// Un paso que empezó y no llegó a terminar. El alcance que recibe no
  /// importa para el desenlace —el `Attempt` no lo declara sano ni ajeno—,
  /// así que sirve igual con un alcance enteramente del stack.
  factory Paso.abortado(String id,
          {String nota = 'la herramienta no llegó a producir un resultado'}) =>
      Paso(id, nota: nota);

  factory Paso.rojo(String id) => Paso(id, diagnosticos: [
        Diagnostic(
            file: 'lib/a.txt',
            line: 3,
            severity: Severity.bloquea,
            ruleId: 'regla-x',
            message: const QuotedText('el mensaje', source: 'test')),
      ]);

  /// Un paso con las tres severidades a la vez.
  factory Paso.mixto(String id) => Paso(id, diagnosticos: [
        for (final s in Severity.values)
          Diagnostic(
              file: 'lib/${s.name}.txt',
              severity: s,
              ruleId: 'r-${s.name}',
              message: QuotedText('mensaje-${s.name}', source: 'test')),
      ]);

  /// Un paso cuya herramienta no informa qué miró: testigo sin sujetos,
  /// noConcluyente por construcción.
  factory Paso.ciego(String id) => Paso(id, ciego: true);

  @override
  Future<VerificationOutcome> run(VerificationScope alcance) async {
    final subjects = alcance.subjects;
    if (lanza != null) throw lanza!;
    if (nota != null) {
      return Aborted(
        attempt: Attempt(
          invocation: 'herramienta --sobre ${subjects.join(" ")}',
          subjects: subjects,
          termination: Termination.tiempoAgotado,
          exitCode: -1,
          note: nota!,
          finishedAt: DateTime.utc(2026),
        ),
      );
    }
    if (ciego) {
      return Executed(
        witness: Witness(
          invocation: 'herramienta --sobre ${subjects.join(" ")}',
          subjects: const [],
          omitted: [
            Omission(reason: 'algo que no se miró'),
          ],
          exitCode: 0,
          finishedAt: DateTime.utc(2026),
        ),
        diagnostics: diagnosticos,
      );
    }
    return Executed(
      witness: testigo(sujetos: subjects),
      diagnostics: diagnosticos,
    );
  }
}

/// Un paso que cubre exactamente los sujetos que se le declaran.
///
/// Sirve para las pruebas del libro de obligaciones, donde importa que un
/// paso cubra un subconjunto propio del alcance y no «lo que le llegó».
class PasoQueCubre implements Verifier {
  @override
  final String id;
  final List<String> cubre;
  final List<Omission> omite;
  PasoQueCubre(this.id, this.cubre, {this.omite = const []});

  @override
  Future<VerificationOutcome> run(VerificationScope alcance) async => Executed(
        witness: Witness(
          invocation: 'herramienta ${cubre.join(" ")}',
          subjects: cubre,
          omitted: omite,
          exitCode: 0,
          finishedAt: DateTime.utc(2026),
        ),
        diagnostics: const [],
      );
}

/// Un observador falso que declara del stack, con un archivo cada uno, los
/// sujetos dados.
ObservadorDeAlcanceFalso _observadorPara(List<String> sujetos) =>
    ObservadorDeAlcanceFalso(observados: {
      for (final s in sujetos)
        s: ObservedSubject(subject: s, ofStack: true, files: 1),
    });

/// Los sujetos que le tocan a `verify` a partir de sus argumentos: los que no
/// empiezan con `-`, o `.` si no hay ninguno. Es la misma regla que
/// `opcionesDe` aplica — reproducida acá para que el doble por defecto
/// declare exactamente lo que la corrida real va a pedir.
List<String> _sujetosDe(List<String> args) {
  final i = args.indexOf('verify');
  final resto = i < 0 ? args : args.sublist(i + 1);
  final sujetos = resto.where((a) => !a.startsWith('-')).toList();
  return sujetos.isEmpty ? const ['.'] : sujetos;
}

/// Corre `verify` con un observador de alcance falso que declara del stack
/// los sujetos dados. Sin esto, cada prueba del CLI tendría que tocar el
/// disco.
Future<(int, String)> correrConAlcance(
    List<String> sujetos, List<Verifier> pasos) {
  final obs = _observadorPara(sujetos);
  return correr(sujetos, pasos,
      construir: (_) => Cascada(pasos, observador: obs));
}

/// Una salida que se rompe **al escribir el terminal de un paso**.
///
/// El `StringSink` es el único punto por donde el terminal llega al
/// consumidor, así que romperlo acá es la ÚNICA forma de provocar de verdad
/// «el `started` quedó abierto». Antes esto se simulaba lanzando desde el
/// callback posterior al terminal, y esa simulación era falsa: el terminal ya
/// se había escrito, el consumidor lo tenía, y el arnés lo declaraba no
/// entregado igual. La prueba pasaba y consolidaba la contradicción.
class SalidaQueFallaEnElTerminal implements StringSink {
  final StringBuffer entregado = StringBuffer();
  final String cuandoContenga;
  var _fallo = false;

  SalidaQueFallaEnElTerminal({required this.cuandoContenga});

  @override
  void writeln([Object? obj = '']) {
    final texto = '$obj';
    if (!_fallo && texto.contains(cuandoContenga)) {
      _fallo = true;
      throw StateError('canal roto al escribir el terminal');
    }
    entregado.writeln(texto);
  }

  @override
  void write(Object? obj) => entregado.write(obj);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      entregado.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => entregado.writeCharCode(charCode);
}

/// Corre `verify` con una salida que se rompe justo al escribir el terminal
/// del paso `A`. Es el canal roto de verdad: el consumidor recibe el
/// `started` de `A` y nunca su terminal.
Future<(int, String)> invocarConTerminalRoto() async {
  final obs = _observadorPara(const ['lib']);
  final out = SalidaQueFallaEnElTerminal(cuandoContenga: '"stage":"executed"');
  final c = await ejecutar(
    const ['verify', 'lib', '--json'],
    directorio: '.',
    salida: out,
    error: StringBuffer(),
    construirCascada: (_) => Cascada([
      PasoQueCubre('A', const ['lib']),
      PasoQueCubre('B', const ['lib'])
    ], observador: obs),
  );
  return (c, out.entregado.toString());
}

/// Corre `verify` con un fallo **posterior** al terminal: el desenlace se
/// entregó y la emisión se rompió después. Es error del arnés, pero no un
/// `started` sin cerrar, y el resultado no puede decir que lo sea.
Future<(int, String)> invocarConFalloDespuesDelTerminal() async {
  final obs = _observadorPara(const ['lib']);
  final out = StringBuffer();
  var primero = true;
  final c = await ejecutar(
    const ['verify', 'lib', '--json'],
    directorio: '.',
    salida: out,
    error: StringBuffer(),
    construirCascada: (_) => Cascada([
      PasoQueCubre('A', const ['lib']),
      PasoQueCubre('B', const ['lib'])
    ], observador: obs),
    alTerminarDeProgreso: (_, __) {
      if (primero) {
        primero = false;
        throw StateError('se rompió DESPUÉS del terminal');
      }
    },
  );
  return (c, out.toString());
}

/// Corre la invocación ENTERA por la frontera, no solo `verify`. Es lo que
/// hace el binario, y es donde estaban los agujeros del protocolo.
///
/// **Sin `construir` explícito**, arma un observador que declara del stack,
/// con un archivo cada uno, exactamente los sujetos que esta invocación va a
/// pedir — el mismo cálculo que hace `opcionesDe`. Así, cualquier prueba que
/// no le importe el alcance puede ignorarlo del todo.
Future<(int, String, String)> invocar(List<String> args, List<Verifier> pasos,
    {Cascada Function(String)? construir}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final c = await ejecutar(
    args,
    directorio: '.',
    salida: out,
    error: err,
    construirCascada: construir ??
        (_) => Cascada(pasos, observador: _observadorPara(_sujetosDe(args))),
  );
  return (c, out.toString(), err.toString());
}

/// Lo mismo, para los casos donde solo importan código y salida.
Future<(int, String)> correr(List<String> args, List<Verifier> pasos,
    {Cascada Function(String)? construir}) async {
  final (c, out, _) =
      await invocar(['verify', ...args], pasos, construir: construir);
  return (c, out);
}

List<Map<String, Object?>> lineas(String salida) => [
      for (final l in salida.trim().split('\n'))
        jsonDecode(l) as Map<String, Object?>,
    ];
