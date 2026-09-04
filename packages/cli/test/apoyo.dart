/// Dobles y ayudantes que comparten las suites del CLI.
library;

import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';

/// **Declara cuántos elementos eran suyos.** Omitirlo lo deja en `null`, que
/// significa «no se pudo establecer» y por sí solo impide el verde: un doble
/// que no lo declara estaría probando otra cosa.
Witness testigo({List<String> sujetos = const ['lib/'], int propios = 2}) =>
    Witness(
      invocation: 'herramienta --sobre lib/',
      subjects: sujetos,
      omitted: const ['algo que no se miró'],
      termination: Termination.completa,
      exitCode: 0,
      ownSubjects: propios,
      finishedAt: DateTime.utc(2026),
    );

class Paso implements Verifier {
  @override
  final String id;
  final VerificationOutcome? devuelve;
  final Object? lanza;
  Paso(this.id, {this.devuelve, this.lanza});

  factory Paso.verde(String id) => Paso(id,
      devuelve: VerificationOutcome(
          verifierId: id, diagnostics: const [], witness: testigo()));

  factory Paso.rojo(String id) => Paso(id,
      devuelve: VerificationOutcome(
        verifierId: id,
        witness: testigo(),
        diagnostics: [
          Diagnostic(
              file: 'lib/a.txt',
              line: 3,
              severity: Severity.bloquea,
              ruleId: 'regla-x',
              message: const QuotedText('el mensaje', source: 'test')),
        ],
      ));

  /// Un paso con las tres severidades a la vez.
  factory Paso.mixto(String id) => Paso(id,
      devuelve: VerificationOutcome(
        verifierId: id,
        witness: testigo(),
        diagnostics: [
          for (final s in Severity.values)
            Diagnostic(
                file: 'lib/${s.name}.txt',
                severity: s,
                ruleId: 'r-${s.name}',
                message: QuotedText('mensaje-${s.name}', source: 'test')),
        ],
      ));

  factory Paso.ciego(String id) => Paso(id,
      devuelve: VerificationOutcome(
          verifierId: id,
          diagnostics: const [],
          witness: testigo(sujetos: const [])));

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    if (lanza != null) throw lanza!;
    return devuelve!;
  }
}

/// Corre la invocación ENTERA por la frontera, no solo `verify`. Es lo que
/// hace el binario, y es donde estaban los agujeros del protocolo.
Future<(int, String, String)> invocar(List<String> args, List<Verifier> pasos,
    {Cascada Function(String)? construir}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final c = await ejecutar(args,
      directorio: '.',
      salida: out,
      error: err,
      construirCascada: construir ?? (_) => Cascada(pasos));
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
