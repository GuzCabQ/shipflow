/// El comando `verify`: interpretación, protocolo de salida y código.
///
/// **La cascada se inyecta.** Estas pruebas no invocan la toolchain: lo que se
/// prueba acá es la traducción entre el estado de una corrida y lo que ve
/// quien la consume — una persona o un script.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

Witness _testigo({List<String> sujetos = const ['lib/']}) => Witness(
      invocation: 'herramienta --sobre lib/',
      subjects: sujetos,
      omitted: const ['algo que no se miró'],
      termination: Termination.completa,
      exitCode: 0,
      finishedAt: DateTime.utc(2026),
    );

class _Paso implements Verifier {
  @override
  final String id;
  final VerificationOutcome? devuelve;
  final Object? lanza;
  _Paso(this.id, {this.devuelve, this.lanza});

  factory _Paso.verde(String id) => _Paso(id,
      devuelve: VerificationOutcome(
          verifierId: id, diagnostics: const [], witness: _testigo()));

  factory _Paso.rojo(String id) => _Paso(id,
      devuelve: VerificationOutcome(
        verifierId: id,
        witness: _testigo(),
        diagnostics: [
          Diagnostic(
              file: 'lib/a.txt',
              line: 3,
              severity: Severity.bloquea,
              ruleId: 'regla-x',
              message: const QuotedText('el mensaje', source: 'test')),
        ],
      ));

  factory _Paso.ciego(String id) => _Paso(id,
      devuelve: VerificationOutcome(
          verifierId: id,
          diagnostics: const [],
          witness: _testigo(sujetos: const [])));

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    if (lanza != null) throw lanza!;
    return devuelve!;
  }
}

/// Corre `verify` con una cascada declarada y devuelve código y salida.
Future<(int, String)> correr(List<String> args, List<Verifier> pasos) async {
  final b = StringBuffer();
  final c = await correrVerify(args,
      directorio: '.', destino: b, construirCascada: (_) => Cascada(pasos));
  return (c, b.toString());
}

void main() {
  group('el código de proceso se deriva del estado', () {
    test('cada estado tiene su código, y la función es total', () {
      // Un estado nuevo no compila hasta que alguien decida su código: el
      // `switch` es exhaustivo. Es lo contrario de una tabla en un documento.
      for (final e in EstadoDeCorrida.values) {
        expect(() => Codigo.deCorrida(e), returnsNormally, reason: '$e');
      }
      expect(Codigo.deCorrida(EstadoDeCorrida.verde), 0);
      expect(Codigo.deCorrida(EstadoDeCorrida.rojo), 1);
      expect(Codigo.deCorrida(EstadoDeCorrida.noConcluyente), 2);
      expect(Codigo.deCorrida(EstadoDeCorrida.errorInterno), 70);
    });

    test('verde da 0', () async {
      final (c, _) = await correr([], [_Paso.verde('A')]);
      expect(c, 0);
    });

    test('un diagnóstico bloqueante da 1', () async {
      final (c, salida) = await correr([], [_Paso.rojo('A')]);
      expect(c, 1);
      expect(salida, contains('el mensaje'));
    });

    test('lo no concluyente da 2, y GANA sobre el 1', () async {
      final (c, salida) = await correr([], [_Paso.rojo('A'), _Paso.ciego('B')]);
      expect(c, 2);
      expect(salida, contains('el mensaje'),
          reason: 'el hallazgo real se reporta igual; lo que cambia es el '
              'código, que habla del conjunto');
    });

    test('un paso roto da 70, nunca 1', () async {
      final (c, _) = await correr(
          [], [_Paso.rojo('A'), _Paso('B', lanza: StateError('x'))]);
      expect(c, 70,
          reason: 'que el arnés se rompa no puede leerse como que el cambio '
              'no verificó');
    });
  });

  group('toda salida que no sea verde dice qué hacer', () {
    for (final caso in {
      'rojo': [_Paso.rojo('A')],
      'no concluyente': [_Paso.ciego('A')],
      'error interno': [_Paso('A', lanza: StateError('x'))],
      'cascada vacía': <Verifier>[],
    }.entries) {
      test('«${caso.key}» trae su acción siguiente', () async {
        final (c, salida) = await correr(const [], caso.value);
        expect(c, isNot(0));
        expect(salida, contains('→'),
            reason: 'detener sin poder decir qué hacer deja a quien lo choca '
                'sin salida (INV-8)');
      });
    }
  });

  group('el protocolo con --json', () {
    test('todo es JSON Lines, y hay EXACTAMENTE un result, último', () async {
      final (_, salida) =
          await correr(['--json'], [_Paso.rojo('A'), _Paso.verde('B')]);
      final lineas = salida.trim().split('\n');
      final objetos = [
        for (final l in lineas) jsonDecode(l) as Map<String, Object?>,
      ];
      expect(objetos.where((o) => o['type'] == 'result'), hasLength(1));
      expect(objetos.last['type'], 'result');
      expect(objetos.every((o) => o['schema'] == esquemaDeSalida), isTrue,
          reason: 'sin versión de esquema, un consumidor no sabe contra qué '
              'está parseando');
    });

    test('el result lleva registrados Y ejecutados', () async {
      // El corolario 2 tiene que llegar al consumidor, no quedarse en la
      // salida para humanos.
      final (_, salida) = await correr(
          ['--json'], [_Paso.verde('A'), _Paso('B', lanza: StateError('x'))]);
      final result = (salida
          .trim()
          .split('\n')
          .map((l) => jsonDecode(l) as Map<String, Object?>)).last;
      final data = result['data']! as Map<String, Object?>;
      expect(data['registered'], ['A', 'B']);
      expect(data['executed'], ['A']);
      expect(data['notExecuted'], ['B']);
    });

    test('no se cuela texto suelto', () async {
      final (_, salida) = await correr(['--json'], [_Paso.rojo('A')]);
      for (final l in salida.trim().split('\n')) {
        expect(() => jsonDecode(l), returnsNormally,
            reason: 'un consumidor automático se rompe con una línea que no '
                'sea un envelope: «$l»');
      }
    });

    test('emitir un segundo resultado es un error, no una línea de más', () {
      // La promesa «uno solo, y último» no la comprueba nadie salvo esto.
      final imp = Impresora(StringBuffer(), json: true);
      const r = ResultEnvelope(
          command: 'verify', exitCode: 0, verdict: 'ok', data: {});
      imp.resultado(r, 'x');
      expect(() => imp.resultado(r, 'x'), throwsStateError);
    });
  });

  group('interpretación de la línea de comandos', () {
    test('sin alcance, el directorio actual', () {
      expect(interpretar(const []).sujetos, ['.']);
    });

    test('los sujetos se toman en orden', () {
      expect(interpretar(const ['lib', 'test']).sujetos, ['lib', 'test']);
    });

    test('una bandera desconocida no se ignora', () {
      // Ignorarla sería correr con un alcance distinto del que se pidió.
      expect(() => interpretar(const ['--inventada']),
          throwsA(isA<UsoInvalido>()));
    });

    test('`--quiet` y `--verbose` juntos son error de uso', () async {
      final (c, _) = await correr(['--quiet', '--verbose'], [_Paso.verde('A')]);
      expect(c, 5);
    });
  });

  group('--verbose muestra el testigo', () {
    test('sin la bandera no aparece; con la bandera, sí', () async {
      final (_, sin) = await correr(const [], [_Paso.verde('A')]);
      expect(sin, isNot(contains('herramienta --sobre')));

      final (_, con) = await correr(['--verbose'], [_Paso.verde('A')]);
      expect(con, contains('herramienta --sobre lib/'));
      expect(con, contains('algo que no se miró'),
          reason: 'lo omitido es lo que ADR-011 pide y lo que nadie ve si no '
              'se imprime');
    });
  });

  group('el binario de verdad', () {
    test('sin argumentos NO sale con éxito', () async {
      // Una invocación sin acción no cumplió ningún contrato.
      final r = await Process.run(Platform.resolvedExecutable,
          ['run', 'packages/cli/bin/shipflow.dart'],
          workingDirectory: Directory.current.path);
      expect(r.exitCode, 5);
      expect(r.stdout, contains('verify'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
