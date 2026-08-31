/// El comando `verify`: interpretación, protocolo de salida y código.
///
/// **La cascada se inyecta** en casi todo: lo que se prueba acá es la
/// traducción entre el estado de una corrida y lo que ve quien la consume, una
/// persona o un script. El último grupo es la excepción, y existe justamente
/// porque inyectar la cascada deja la composición real sin probar.
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

  /// Un paso con las tres severidades a la vez.
  factory _Paso.mixto(String id) => _Paso(id,
      devuelve: VerificationOutcome(
        verifierId: id,
        witness: _testigo(),
        diagnostics: [
          for (final s in Severity.values)
            Diagnostic(
                file: 'lib/${s.name}.txt',
                severity: s,
                ruleId: 'r-${s.name}',
                message: QuotedText('mensaje-${s.name}', source: 'test')),
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

Impresora _impresora() =>
    Impresora(salida: StringBuffer(), error: StringBuffer(), json: true);

const _result =
    ResultEnvelope(command: 'verify', exitCode: 0, verdict: 'ok', data: {});

List<Map<String, Object?>> _lineas(String salida) => [
      for (final l in salida.trim().split('\n'))
        jsonDecode(l) as Map<String, Object?>,
    ];

void main() {
  group('el código de proceso se deriva del estado', () {
    test('cada estado tiene su código, y la función es total', () {
      for (final e in EstadoDeCorrida.values) {
        expect(() => Codigo.deCorrida(e), returnsNormally, reason: '$e');
      }
      expect(Codigo.deCorrida(EstadoDeCorrida.verde), 0);
      expect(Codigo.deCorrida(EstadoDeCorrida.rojo), 1);
      expect(Codigo.deCorrida(EstadoDeCorrida.noConcluyente), 2);
      expect(Codigo.deCorrida(EstadoDeCorrida.errorInterno), 70);
    });

    test('verde da 0', () async {
      expect((await correr(const [], [_Paso.verde('A')])).$1, 0);
    });

    test('un diagnóstico bloqueante da 1', () async {
      final (c, salida) = await correr(const [], [_Paso.rojo('A')]);
      expect(c, 1);
      expect(salida, contains('el mensaje'));
    });

    test('lo no concluyente da 2, y GANA sobre el 1', () async {
      final (c, salida) =
          await correr(const [], [_Paso.rojo('A'), _Paso.ciego('B')]);
      expect(c, 2);
      expect(salida, contains('el mensaje'),
          reason: 'el hallazgo real se reporta igual; lo que cambia es el '
              'código, que habla del conjunto');
    });

    test('un paso roto da 70, nunca 1', () async {
      final (c, _) = await correr(
          const [], [_Paso.rojo('A'), _Paso('B', lanza: StateError('x'))]);
      expect(c, 70);
    });

    test('una cascada que NO SE PUEDE CONSTRUIR da 70, no una excepción',
        () async {
      // La cascada rechaza ids duplicados, y ese rechazo ocurre FUERA del
      // `try` que envuelve los pasos. Sin la red de arriba, escapaba del
      // comando: proceso con código del runtime y consumidor sin nada que
      // leer. Es el sabotaje SC-16.
      final (c, salida) = await correr(const ['--json'], const [],
          construir: (_) => Cascada([_Paso.verde('A'), _Paso.verde('A')]));
      expect(c, 70);
      final r = _lineas(salida).single;
      expect(r['type'], 'result');
      expect(r['verdict'], 'internalError');
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

    test('la cascada vacía NO manda a mirar testigos que no existen', () async {
      // Decía «mirá lo que omitió cada testigo con --verbose» cuando no hay
      // pasos ni testigos: un error indicando una acción imposible.
      final (_, salida) = await correr(const [], const []);
      expect(salida, contains('ningún verificador registrado'));
      expect(salida, isNot(contains('--verbose')));
    });
  });

  group('el protocolo con --json', () {
    test('todo es JSON Lines, y hay EXACTAMENTE un result, último', () async {
      final (_, salida) =
          await correr(const ['--json'], [_Paso.rojo('A'), _Paso.verde('B')]);
      final objetos = _lineas(salida);
      expect(objetos.where((o) => o['type'] == 'result'), hasLength(1));
      expect(objetos.last['type'], 'result');
      expect(objetos.every((o) => o['schema'] == esquemaDeSalida), isTrue);
    });

    test('un error de uso TAMBIÉN sale como envelope', () async {
      // Imprimía texto humano y con `--json` eso rompe a cualquier consumidor:
      // la primera línea no es JSON y no hay resultado que leer.
      final (c, salida) =
          await correr(const ['--json', '--inventada'], const []);
      expect(c, 5);
      final r = _lineas(salida).single;
      expect(r['type'], 'result');
      expect(r['exitCode'], 5);
      expect(r['nextAction'], isNotNull);
      expect(r['verdict'], isNull,
          reason: 'un error de uso no alcanzó el dominio: no tiene veredicto '
              'que dar, y la superficie no declara ninguno para el código 5');
    });

    test('el result lleva registrados Y ejecutados', () async {
      final (_, salida) = await correr(const ['--json'],
          [_Paso.verde('A'), _Paso('B', lanza: StateError('x'))]);
      final data = _lineas(salida).last['data']! as Map<String, Object?>;
      expect(data['registered'], ['A', 'B']);
      expect(data['executed'], ['A']);
      expect(data['notExecuted'], ['B']);
    });

    test('no se cuela texto suelto', () async {
      final (_, salida) = await correr(const ['--json'], [_Paso.rojo('A')]);
      for (final l in salida.trim().split('\n')) {
        expect(() => jsonDecode(l), returnsNormally, reason: '«$l»');
      }
    });

    test('emitir un segundo resultado es un error, no una línea de más', () {
      final imp = _impresora();
      imp.resultado(_result, 'x');
      expect(() => imp.resultado(_result, 'x'), throwsA(isA<ProtocoloRoto>()));
    });

    test('CERO resultados también incumple el contrato', () {
      // «Uno solo» no dice nada sobre «al menos uno», y un comando que no
      // emite ninguno deja al consumidor esperando algo que no llega.
      expect(_impresora().cerrar, throwsA(isA<ProtocoloRoto>()));
    });

    test('un evento DESPUÉS del resultado también', () {
      final imp = _impresora();
      imp.resultado(_result, 'x');
      expect(
          () => imp.evento(
              EventEnvelope(
                  command: 'verify', type: 'progress', data: const {}),
              'x'),
          throwsA(isA<ProtocoloRoto>()));
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
      expect(() => interpretar(const ['--inventada']),
          throwsA(isA<UsoInvalido>()));
    });

    test('`--quiet` y `--verbose` juntos son error de uso', () async {
      expect((await correr(const ['--quiet', '--verbose'], const [])).$1, 5);
    });

    test('`--help` se reconoce y sale con 0', () async {
      // Lo rechazaba como bandera desconocida, y el mensaje de error
      // recomendaba correr exactamente eso: un bucle imposible.
      for (final b in ['--help', '-h']) {
        final (c, salida) = await correr([b], [_Paso.verde('A')]);
        expect(c, 0, reason: b);
        expect(salida, contains('--verbose'), reason: b);
      }
    });
  });

  group('el silencio y el detalle', () {
    test('`--quiet` calla el progreso pero NO los diagnósticos', () async {
      final (_, salida) = await correr(const ['--quiet'], [_Paso.rojo('A')]);
      expect(salida, contains('el mensaje'));
      expect(salida, isNot(contains('FALLA     A')),
          reason: 'el progreso sí se calla');
    });

    test('`silencia` NO se muestra nunca, ni siquiera sin banderas', () {
      // `Severity.silencia` dice de sí misma «registra para telemetría y no se
      // muestra». Se filtraba por el TIPO del evento, no por la severidad, así
      // que se imprimía igual.
      final d = Diagnostic(
          file: 'a',
          severity: Severity.silencia,
          ruleId: 'r',
          message: const QuotedText('m', source: 't'));
      expect(seMuestra(d, silencioso: false), isFalse);
      expect(seMuestra(d, silencioso: true), isFalse);
    });

    test('`--quiet` es «solo errores», no «todos los diagnósticos»', () async {
      // Dejaba pasar lo informativo, que anota y sigue. Un error es lo que
      // bloquea.
      final (_, ruidoso) = await correr(const [], [_Paso.mixto('A')]);
      expect(ruidoso, contains('mensaje-bloquea'));
      expect(ruidoso, contains('mensaje-reporta'));
      expect(ruidoso, isNot(contains('mensaje-silencia')));

      final (_, callado) = await correr(const ['--quiet'], [_Paso.mixto('A')]);
      expect(callado, contains('mensaje-bloquea'));
      expect(callado, isNot(contains('mensaje-reporta')));
      expect(callado, isNot(contains('mensaje-silencia')));
    });

    test('el rescate en modo humano TAMBIÉN dice qué hacer', () async {
      // La excepción que escapa del comando entero pasa por otra rama que la
      // del paso roto: el envelope llevaba la acción y el texto para personas
      // no. «Todo error indica la acción siguiente» no admite excepciones por
      // formato ni por camino.
      final (c, salida, _) = await invocar(const ['verify'], const [],
          construir: (_) => Cascada([_Paso.verde('A'), _Paso.verde('A')]));
      expect(c, 70);
      expect(salida, contains('→'),
          reason: 'el rescate imprimía solo la línea del error');
    });

    test('el error interno en modo humano TAMBIÉN dice qué hacer', () async {
      // El envelope lo llevaba y la salida para personas no. «Todo error
      // indica la acción siguiente» no admite excepciones por formato.
      final (c, salida) =
          await correr(const [], [_Paso('A', lanza: StateError('x'))]);
      expect(c, 70);
      expect(salida, contains('→'));
    });

    test('`--verbose` muestra el testigo; sin la bandera, no', () async {
      final (_, sin) = await correr(const [], [_Paso.verde('A')]);
      expect(sin, isNot(contains('herramienta --sobre')));

      final (_, con) = await correr(const ['--verbose'], [_Paso.verde('A')]);
      expect(con, contains('herramienta --sobre lib/'));
      expect(con, contains('algo que no se miró'));
    });
  });

  group('la frontera es UNA: el ruteo también cumple el protocolo', () {
    // `_enrutar` y `main` tenían salidas propias y con `--json` rompían el
    // contrato en tres invocaciones distintas. Cada una había que arreglarla
    // por separado; ahora el único camino de salida construye envelopes.
    for (final caso in {
      'sin comando': <String>[],
      'comando desconocido': ['desconocido'],
      'ayuda global': ['--help'],
    }.entries) {
      test('«${caso.key}» con --json sale como envelope', () async {
        final (_, out, _) = await invocar(['--json', ...caso.value], const []);
        final lineas = out.trim().split('\n');
        expect(lineas, hasLength(1),
            reason: 'un solo documento, y nada de texto suelto');
        final r = jsonDecode(lineas.single) as Map<String, Object?>;
        expect(r['type'], 'result');
        expect(r['schema'], esquemaDeSalida);
      });
    }

    test('sin comando no es éxito; `--help` explícito sí', () async {
      expect((await invocar(const [], const [])).$1, 5);
      expect((await invocar(const ['--help'], const [])).$1, 0);
    });
  });

  group('la última salida va por la corriente de error', () {
    test('si ni siquiera se puede emitir el resultado', () {
      // El contrato reserva esa corriente para «un fallo que impida incluso
      // serializar el resultado», y hasta acá nadie escribía en ella: el
      // rescate reintentaba sobre la misma salida que acababa de fallar.
      final err = StringBuffer();
      Impresora(salida: StringBuffer(), error: err)
          .ultimoRecurso('se rompió', 'hacé esto');
      expect(err.toString(), contains('se rompió'));
      expect(err.toString(), contains('→ hacé esto'));
    });
  });

  group('el binario, con su composición de verdad', () {
    late Directory raiz;

    setUp(() {
      raiz = Directory.systemTemp.createTempSync('cli_');
      File('${raiz.path}/pubspec.yaml')
          .writeAsStringSync('name: sujeto\nenvironment:\n  sdk: ^3.0.0\n');
      Directory('${raiz.path}/lib').createSync();
    });
    tearDown(() => raiz.deleteSync(recursive: true));

    Future<ProcessResult> shipflow(List<String> args) => Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            '${Directory.current.path}/packages/cli/bin/shipflow.dart',
            ...args,
          ],
          workingDirectory: raiz.path,
        );

    test('registra los pasos reales y los corre de verdad', () async {
      // **La única prueba que toca `cascadaPorDefecto`.** Todo lo demás
      // inyecta la cascada, así que los dos pasos podrían borrarse,
      // invertirse o reemplazarse y las pruebas seguirían verdes.
      File('${raiz.path}/lib/feo.dart')
          .writeAsStringSync('void a(){int   x=1;print(x);}\n');
      final r = await shipflow(['verify', 'lib', '--json']);
      expect(r.exitCode, 1);
      final doc = _lineas(r.stdout as String).last;
      final data = doc['data']! as Map<String, Object?>;
      expect(data['registered'], ['FormatCheck', 'StaticAnalysis'],
          reason: 'el orden es de costo creciente y es parte del contrato');
      expect(data['executed'], ['FormatCheck', 'StaticAnalysis']);
      expect(doc['verdict'], 'failed',
          reason: 'los pasos reales tienen que ENCONTRAR el archivo sin '
              'formatear, no solo estar registrados');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('una bandera global ANTES del comando no es un comando', () async {
      // `--json verify` se leía como el comando «--json».
      File('${raiz.path}/lib/a.dart').writeAsStringSync('void main() {}\n');
      final r = await shipflow(['--json', 'verify', 'lib']);
      expect(r.exitCode, 0);
      expect(_lineas(r.stdout as String).last['type'], 'result');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('sin argumentos NO sale con éxito', () async {
      final r = await shipflow(const []);
      expect(r.exitCode, 5);
      expect(r.stdout, contains('verify'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('`--help` explícito SÍ sale con éxito', () async {
      // Pediste ayuda y la tuviste: eso cumplió su contrato. Una invocación
      // vacía no.
      final r = await shipflow(const ['--help']);
      expect(r.exitCode, 0);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
