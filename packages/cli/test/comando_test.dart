/// El comando `ship` visto **desde la frontera**: qué código sale del
/// proceso, por dónde sale cada texto, y qué lleva el payload de máquina.
///
/// **No repite lo que `ship/ship_test` ya fija.** Aquella suite mide los
/// dieciséis pasos camino por camino; esta mide lo único que aquélla no puede
/// ver, porque llama a la orquestación directamente: que el despachador
/// conozca el comando, que los colaboradores estén DE VERDAD conectados, que
/// las cuatro excepciones se traduzcan a su código, y que la previsualización
/// salga por el canal de eventos y no por la salida cruda.
///
/// **El repositorio es de verdad**, en un directorio temporal, por el mismo
/// motivo que allá: lo que estas pruebas afirman —qué rama, qué base, qué
/// revisión del candidato, qué rutas ajenas— no lo puede producir ningún
/// doble sin reimplementar `git`.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

import 'apoyo.dart';

/// El archivo de la rebanada: versionado desde el primer commit, y la corrida
/// lo modifica. Sin un cambio contra la base, `prepareCandidate` rechaza.
const _archivo = 'lib/a.txt';

/// Una ruta sucia que NO es de la rebanada. La previsualización la nombra
/// aparte, y esa cuenta es lo que prueba que `cambiosAjenos` de verdad miró.
const _ajeno = 'ajeno.txt';

/// Una línea que el detector reconoce por el NOMBRE al que se asigna.
const _lineaConSecreto = 'password = "no-deberia-estar-acá-nunca"';

/// El desenlace que el payload tiene que saber describir. Es el del diseño:
/// entrega incompleta, reintentable, sobre una verificación verde.
ShipOutcome desenlaceDePrueba() =>
    ShipOutcome.publicacionIncompletaParaLaPrueba(
      remoto: PushUnknown(causa: CausaDePublicacion.red),
      verificacion: EstadoPublicable.verde,
    );

/// La invocación entera, sin montar nada. Sirve para los caminos que salen
/// ANTES de componer ningún colaborador.
Future<int> ejecutarDePrueba(List<String> args) async => ejecutar(
  args,
  directorio: '.',
  salida: StringBuffer(),
  error: StringBuffer(),
);

/// La ayuda de la frontera, tal como la ve quien corre `shipflow --help`.
Future<String> ayudaDePrueba() async {
  final salida = StringBuffer();
  await ejecutar(
    const ['--help'],
    directorio: '.',
    salida: salida,
    error: StringBuffer(),
  );
  return salida.toString();
}

/// Un repositorio de verdad y los colaboradores de una corrida de `ship`.
///
/// **Los dobles son los que ya existen** —`SalidaDePrFalsa`,
/// `FuenteDeCredencialFalsa`, `PoliticaDeArtefactosFalsa`,
/// `ObservadorDeAlcanceFalso`, `EntornoFalso` y `Paso`—. El único colaborador
/// que se usa REAL, además del repositorio, es la lectura de cambios ajenos:
/// es barata —un `git status`— y es justamente la que una prueba contra un
/// doble no podría afirmar.
class Mundo {
  final EstadoDeCorrida estado;
  final bool conSecreto;
  final bool sinCredencial;
  final bool conCambioAjeno;

  /// No hay forja compuesta. Es el estado real de este repositorio: no existe
  /// todavía ninguna superficie para declarar de qué remoto se trata.
  final bool sinForja;

  /// Cómo contesta quien corre, o nulo si no hay con quién hablar.
  final Future<bool> Function(String pregunta)? responder;

  /// La identidad de la corrida, fijada: hay un camino —el documento que `git`
  /// NO ignora— donde la ruta del documento tiene que ser conocida ANTES de
  /// que la corrida empiece, porque lo que la provoca es que esa ruta esté en
  /// el índice.
  static const runId = 'r-1';

  late final Directory raiz;
  late final RepositorioGit repo;
  late final RegistroDeCorridas registro;
  final EntornoFalso ambiente = EntornoFalso();
  final SalidaDePrFalsa forja = SalidaDePrFalsa(
    respuesta: PullRequestOpen(url: 'https://forja.invalida/pr/1'),
  );

  Mundo({
    this.estado = EstadoDeCorrida.verde,
    this.conSecreto = false,
    this.sinCredencial = false,
    this.conCambioAjeno = false,
    this.sinForja = false,
    this.responder,
  }) {
    raiz = Directory.systemTemp.createTempSync('ship_comando_');
    addTearDown(() => raiz.deleteSync(recursive: true));
    _escribir(_archivo, 'antes\n');
    _git(['init', '--initial-branch=main', '.']);
    _git(['config', 'user.email', 'p@p']);
    _git(['config', 'user.name', 'prueba']);
    _git(['add', '-A']);
    _git(['commit', '-m', 'base']);
    _git(['switch', '-c', 'trabajo']);
    repo = RepositorioGit(
      directorio: raiz.path,
      politica: PoliticaDeArtefactosFalsa(),
    );
    registro = RegistroDeCorridas(raiz: '${raiz.path}/.shipflow');
    if (conCambioAjeno) _escribir(_ajeno, 'trabajo de al lado\n');
  }

  String _git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: raiz.path);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
    }
    return (r.stdout as String).trim();
  }

  void _escribir(String ruta, String contenido) {
    final f = File('${raiz.path}/$ruta');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  List<Verifier> get _pasos => switch (estado) {
    EstadoDeCorrida.verde => [Paso.verde('doble')],
    EstadoDeCorrida.rojo => [Paso.rojo('doble')],
    EstadoDeCorrida.noConcluyente => [Paso.ciego('doble')],
    EstadoDeCorrida.errorInterno => [
      Paso('doble', lanza: StateError('el instrumento se rompió')),
    ],
  };

  ColaboradoresDeShip _colaboradores(
    String directorio,
    Globales g,
  ) => ColaboradoresDeShip(
    repo: repo,
    ambiente: ambiente,
    construirCascada: (_) => Cascada(
      _pasos,
      observador: ObservadorDeAlcanceFalso(
        observados: {
          _archivo: ObservedSubject(subject: _archivo, ofStack: true, files: 1),
        },
      ),
    ),
    controles: {for (final p in _pasos) p.id: p},
    credenciales: sinCredencial
        ? const FuenteDeCredencialFalsa()
        : const FuenteDeCredencialFalsa(
            credenciales: {
              claveDeCredencialDeLaForja: Credential(
                'un-secreto',
                label: claveDeCredencialDeLaForja,
              ),
            },
          ),
    forja: sinForja ? null : forja,
    registro: registro,
    cambiosAjenos: (List<String> archivos) =>
        cambiosAjenosDelArbol(directorio: raiz.path, deLaRebanada: archivos),
    responder: responder,
    leerArchivo: (String ruta) => File(ruta).readAsString(),
    nuevoRunId: () => runId,
    baseConfigurada: 'main',
  );

  /// Corre `shipflow ship` ENTERO, por la frontera.
  Future<(int, String, String)> correr(List<String> args) async {
    _escribir(_archivo, conSecreto ? '$_lineaConSecreto\n' : 'después\n');
    final salida = StringBuffer();
    final error = StringBuffer();
    final codigo = await ejecutar(
      ['ship', ...args],
      directorio: raiz.path,
      salida: salida,
      error: error,
      construirShip: _colaboradores,
    );
    return (codigo, salida.toString(), error.toString());
  }

  /// Los commits que la corrida dejó en la rama.
  List<String> get commits {
    final r = _git(['rev-list', 'main..refs/heads/trabajo']);
    return [
      for (final l in r.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
  }
}

/// Los argumentos mínimos de una invocación válida.
const _invocacion = ['--intent', 'publicar el cambio', '--file', _archivo];

void main() {
  group('el payload de máquina', () {
    test('el envelope NO sube de versión', () {
      expect(
        payloadDeShip(desenlaceDePrueba())['schema'],
        isNull,
        reason: 'el schema es del envelope, no del payload',
      );
      expect(esquemaDeSalida, 2);
    });

    test('el payload lleva su propia versión', () {
      expect(
        payloadDeShip(desenlaceDePrueba())['payloadVersion'],
        payloadVersionDeShip,
      );
    });

    test('una entrega incompleta sale 6 y dice cómo reintentar', () {
      final d = ShipOutcome.publicacionIncompletaParaLaPrueba(
        remoto: PushUnknown(causa: CausaDePublicacion.red),
        verificacion: EstadoPublicable.verde,
      );
      expect(Codigo.deShip(d), 6);
      expect(accionDe(d), contains('--retry-publication'));
    });

    test('el estado de entrega y el reintento salen del desenlace remoto', () {
      final p = payloadDeShip(desenlaceDePrueba());
      expect(p['deliveryStatus'], EstadoDeEntrega.incompletaReintentable.name);
      expect(p['retryable'], isTrue);
      expect(p['push'], 'unknown');
      expect(
        p['pullRequest'],
        'notAttempted',
        reason:
            'si no se supo del empuje, el pull request no se llegó a pedir: '
            'decir otra cosa sería inventar un hecho remoto',
      );
    });

    test('la causa que la precedencia descartó viaja igual', () {
      // El secreto gana sobre la compuerta, y el estado de la verificación
      // —que también habría detenido la corrida— no se pierde: viaja en el
      // payload, que es lo único que lo lleva.
      final d = ShipOutcome.noIntentadoParaLaPrueba(
        causa: CausaDeNoIntento.secretDetected,
        verificacion: EstadoDeCorrida.rojo,
      );
      final p = payloadDeShip(d);
      expect(p['causa'], 'secretDetected');
      expect(p['verificacion'], 'rojo');
    });

    test('el veredicto sale del estado, y es nulo donde no hay estado', () {
      expect(veredictoDeShip(desenlaceDePrueba()), 'ok');
      expect(
        veredictoDeShip(
          ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'abc123'),
        ),
        isNull,
        reason:
            'un compare-and-swap rechazado no lleva estado de verificación: '
            'darle un veredicto sería afirmar algo que nadie miró',
      );
    });
  });

  group('la frontera conoce el comando', () {
    test('shipflow ship sin argumentos sale 5, no 70', () async {
      expect(await ejecutarDePrueba(['ship']), Codigo.errorDeUso);
    });

    test('la ayuda nombra a ship y sus banderas', () async {
      final texto = await ayudaDePrueba();
      for (final b in [
        'ship',
        '--intent',
        '--file',
        '--slice',
        '--yes',
        '--dry-run',
        '--allow-incomplete',
      ]) {
        expect(texto, contains(b), reason: b);
      }
    });

    test('la ayuda nombra los códigos nuevos', () async {
      final texto = await ayudaDePrueba();
      for (final c in ['3', '4', '6']) {
        expect(texto, contains(c), reason: c);
      }
    });

    test(
      'ship --help imprime la ayuda de ship, no la de la frontera',
      () async {
        final salida = StringBuffer();
        final codigo = await ejecutar(
          const ['ship', '--help'],
          directorio: '.',
          salida: salida,
          error: StringBuffer(),
        );
        expect(codigo, Codigo.exito);
        expect(salida.toString(), contains('shipflow ship'));
        expect(salida.toString(), contains('--allow-incomplete'));
      },
    );

    test('con --json no hay a quién preguntarle, aun con terminal', () {
      // Un consumidor automático no contesta preguntas, y la pregunta sería
      // una línea que no es un envelope: el protocolo roto por cuarta vez.
      expect(responderDeLaTerminal(json: true, hayTerminal: true), isNull);
      expect(responderDeLaTerminal(json: false, hayTerminal: false), isNull);
      expect(
        responderDeLaTerminal(json: false, hayTerminal: true),
        isNotNull,
        reason:
            'sin las dos condiciones no hay pregunta que hacer, y entonces '
            'esta prueba pasaría con cualquiera de las dos borrada',
      );
    });

    test('la tabla de códigos del doc está atada a las constantes', () {
      // El doc de `correrShip` escribe `4` y `5` como literales de prosa. Esto
      // es lo que impide que las constantes se muevan y la tabla quede
      // mintiendo sin que nada se ponga rojo.
      expect(Codigo.errorDeConfiguracion, 4);
      expect(Codigo.errorDeUso, 5);
      expect(Codigo.detencionDeclarada, 3);
      expect(Codigo.entregaIncompleta, 6);
    });
  });

  group('los colaboradores están conectados', () {
    test('--dry-run corre la orquestación entera y no deja nada', () async {
      final mundo = Mundo(conCambioAjeno: true);
      final (codigo, salida, _) = await mundo.correr([
        ..._invocacion,
        '--dry-run',
      ]);
      expect(codigo, Codigo.exito);
      // Nada de esto lo puede producir un comando hueco: la rama y la base
      // salen del preflight sobre el repositorio real, el archivo sale de la
      // rebanada, y la ruta ajena salió de un `git status` de verdad.
      expect(salida, contains('rama: trabajo → main'));
      expect(salida, contains(_archivo));
      expect(salida, contains(_ajeno));
      expect(mundo.commits, isEmpty);
      expect(mundo.forja.recibidas, isEmpty);
    });

    test(
      'la previsualización sale por el canal de eventos, no cruda',
      () async {
        final mundo = Mundo();
        final (_, salida, _) = await mundo.correr([
          ..._invocacion,
          '--dry-run',
          '--json',
        ]);
        final documentos = lineas(salida);
        final previos = documentos
            .where((d) => d['type'] == 'preview')
            .toList();
        expect(previos, hasLength(1));
        expect(previos.single['schema'], esquemaDeSalida);
        expect(previos.single['command'], 'ship');
        expect(
          documentos.last['type'],
          'result',
          reason: 'el resultado es el último, y el preview va antes',
        );
        expect(
          '${(previos.single['data']! as Map)['preview']}',
          contains('rama: trabajo → main'),
        );
      },
    );

    test('--quiet no calla la previsualización', () async {
      // El tipo del evento NO es `progress`: `--quiet` calla el progreso, y
      // el preview es aquello sobre lo que una persona decide.
      final mundo = Mundo();
      final (_, salida, _) = await mundo.correr([
        ..._invocacion,
        '--dry-run',
        '--quiet',
      ]);
      expect(salida, contains('rama: trabajo → main'));
    });

    test('un secreto en la rebanada sale 1 y el payload lo nombra', () async {
      final mundo = Mundo(conSecreto: true);
      final (codigo, salida, _) = await mundo.correr([
        ..._invocacion,
        '--yes',
        '--json',
      ]);
      expect(codigo, Codigo.fallaDeVerificacion);
      final resultado = lineas(salida).last;
      expect((resultado['data']! as Map)['causa'], 'secretDetected');
      expect(mundo.commits, isEmpty);
    });

    test('con --yes se publica: la forja recibió la solicitud', () async {
      final mundo = Mundo();
      final (codigo, _, _) = await mundo.correr([..._invocacion, '--yes']);
      expect(codigo, Codigo.exito);
      expect(mundo.forja.recibidas, hasLength(1));
      expect(mundo.commits, hasLength(1));
      expect(
        mundo.forja.recibidas.single.draft.branch,
        'trabajo',
        reason: 'la rama sale del preflight sobre el repositorio real',
      );
    });

    test(
      'sin terminal, la corrida se comporta como previsualización',
      () async {
        // `responder` nulo es «no hay con quién hablar». No se pregunta nada, y
        // el desenlace es `confirmationMissing`: sale 0 y dice qué falta.
        final mundo = Mundo();
        final (codigo, salida, _) = await mundo.correr(_invocacion);
        expect(codigo, Codigo.exito);
        expect(salida, contains('--yes'));
        expect(mundo.commits, isEmpty);
      },
    );

    test('con terminal, se pregunta y un no detiene la corrida', () async {
      final preguntas = <String>[];
      final mundo = Mundo(
        responder: (pregunta) async {
          preguntas.add(pregunta);
          return false;
        },
      );
      final (codigo, _, _) = await mundo.correr(_invocacion);
      expect(preguntas, hasLength(1));
      expect(codigo, Codigo.exito);
      expect(mundo.commits, isEmpty);
    });
  });

  group('las cuatro salidas por excepción', () {
    test('el preflight rechazado sale 4 y no escribe nada', () async {
      final mundo = Mundo(sinCredencial: true);
      final (codigo, salida, _) = await mundo.correr([..._invocacion, '--yes']);
      expect(codigo, Codigo.errorDeConfiguracion);
      expect(salida, contains('credencial'));
      expect(mundo.commits, isEmpty);
    });

    test('un .gitignore ajeno en el directorio de corridas sale 4', () async {
      final mundo = Mundo();
      File('${mundo.raiz.path}/.shipflow/.gitignore')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('# lo puso otra persona, a propósito\n');
      final (codigo, _, _) = await mundo.correr([..._invocacion, '--yes']);
      expect(codigo, Codigo.errorDeConfiguracion);
      expect(mundo.commits, isEmpty);
    });

    test('un documento de corrida NO ignorado sale 4', () async {
      final mundo = Mundo();
      // El índice es lo que cuenta: una ruta seguida no la ignora ninguna
      // regla, así que el documento terminaría dentro del pull request.
      File('${mundo.raiz.path}/.shipflow/runs/${Mundo.runId}.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}\n');
      Process.runSync('git', [
        'add',
        '-f',
        '.shipflow/runs/${Mundo.runId}.json',
      ], workingDirectory: mundo.raiz.path);
      final (codigo, _, _) = await mundo.correr([..._invocacion, '--yes']);
      expect(codigo, Codigo.errorDeConfiguracion);
    });

    test('una rebanada ilegible sale 5, no 70', () async {
      final mundo = Mundo();
      final (codigo, _, _) = await mundo.correr([
        '--slice',
        '${mundo.raiz.path}/no-existe.json',
      ]);
      expect(codigo, Codigo.errorDeUso);
    });
  });

  group('la forja que no está compuesta', () {
    test(
      'una corrida que PODRÍA publicar se detiene en 4, sin escribir',
      () async {
        final mundo = Mundo(sinForja: true);
        final (codigo, salida, _) = await mundo.correr([
          ..._invocacion,
          '--yes',
        ]);
        expect(codigo, Codigo.errorDeConfiguracion);
        expect(salida, contains('forja'));
        expect(mundo.commits, isEmpty);
      },
    );

    test('un ensayo corre igual: por construcción no publica', () async {
      final mundo = Mundo(sinForja: true);
      final (codigo, salida, _) = await mundo.correr([
        ..._invocacion,
        '--dry-run',
      ]);
      expect(codigo, Codigo.exito);
      expect(salida, contains('rama: trabajo → main'));
    });
  });

  test('el resultado de ship es uno solo y lleva su runId', () async {
    final mundo = Mundo();
    final (_, salida, _) = await mundo.correr([
      ..._invocacion,
      '--yes',
      '--json',
    ]);
    final resultados = lineas(
      salida,
    ).where((d) => d['type'] == 'result').toList();
    expect(resultados, hasLength(1));
    expect(resultados.single['runId'], Mundo.runId);
    expect(resultados.single['command'], 'ship');
    expect(
      resultados.single['verdict'],
      'ok',
      reason: 'el veredicto de ship sale del estado de su verificación',
    );
    expect(
      (resultados.single['data']! as Map)['runId'],
      isNull,
      reason:
          'el runId es del envelope: repetirlo en el payload es el mismo '
          'hecho escrito dos veces, y dos escrituras divergen',
    );
  });
}
