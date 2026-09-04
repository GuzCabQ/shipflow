/// El comando `verify`: interpretación, protocolo de salida y código.
///
/// **La cascada se inyecta** en casi todo: lo que se prueba acá es la
/// traducción entre el estado de una corrida y lo que ve quien la consume, una
/// persona o un script. El último grupo es la excepción, y existe justamente
/// porque inyectar la cascada deja la composición real sin probar.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

import 'apoyo.dart';

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
      expect((await correr(const [], [Paso.verde('A')])).$1, 0);
    });

    test('un diagnóstico bloqueante da 1', () async {
      final (c, salida) = await correr(const [], [Paso.rojo('A')]);
      expect(c, 1);
      expect(salida, contains('el mensaje'));
    });

    test('lo no concluyente da 2, y GANA sobre el 1', () async {
      final (c, salida) =
          await correr(const [], [Paso.rojo('A'), Paso.ciego('B')]);
      expect(c, 2);
      expect(salida, contains('el mensaje'),
          reason: 'el hallazgo real se reporta igual; lo que cambia es el '
              'código, que habla del conjunto');
    });

    test('un paso roto da 70, nunca 1', () async {
      final (c, _) = await correr(
          const [], [Paso.rojo('A'), Paso('B', lanza: StateError('x'))]);
      expect(c, 70);
    });

    test('una cascada que NO SE PUEDE CONSTRUIR da 70, no una excepción',
        () async {
      // La cascada rechaza ids duplicados, y ese rechazo ocurre FUERA del
      // `try` que envuelve los pasos. Sin la red de arriba, escapaba del
      // comando: proceso con código del runtime y consumidor sin nada que
      // leer. Es el sabotaje SC-16.
      final (c, salida) = await correr(const ['--json'], const [],
          construir: (_) => Cascada([Paso.verde('A'), Paso.verde('A')]));
      expect(c, 70);
      final r = lineas(salida).single;
      expect(r['type'], 'result');
      expect(r['verdict'], 'internalError');
    });
  });

  group('toda salida que no sea verde dice qué hacer', () {
    for (final caso in {
      'rojo': [Paso.rojo('A')],
      'no concluyente': [Paso.ciego('A')],
      'error interno': [Paso('A', lanza: StateError('x'))],
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

  group('el alcance', () {
    Globales g(List<String> restantes) => Globales(
        json: false,
        silencioso: false,
        detallado: false,
        ayuda: false,
        comando: 'verify',
        restantes: restantes);

    test('sin alcance, el directorio actual', () {
      expect(opcionesDe(g(const [])).sujetos, ['.']);
    });

    test('los sujetos se toman en orden', () {
      expect(opcionesDe(g(const ['lib', 'test'])).sujetos, ['lib', 'test']);
    });

    test('una bandera que sobró no la ignora nadie', () {
      // `verify` no tiene banderas propias, así que una que la frontera dejó
      // pasar no la puede aceptar él tampoco. Ignorarla sería correr con un
      // alcance distinto del que se pidió.
      expect(() => opcionesDe(g(const ['--dry-run'])),
          throwsA(isA<UsoInvalido>()));
    });
  });

  group('el silencio y el detalle', () {
    test('`--quiet` calla el progreso pero NO los diagnósticos', () async {
      final (_, salida) = await correr(const ['--quiet'], [Paso.rojo('A')]);
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
      final (_, ruidoso) = await correr(const [], [Paso.mixto('A')]);
      expect(ruidoso, contains('mensaje-bloquea'));
      expect(ruidoso, contains('mensaje-reporta'));
      expect(ruidoso, isNot(contains('mensaje-silencia')));

      final (_, callado) = await correr(const ['--quiet'], [Paso.mixto('A')]);
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
          construir: (_) => Cascada([Paso.verde('A'), Paso.verde('A')]));
      expect(c, 70);
      expect(salida, contains('→'),
          reason: 'el rescate imprimía solo la línea del error');
    });

    test('el error interno en modo humano TAMBIÉN dice qué hacer', () async {
      // El envelope lo llevaba y la salida para personas no. «Todo error
      // indica la acción siguiente» no admite excepciones por formato.
      final (c, salida) =
          await correr(const [], [Paso('A', lanza: StateError('x'))]);
      expect(c, 70);
      expect(salida, contains('→'));
    });

    test('`--verbose` muestra el testigo; sin la bandera, no', () async {
      final (_, sin) = await correr(const [], [Paso.verde('A')]);
      expect(sin, isNot(contains('herramienta --sobre')));

      final (_, con) = await correr(const ['--verbose'], [Paso.verde('A')]);
      expect(con, contains('herramienta --sobre lib/'));
      expect(con, contains('algo que no se miró'));
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
      final doc = lineas(r.stdout as String).last;
      final data = doc['data']! as Map<String, Object?>;
      expect(data['registered'], ['FormatCheck', 'StaticAnalysis'],
          reason: 'el orden es de costo creciente y es parte del contrato');
      expect(data['executed'], ['FormatCheck', 'StaticAnalysis']);
      expect(doc['verdict'], 'failed',
          reason: 'los pasos reales tienen que ENCONTRAR el archivo sin '
              'formatear, no solo estar registrados');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('un alcance sin archivos del stack se SALTA, y lo dice', () async {
      // Antes de esta rebanada, esto salía «no concluyente: algún paso no pudo
      // observar su alcance» — falso: las dos herramientas corrieron,
      // terminaron completas con código 0, y no tenían nada suyo que mirar.
      // Es el falso rojo simétrico del falso verde que el arnés caza.
      File('${raiz.path}/lib/LEEME.md').writeAsStringSync('# solo prosa\n');
      final r = await shipflow(['verify', 'lib', '--json']);

      final doc = lineas(r.stdout as String).last;
      final data = doc['data']! as Map<String, Object?>;
      final saltados = data['skipped']! as Map<String, Object?>;
      expect(saltados.keys, ['FormatCheck', 'StaticAnalysis']);
      expect(saltados['FormatCheck'], isNotEmpty,
          reason: 'un salto sin motivo es un salto silencioso');
      expect(data['notExecuted'], isEmpty,
          reason: 'un salto está contado: no es una discrepancia');

      // Y la corrida NO es verde: cada salto por separado es legítimo, todos
      // juntos son una corrida que no verificó nada.
      expect(doc['verdict'], 'inconclusive');
      expect(doc['exitCode'], 2);
      expect(doc['nextAction'], contains('tuvo nada que hacer'),
          reason: 'no puede decir «no pudo observar»: sí observó');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('una bandera global ANTES del comando no es un comando', () async {
      // `--json verify` se leía como el comando «--json».
      File('${raiz.path}/lib/a.dart').writeAsStringSync('void main() {}\n');
      final r = await shipflow(['--json', 'verify', 'lib']);
      expect(r.exitCode, 0);
      expect(lineas(r.stdout as String).last['type'], 'result');
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
