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
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';

import 'apoyo.dart';

/// Una cascada con ids duplicados no llega a observar nada: el registro se
/// rechaza en el constructor, antes de que `correr` exista. Un observador sin
/// ningún sujeto declarado alcanza.
ObservadorDeAlcanceFalso _observadorQueNoSeUsa() =>
    ObservadorDeAlcanceFalso(observados: const {});

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

    test(
        'un paso roto Y causas no concluyentes concurrentes: 70, y la '
        'acción habla del arnés, no de la causa', () async {
      // La lista de causas puede venir no vacía con error interno: un paso
      // roto no impide que otro haya quedado ciego. La acción siguiente
      // tiene que atender el roto primero, o hablaría de otra cosa que lo
      // que de verdad interrumpió la corrida.
      final (c, salida) = await correr(
          const [], [Paso.ciego('A'), Paso('B', lanza: StateError('x'))]);
      expect(c, 70);
      expect(salida, contains('rompió un paso del arnés'));
      expect(salida, contains('B'));
    });

    test('una cascada que NO SE PUEDE CONSTRUIR da 70, no una excepción',
        () async {
      // La cascada rechaza ids duplicados, y ese rechazo ocurre FUERA del
      // `try` que envuelve los pasos. Sin la red de arriba, escapaba del
      // comando: proceso con código del runtime y consumidor sin nada que
      // leer. Es el sabotaje SC-16.
      final (c, salida) = await correr(const ['--json'], const [],
          construir: (_) => Cascada([Paso.verde('A'), Paso.verde('A')],
              observador: _observadorQueNoSeUsa()));
      expect(c, 70);
      final r = lineas(salida).single;
      expect(r['type'], 'result');
      expect(r['verdict'], 'internalError');
    });
  });

  group('cada desenlace tiene su etapa, y son cinco', () {
    test('un verde llega como `executed`', () async {
      final etapas = <String>{};
      final (_, salida) = await correr(const ['--json'], [Paso.verde('A')]);
      for (final l in lineas(salida)) {
        final d = l['data'] as Map<String, Object?>?;
        if (d != null && d['stage'] != null) etapas.add(d['stage'] as String);
      }
      expect(etapas, containsAll(['started', 'executed']));
    });

    test('un roto llega como `internalError`', () async {
      final etapas = <String>{};
      final (_, salida) =
          await correr(const ['--json'], [Paso('A', lanza: StateError('x'))]);
      for (final l in lineas(salida)) {
        final d = l['data'] as Map<String, Object?>?;
        if (d != null && d['stage'] != null) etapas.add(d['stage'] as String);
      }
      expect(etapas, contains('internalError'));
    });
  });

  group('el esquema de salida', () {
    test('subió a 2, y todo evento lleva runId', () async {
      final (_, salida) = await correr(const ['--json'], [Paso.verde('A')]);
      expect(lineas(salida).every((l) => l['schema'] == 2), isTrue);
      expect(lineas(salida).last.containsKey('runId'), isTrue);
    });

    test('un error de uso, que no corre ninguna cascada, no tiene runId',
        () async {
      final (_, salida) = await correr(const ['--json', '--dry-run'], const []);
      expect(lineas(salida).single['runId'], isNull);
    });
  });

  group('el resultado lleva la causa estructurada y el libro', () {
    test('lo no concluyente trae `inconclusiveBecause` y `obligations`',
        () async {
      final (c, salida) = await correr(const ['--json'], [Paso.ciego('A')]);
      expect(c, 2);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      expect(data['inconclusiveBecause'], isNotEmpty);
      expect(data.containsKey('obligations'), isTrue);
    });

    test('el libro trae el desenlace completo de cada paso', () async {
      final (_, salida) = await correr(const ['--json'], [Paso.verde('A')]);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      final outcomes = data['outcomes']! as Map<String, Object?>;
      expect(outcomes.keys, ['A']);
      final a = outcomes['A']! as Map<String, Object?>;
      expect(a['kind'], 'executed');
    });
  });

  group('la acción siguiente solo nombra evidencia presente en `data`', () {
    test('con lo no concluyente, ni banderas ni comandos que no existen',
        () async {
      // El canario de la acción imposible: decía «mirá lo que omitió cada
      // testigo con --verbose» sobre una lista vacía.
      final (_, salida) = await correr(const ['--json'], [Paso.ciego('A')]);
      final doc = lineas(salida).last;
      final accion = doc['nextAction']! as String;
      expect(accion, isNot(contains('--verbose')));
      expect(accion, isNot(contains('doctor')));
      expect(accion, isNot(contains('--budget')));
    });

    test('nombra el motivo real del testigo, y ese motivo está en `data`',
        () async {
      final (_, salida) = await correr(const ['--json'], [Paso.ciego('A')]);
      final doc = lineas(salida).last;
      final data = doc['data']! as Map<String, Object?>;
      final outcomes = data['outcomes']! as Map<String, Object?>;
      final witness = (outcomes['A']! as Map<String, Object?>)['witness']!
          as Map<String, Object?>;
      final omitido =
          (witness['omitted']! as List).cast<Map<String, Object?>>();
      final motivo = omitido.first['reason']! as String;
      expect(doc['nextAction'], contains(motivo));
    });
  });

  group('`--json --quiet` deja SOLO el resultado', () {
    test('es el modo no streaming de la superficie, sin bandera nueva',
        () async {
      // `--quiet` ya significa callar el progreso.
      final (_, salida) =
          await correr(const ['--json', '--quiet'], [Paso.verde('A')]);
      expect(lineas(salida), hasLength(1));
      expect(lineas(salida).single['type'], 'result');
    });
  });

  group('un start sin terminal queda declarado en el resultado', () {
    test(
        'la garantía de entrega: si el canal se rompe, el consumidor no '
        'espera', () async {
      final (c, salida) = await invocarConObservadorRoto();
      expect(c, 70);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      expect(data['unterminated'], isNotEmpty);
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

    test(
        'alcance MIXTO —un ajeno y una ruta inexistente—: dice qué NO se '
        'pudo observar, no que nada era del stack', () async {
      // **Este es el caso mixto, no el puro.** El puro —todo inobservable,
      // ningún ajeno— ya distinguía las causas porque `nadaEjecutado` no
      // tenía ningún ajeno que nombrar, y una prueba solo con ese caso no
      // habría notado la diferencia entre el arreglo y lo que ya había. Acá
      // hay un ajeno DE VERDAD (LEEME.md) además de la ruta que ni se pudo
      // mirar: antes del fix en `cascada.dart`, `nadaEjecutado` ganaba,
      // nombraba a LEEME.md con toda normalidad —no el bug literal de
      // nombrar evidencia ausente— y callaba que además hubo una ruta
      // inobservable. Es la afirmación parcial que un review encontró.
      final obs = ObservadorDeAlcanceFalso(
        observados: {
          'LEEME.md': ObservedSubject(
              subject: 'LEEME.md',
              ofStack: false,
              files: 0,
              reason: 'no es de este stack'),
        },
        noObservados: const {'no/existe': 'no existe'},
      );
      final (c, salida) = await correr(
        const ['--json', 'LEEME.md', 'no/existe'],
        [Paso.verde('A')],
        construir: (_) => Cascada([Paso.verde('A')], observador: obs),
      );
      expect(c, 2);
      final doc = lineas(salida).last;
      expect(doc['nextAction'], contains('No se pudo observar'));
      expect(doc['nextAction'],
          isNot(contains('Ningún sujeto del alcance es de este stack')),
          reason: 'nombrar solo el ajeno callaría la ruta inobservable');
    });

    test(
        'alcance SANO y todos los pasos ABORTAN: la acción habla del '
        'aborto, no de sujetos ajenos que no existen', () async {
      // El caso que un review reprodujo DESPUÉS de que el reordenamiento de
      // `cascada.dart` cerrara el caso mixto: acá no hay ningún sujeto
      // ajeno ni ninguna ruta inobservable —el alcance es enteramente del
      // stack— y sin embargo nada ejecutó, porque los dos pasos abortan.
      // Antes del fix (condicionar el disparo de `nadaEjecutado` a que
      // exista al menos un ajeno, no reordenarlo una vez más), la acción
      // decía «Ningún sujeto del alcance es de este stack: .» — el hueco
      // después de los dos puntos es el error original exacto: una acción
      // que nombra evidencia que no existe.
      final (c, salida) = await correr(
        const ['--json'],
        [
          Paso.abortado('A', nota: 'la nota real del intento'),
          Paso.abortado('B'),
        ],
      );
      expect(c, 2);
      final doc = lineas(salida).last;
      expect(doc['nextAction'], contains('la nota real del intento'));
      expect(doc['nextAction'],
          isNot(contains('Ningún sujeto del alcance es de este stack')),
          reason: 'no hay ningún sujeto ajeno que nombrar: el alcance es '
              'sano, lo que faltó fue que los pasos terminaran');
    });
  });

  group('el libro de obligaciones', () {
    test('un paso que cubre un subconjunto sin explicar el resto no da verde',
        () async {
      final (c, salida) = await correrConAlcance(
        const ['--json', 'a.fuente', 'b.fuente'],
        [
          PasoQueCubre('A', const ['a.fuente', 'b.fuente']),
          PasoQueCubre('B', const ['a.fuente']),
        ],
      );
      expect(c, 2);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      expect(data['obligations'], [
        {'step': 'B', 'subject': 'b.fuente'},
      ]);
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
          construir: (_) => Cascada([Paso.verde('A'), Paso.verde('A')],
              observador: _observadorQueNoSeUsa()));
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
      expect(con, contains('herramienta --sobre .'));
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
      final registrados = (data['registered']! as List)
          .cast<Map<String, Object?>>()
          .map((e) => e['id'])
          .toList();
      expect(registrados, ['FormatCheck', 'StaticAnalysis'],
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
      final outcomes = data['outcomes']! as Map<String, Object?>;
      expect(outcomes.keys, ['FormatCheck', 'StaticAnalysis']);
      for (final o in outcomes.values) {
        expect((o as Map<String, Object?>)['kind'], 'skipped',
            reason: 'un salto sin motivo es un salto silencioso');
      }

      // Y la corrida NO es verde: cada salto por separado es legítimo, todos
      // juntos son una corrida que no verificó nada.
      expect(doc['verdict'], 'inconclusive');
      expect(doc['exitCode'], 2);
      expect(
          doc['nextAction'],
          contains('Ningún sujeto del alcance es de '
              'este stack'),
          reason: 'no puede decir «no pudo observar»: sí observó');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('una ruta INEXISTENTE no es «no tuvo nada que hacer»', () async {
      // El falso salto: el arnés no pudo mirar, no es que no había nada. Un
      // review lo cobró — y con otro paso en verde en la cascada, esto habría
      // sido un verde sobre una ruta que nadie miró.
      final r = await shipflow(['verify', 'no/existe', '--json']);

      final doc = lineas(r.stdout as String).last;
      final data = doc['data']! as Map<String, Object?>;
      final outcomes = data['outcomes']! as Map<String, Object?>;
      expect(
          outcomes.values.every(
              (o) => (o as Map<String, Object?>)['kind'] == 'unobservable'),
          isTrue,
          reason: 'no pudo mirar ≠ no había nada');
      expect(doc['verdict'], 'inconclusive');
      expect(doc['nextAction'], contains('No se pudo observar'));
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

  // Los seis ataques que se reprodujeron sobre el código anterior y salían
  // verdes, o daban acciones imposibles. Convertidos en pruebas para que no
  // vuelvan a funcionar sin que algo lo note.
  //
  // **Nota de adaptación.** El brief de esta tarea traía este grupo escrito
  // contra una forma del código que cinco cambios, ocurridos durante la
  // ejecución del plan, dejaron desactualizada:
  //
  // - `Skipped` no lleva más un solo `ObservedSubject` opcional: lleva
  //   `notOfStack`, la lista completa de ajenos que motiva el salto.
  // - `Witness` ya no tiene campo de terminación ni de conteo: `Termination`
  //   distinta de completa vive en `Attempt`, dentro de `Aborted`.
  // - Los ayudantes que el brief daba por existentes —`correrConAlcance`,
  //   `PasoQueCubre`, `invocarConObservadorRoto`, `lineas`— ya estaban en
  //   `apoyo.dart` de una tarea previa, así que se reusan tal cual en vez de
  //   volver a declararlos acá.
  group('los ataques que antes funcionaban', () {
    test('C1 · un verificador no puede declarar que un archivo no es suyo', () {
      // No hay forma de escribir el ataque: `run` devuelve
      // `VerificationOutcome` y `Skipped` no es uno. Si esta prueba deja de
      // compilar porque alguien metió `Skipped` bajo `VerificationOutcome`,
      // el invariante se perdió.
      expect(
          Skipped(notOfStack: [
            ObservedSubject(
                subject: 'a', ofStack: false, files: 0, reason: 'no es mío')
          ]),
          isNot(isA<VerificationOutcome>()));
    });

    test('C3 · cubrir la mitad sin explicar el resto no da verde', () async {
      final (c, _) = await correrConAlcance(const [
        'a.fuente',
        'b.fuente'
      ], [
        PasoQueCubre('A', const ['a.fuente'])
      ]);
      expect(c, 2);
    });

    test('C6 · un start sin terminal queda declarado', () async {
      final (c, salida) = await invocarConObservadorRoto();
      expect(c, 70);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      expect(data['unterminated'], isNotEmpty);
    });

    test('C9 · un paso sin evidencia no se puede construir', () {
      expect(
          () => Witness(
                invocation: 'h',
                subjects: const [],
                omitted: const [],
                exitCode: 0,
                finishedAt: DateTime.utc(2026),
              ),
          throwsArgumentError);
    });

    test('C12 · un testigo honesto da verde, sin campos de más', () async {
      // El plugin de terceros que cumplía las cláusulas y nunca obtenía
      // verde, porque le faltaba un conteo que ya no existe.
      final (c, _) = await correrConAlcance(const [
        'a.fuente'
      ], [
        PasoQueCubre('A', const ['a.fuente'])
      ]);
      expect(c, 0);
    });

    test('C5 · la regla del motivo en blanco vale en LOS TRES tipos', () {
      // Antes había dos reglas para el mismo hecho: un tipo rechazaba
      // cualquier blanco y otro solo si TODOS lo eran. `Omission` lanza antes
      // que `Witness`, así que comprobar los dos ahí no probaría nada nuevo:
      // lo que se recorre son los tres lugares donde se escribe un motivo.
      expect(() => Omission(subject: 'a', reason: ' '), throwsArgumentError);
      expect(
          () => ObservedSubject(
              subject: 'a', ofStack: false, files: 0, reason: '  '),
          throwsArgumentError);
      expect(() => UnobservedSubject(subject: 'a', cause: ' '),
          throwsArgumentError);
    });
  });
}
