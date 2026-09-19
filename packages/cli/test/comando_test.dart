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

import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:forge/forge.dart';
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

/// Un remoto que la fábrica del paquete de la forja SÍ atiende. Se escribe en
/// el repositorio de verdad y nadie sale a la red por él: lo único que se hace
/// con esta URL es leerla y decidir.
const remotoAtendible = 'https://github.com/duenio/repo.git';

/// La MISMA forja del remoto atendible, alcanzada por un canal que no puede
/// llevar la credencial. Se lee perfectamente —salen el dueño y el
/// repositorio— y aun así no se atiende: la publicación la rechazaría, y
/// preparar la corrida entera para eso es lo que el preflight evita.
const remotoAtendidoSinCanalSeguro = 'git@github.com:duenio/repo.git';

/// Un remoto bien formado que **ninguna forja conocida atiende**.
const remotoAjeno = 'https://una.forja.desconocida/duenio/repo.git';

/// El host de ese remoto, aparte, porque las pruebas de fuga afirman sobre él:
/// la URL entera es tan secreta como la credencial que puede traer adentro.
const hostDelRemotoAjeno = 'una.forja.desconocida';

/// Lo que ese remoto puede traer embebido en su autoridad. Quien lo configuró
/// no autorizó publicarlo por ningún canal.
///
/// **Distinto del que lleva la credencial de la forja en esta suite**, a
/// propósito: con el mismo texto, una fuga de uno se leería como del otro y la
/// prueba señalaría el canal equivocado.
const secretoDelRemoto = 'secreto-embebido-en-el-remoto';

/// El mismo remoto ajeno, con la credencial adentro.
const remotoConCredencial =
    'https://usuario:$secretoDelRemoto@$hostDelRemotoAjeno/d/r.git';

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

/// Un registro que escribe como el de verdad y **no se deja releer**: es el
/// documento ilegible o corrupto DESPUÉS de que la publicación ya ocurrió.
///
/// Lanza un error y no una excepción a propósito: la familia de fallos que
/// produce un documento con la forma equivocada llega así, y es justamente la
/// que una lista de tipos atrapados dejaría afuera.
class _RegistroQueNoSeDejaReleer extends RegistroDeCorridas {
  _RegistroQueNoSeDejaReleer({required super.raiz});

  @override
  Future<DocumentoDeCorrida?> leer(String runId) async =>
      throw StateError('el documento de $runId no se puede leer');
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

  /// Si el documento de la corrida se deja releer al final. En falso, la
  /// corrida escribe todo como siempre y la relectura del payload falla.
  final bool documentoIlegible;

  /// El documento de esta corrida ya está en el índice de `git`, así que
  /// `check-ignore` lo declara NO ignorado y la corrida se detiene en el paso
  /// 9 — después de que ese mismo paso creó el directorio de corridas.
  final bool documentoVersionado;

  /// El remoto que este repositorio tiene configurado, o **nulo si no tiene
  /// ninguno**. Se escribe en el repositorio de verdad, y de ahí lo lee la
  /// composición: sin eso, «hay remoto» sería un hecho que la prueba le
  /// declara al código en vez de uno que el código mide.
  final String? remoto;

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
    this.documentoIlegible = false,
    this.documentoVersionado = false,
    this.remoto = remotoAtendible,
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
    final url = remoto;
    if (url != null) _git(['remote', 'add', 'origin', url]);
    repo = RepositorioGit(
      directorio: raiz.path,
      politica: PoliticaDeArtefactosFalsa(),
    );
    registro = documentoIlegible
        ? _RegistroQueNoSeDejaReleer(raiz: '${raiz.path}/.shipflow')
        : RegistroDeCorridas(raiz: '${raiz.path}/.shipflow');
    if (conCambioAjeno) _escribir(_ajeno, 'trabajo de al lado\n');
    if (documentoVersionado) {
      // El índice es lo que cuenta: se agrega y se borra del árbol, así que
      // la ruta queda seguida sin dejar en el disco un documento ilegible.
      _escribir('.shipflow/runs/$runId.json', '{}\n');
      _git(['add', '-f', '.shipflow/runs/$runId.json']);
      File('${raiz.path}/.shipflow/runs/$runId.json').deleteSync();
    }
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
    urlDelRemoto: repo.urlDelRemoto,
    forjaDelRemoto: _forjaDelRemoto,
    registro: registro,
    cambiosAjenos: (List<String> archivos) =>
        cambiosAjenosDelArbol(directorio: raiz.path, deLaRebanada: archivos),
    responder: responder,
    leerArchivo: (String ruta) => File(ruta).readAsString(),
    nuevoRunId: () => runId,
    baseConfigurada: 'main',
  );

  /// Quién atiende el remoto: **la decisión la toma la fábrica de verdad, y
  /// lo que se reemplaza es solo el efecto remoto**.
  ///
  /// Con un predicado inventado acá, esta suite mediría su propio predicado:
  /// pasaría igual con la fábrica desconectada de la composición. Llamándola
  /// de verdad, lo que se fija es que una URL atendible produce una salida y
  /// una ajena produce nulo — y el doble entra recién después, para que la
  /// publicación no salga a la red.
  PullRequestSink? _forjaDelRemoto(String url) =>
      salidaDePrDelRemoto(
            urlDelRemoto: url,
            credenciales: const FuenteDeCredencialFalsa(),
            claveDeCredencial: claveDeCredencialDeLaForja,
            directorio: raiz.path,
            entornoDelPadre: EntornoDelProceso(const {}),
          ) ==
          null
      ? null
      : forja;

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

  /// La revisión a la que apunta [referencia], leída del repositorio real.
  String revisionDe(String referencia) => _git(['rev-parse', referencia]);

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

    test('«documentUnreadable» solo aparece cuando la relectura falló', () {
      expect(
        payloadDeShip(desenlaceDePrueba()).containsKey('documentUnreadable'),
        isFalse,
        reason:
            'sin documento y sin que nadie haya intentado releerlo, no hay '
            'nada que señalar',
      );
      expect(
        payloadDeShip(
          desenlaceDePrueba(),
          documentoIlegible: true,
        )['documentUnreadable'],
        isTrue,
      );
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

    test('el payload de un no-intentado lleva la causa Y la verificación', () {
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
          ShipOutcome.noAplicadoParaLaPrueba(
            causa: CausaDeNoAplicacion.baseMovida,
            headObservado: 'abc123',
          ),
        ),
        isNull,
        reason:
            'un compare-and-swap rechazado no lleva estado de verificación: '
            'darle un veredicto sería afirmar algo que nadie miró',
      );
    });
  });

  group('los cuatro campos que se releen del documento', () {
    test('una corrida que publicó los lleva los cuatro', () async {
      final mundo = Mundo();
      final (codigo, salida, _) = await mundo.correr([
        ..._invocacion,
        '--yes',
        '--json',
      ]);
      expect(codigo, Codigo.exito);
      final datos = lineas(salida).last['data']! as Map;
      expect(datos['branch'], 'trabajo');
      expect(datos['base'], 'main');
      expect(
        datos['revision'],
        mundo.commits.single,
        reason:
            'la revisión es la del commit que la corrida dejó en la rama, no '
            'una que el payload arme por su cuenta',
      );
      final candidato = datos['candidate']! as Map;
      expect(candidato['contentRevision'], isNotEmpty);
      expect(
        candidato['baseRevision'],
        mundo.revisionDe('main'),
        reason: 'el candidato se construyó sobre la base que el CAS exigió',
      );
    });

    test(
      'una corrida que no intentó no lleva NINGUNO, y sin claves en nulo',
      () async {
        // Una corrida que no intentó no TIENE revisión: un campo presente con
        // nulo adentro sería el invento. Y `--dry-run` no escribe documento, que
        // es de donde se releen los cuatro.
        final mundo = Mundo();
        final (_, salida, _) = await mundo.correr([
          ..._invocacion,
          '--dry-run',
          '--json',
        ]);
        final datos = lineas(salida).last['data']! as Map;
        for (final clave in const ['branch', 'base', 'revision', 'candidate']) {
          expect(
            datos.containsKey(clave),
            isFalse,
            reason: 'la clave «$clave» no tiene que estar, ni siquiera en nulo',
          );
        }
        // **La ausencia HONESTA: no hay clave que diga que no se pudo leer**,
        // porque acá no hubo nada que leer. Confundirla con la de abajo —el
        // documento que sí se escribió y no se dejó releer— es exactamente lo
        // que un consumidor automático no puede permitirse: leería «no se
        // escribió nada» donde en realidad pasó lo otro.
        expect(datos.containsKey('documentUnreadable'), isFalse);
      },
    );

    test(
      'un documento que no se deja releer NO borra la publicación',
      () async {
        // La relectura es un enriquecimiento y corre después de que el pull
        // request ya se abrió. Si su fallo subiera como los de la corrida,
        // esta invocación saldría `70` —«se rompió el arnés»— y se perdería el
        // único hecho que volver a correr no reconstruye, porque ya ocurrió
        // del otro lado. Lo que se pierde son los cuatro campos, y nada más.
        final mundo = Mundo(documentoIlegible: true);
        final (codigo, salida, _) = await mundo.correr([
          ..._invocacion,
          '--yes',
          '--json',
        ]);
        expect(
          codigo,
          Codigo.exito,
          reason: 'el desenlace publicado sobrevive a la relectura',
        );
        expect(mundo.forja.recibidas, hasLength(1));
        final datos = lineas(salida).last['data']! as Map;
        for (final clave in const ['branch', 'base', 'revision', 'candidate']) {
          expect(datos.containsKey(clave), isFalse);
        }
        // **La otra ausencia, y esta SÍ tiene que decir por qué.** Sin esta
        // clave, esta corrida y la de arriba —la que nunca escribió
        // documento— se leen exactamente igual: las dos cuentan cuatro
        // ausencias. Y son hechos distintos — acá SÍ hubo una corrida que
        // escribió, y lo que falló fue releerla DESPUÉS de que el pull
        // request ya se hubiera abierto.
        expect(
          datos['documentUnreadable'],
          isTrue,
          reason:
              'la ausencia de los cuatro campos tiene dos causas distintas, y '
              'un consumidor automático no puede adivinar cuál de las dos '
              'pasó sin esta clave',
        );
      },
    );
  });

  group('la frontera conoce el comando', () {
    test('shipflow ship sin argumentos sale 5, no 70', () async {
      expect(await ejecutarDePrueba(['ship']), Codigo.errorDeUso);
    });

    test('la ayuda nombra la entrada de ship, con sus banderas', () async {
      final texto = await ayudaDePrueba();
      // **Anclado a la entrada del comando, no al nombre suelto.** La primera
      // línea de esta ayuda ya dice «shipflow», así que `contains('ship')`
      // pasaría aunque se borrara la entrada entera de `ship` — sobrevivía
      // solo porque las banderas viven nada más que en esa línea. Localizar
      // la entrada primero hace que borrarla ponga roja esta prueba.
      final inicio = texto.indexOf('ship [opciones]');
      expect(
        inicio,
        isNot(-1),
        reason: 'la ayuda de la frontera tiene que listar la entrada de ship',
      );
      final entrada = texto.substring(inicio, texto.indexOf('\n\n', inicio));
      for (final b in [
        '--intent',
        '--file',
        '--slice',
        '--branch',
        '--base',
        '--dry-run',
        '--yes',
        '--allow-incomplete',
      ]) {
        expect(entrada, contains(b), reason: b);
      }
    });

    test('la ayuda nombra los códigos nuevos en su línea de códigos', () async {
      // Anclado a la línea de «Códigos:» y no al texto entero: cualquier
      // dígito futuro en la prosa no tiene que poder aprobar esto.
      final texto = await ayudaDePrueba();
      final inicio = texto.indexOf('Códigos:');
      expect(inicio, isNot(-1));
      final lineaDeCodigos = texto.substring(inicio);
      for (final c in ['3', '4', '6']) {
        expect(lineaDeCodigos, contains(c), reason: c);
      }
    });

    test('la ayuda de ship nombra sus propios códigos, en su línea', () async {
      // `ayudaDeShip` —la que lee quien corre `shipflow ship --help`— es un
      // texto propio, no la de la frontera, y no tenía ninguna prueba de sus
      // códigos.
      final salida = StringBuffer();
      await ejecutar(
        const ['ship', '--help'],
        directorio: '.',
        salida: salida,
        error: StringBuffer(),
      );
      final texto = salida.toString();
      final inicio = texto.indexOf('Códigos:');
      expect(inicio, isNot(-1));
      final lineaDeCodigos = texto.substring(inicio);
      for (final c in ['3', '4', '6']) {
        expect(lineaDeCodigos, contains(c), reason: c);
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

    test(
      'la confirmación sale por el canal de eventos, no solo al que responde',
      () async {
        // La prueba de arriba comprueba que se llamó a quien responde; esta
        // comprueba que la PREGUNTA salió por el canal de eventos con su
        // propio tipo, la misma afirmación que ya se cierra para la
        // previsualización. Borrar la emisión de acá dejaría a esa otra
        // prueba entera en verde.
        final mundo = Mundo(responder: (_) async => false);
        final (_, salida, _) = await mundo.correr([..._invocacion, '--json']);
        final documentos = lineas(salida);
        final confirmaciones = documentos
            .where((d) => d['type'] == 'confirmation')
            .toList();
        expect(confirmaciones, hasLength(1));
        expect(confirmaciones.single['schema'], esquemaDeSalida);
        expect(confirmaciones.single['command'], 'ship');
        expect(
          (confirmaciones.single['data']! as Map)['question'],
          contains('¿Se publica'),
        );
        expect(
          documentos.last['type'],
          'result',
          reason: 'el resultado es el último, y la confirmación va antes',
        );
      },
    );
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

  group('la forja sale del remoto del repositorio', () {
    test(
      'sin remoto, una corrida que PODRÍA publicar se detiene en 4',
      () async {
        final mundo = Mundo(remoto: null);
        final (codigo, salida, _) = await mundo.correr([
          ..._invocacion,
          '--yes',
        ]);
        expect(codigo, Codigo.errorDeConfiguracion);
        expect(
          salida,
          contains('no tiene remoto configurado'),
          reason: 'el mensaje dice POR QUÉ no se puede publicar',
        );
        expect(mundo.commits, isEmpty);
      },
    );

    test(
      'con un remoto que nadie atiende, también 4 y con OTRO motivo',
      () async {
        // El mismo código por una causa distinta. Un mensaje único dejaría a
        // quien corre averiguando cuál de los dos le pasó: agregar un remoto no
        // es lo mismo que apuntarlo a otro lado.
        final mundo = Mundo(remoto: remotoAjeno);
        final (codigo, salida, _) = await mundo.correr([
          ..._invocacion,
          '--yes',
        ]);
        expect(codigo, Codigo.errorDeConfiguracion);
        expect(salida, contains('ninguna forja conocida sepa atender'));
        expect(salida, isNot(contains('no tiene remoto configurado')));
        expect(mundo.commits, isEmpty);
      },
    );

    test('el documento no ignorado sale 4, y el consejo dice QUÉ quedó '
        'escrito', () async {
      // **El texto que mentía.** El paso 9 llama a `asegurarGitignore` antes
      // del control que lanza, y esa función crea el directorio de corridas y
      // escribe su regla antes de devolver: en el primer uso quedan las dos
      // cosas. El consejo decía «No se escribió nada», justo donde alguien lo
      // lee para decidir si tiene que limpiar algo.
      final mundo = Mundo(documentoVersionado: true);
      final (codigo, salida, _) = await mundo.correr([..._invocacion, '--yes']);
      expect(codigo, Codigo.errorDeConfiguracion);
      expect(mundo.commits, isEmpty);
      expect(
        salida,
        isNot(contains('No se escribió nada')),
        reason: 'es falso: el directorio de corridas y su regla quedaron',
      );
      expect(salida, contains('directorio de corridas'));
      expect(salida, contains('inerte'));
      // Y el disco lo confirma, que es lo que vuelve comprobable al texto.
      expect(
        File('${mundo.raiz.path}/.shipflow/.gitignore').existsSync(),
        isTrue,
      );
    });

    test('un remoto de una forja atendida por un canal que no lo es: 4 y cero '
        'escrituras', () async {
      // **El caso que antes se preparaba entero para fallar al final.** De
      // esta forma salen el dueño y el repositorio, así que la fábrica
      // devolvía una salida y la corrida escribía el commit y el documento
      // para morir recién en la publicación. Lo que esta prueba mide es lo
      // que el preflight promete: si algo falla, no se preparó nada.
      final mundo = Mundo(remoto: remotoAtendidoSinCanalSeguro);
      final (codigo, salida, _) = await mundo.correr([..._invocacion, '--yes']);
      expect(codigo, Codigo.errorDeConfiguracion);
      expect(mundo.commits, isEmpty, reason: 'cero escrituras');
      // La regla dura: ninguna prohibición se instala sin su alternativa, y
      // acá hay DOS causas posibles. Decir solo «apuntalo a una forja
      // soportada» sería falso para este remoto, cuya forja sí se soporta.
      expect(
        salida,
        contains('git remote set-url'),
        reason: 'el mensaje dice cómo cambiar el remoto propio',
      );
      expect(salida, contains('https'));
      // **El caso que antes NO se distinguía.** Esta forja SÍ se atiende —es
      // la misma que `remotoAjeno` no nombra— así que el texto humano no
      // puede decir lo mismo que dice para una forja desconocida: eso manda
      // a sospechar de la forja cuando lo que falla es el protocolo.
      expect(
        salida,
        isNot(contains('ninguna forja conocida sepa atender')),
        reason:
            'esta forja se conoce; lo que no se atiende es el protocolo del '
            'remoto, y decir lo mismo que para una desconocida es falso acá',
      );
      expect(
        salida,
        contains('protocolo'),
        reason: 'el texto humano nombra qué es lo que no se atiende',
      );
    });

    test('el payload de máquina distingue las dos causas, no solo el texto '
        'humano', () async {
      // **El hueco que esta prueba cierra.** El texto humano ya distingue
      // forja desconocida de protocolo no atendible —las pruebas de
      // arriba lo miden—, pero antes `data.error` decía lo mismo
      // («remoto sin forja que lo atienda») para las dos causas. Un
      // consumidor automático no puede leer un texto pensado para
      // persona: necesita una clave que sea DISTINTA en cada rama.
      Future<Object?> causaDe(String remoto) async {
        final mundo = Mundo(remoto: remoto);
        final (codigo, salida, _) = await mundo.correr([
          ..._invocacion,
          '--yes',
          '--json',
        ]);
        expect(codigo, Codigo.errorDeConfiguracion);
        final datos = lineas(salida).last['data']! as Map;
        return datos['causa'];
      }

      final causaForjaDesconocida = await causaDe(remotoAjeno);
      final causaProtocolo = await causaDe(remotoAtendidoSinCanalSeguro);

      expect(
        causaForjaDesconocida,
        CausaDeAusenciaDeForja.forjaDesconocida.name,
        reason:
            'el discriminador usa el mismo vocabulario que ya expone '
            'causaDeAusenciaDeForja, no una frase nueva',
      );
      expect(causaProtocolo, CausaDeAusenciaDeForja.protocoloNoAtendible.name);
      // La afirmación que de verdad importa: si las dos ramas emitieran
      // el mismo valor, la distinción no llegó al payload aunque las dos
      // líneas de arriba pasaran cada una por separado con literales
      // distintos escritos a mano.
      expect(
        causaForjaDesconocida,
        isNot(causaProtocolo),
        reason: 'dos causas distintas no pueden compartir discriminador',
      );
    });

    test('la URL del remoto NO se imprime por la salida estándar', () async {
      // **Primero el canal, después la ausencia.** Un remoto puede llevar la
      // credencial embebida en su autoridad, y esta detención es el único
      // texto de la corrida que tiene la URL a mano. Afirmar solo las dos
      // ausencias dejaría la prueba verde con el mensaje borrado entero, o
      // con el comando muerto antes de llegar a él: dos cambios que no
      // arreglan ninguna fuga. Por eso se exige el código y se exige que el
      // mensaje ESTÉ, y recién sobre ese mensaje se afirma lo que no lleva.
      final mundo = Mundo(remoto: remotoConCredencial);
      final (codigo, salida, _) = await mundo.correr([..._invocacion, '--yes']);
      expect(codigo, Codigo.errorDeConfiguracion);
      expect(salida, contains('ninguna forja conocida sepa atender'));
      expect(salida, isNot(contains(secretoDelRemoto)));
      expect(salida, isNot(contains(hostDelRemotoAjeno)));
    });

    test('ni la lleva ninguna clave del payload de máquina', () async {
      // La variante de arriba corre SIN el protocolo de máquina, así que el
      // payload no sale y nadie lo mira: sin esta, «tampoco por el payload»
      // sería una afirmación sobre un canal que la prueba nunca abrió. Acá el
      // payload existe —se exige que exista— y se lo recorre entero, claves y
      // valores, porque una fuga no elige por dónde sale.
      final mundo = Mundo(remoto: remotoConCredencial);
      final (codigo, salida, _) = await mundo.correr([
        ..._invocacion,
        '--yes',
        '--json',
      ]);
      expect(codigo, Codigo.errorDeConfiguracion);
      final eventos = lineas(salida);
      final resultado = eventos.last;
      expect(
        resultado['exitCode'],
        Codigo.errorDeConfiguracion,
        reason: 'el payload que se revisa es el de ESTA detención',
      );
      expect(
        resultado['nextAction'],
        isNotNull,
        reason:
            'la acción siguiente viaja en el payload: es donde una URL '
            'nombrada se filtraría sin pasar por la salida humana',
      );
      final crudo = jsonEncode(eventos);
      expect(crudo, isNot(contains(secretoDelRemoto)));
      expect(crudo, isNot(contains(hostDelRemotoAjeno)));
    });

    test('un ensayo corre igual: por construcción no publica', () async {
      final mundo = Mundo(remoto: null);
      final (codigo, salida, _) = await mundo.correr([
        ..._invocacion,
        '--dry-run',
      ]);
      expect(codigo, Codigo.exito);
      expect(salida, contains('rama: trabajo → main'));
    });
  });

  test('fuera de un repositorio se sale 4, no 70', () async {
    // **Sin ningún doble**: esta invocación entra por la composición real.
    // Antes salía por la red de último recurso —«se rompió el arnés,
    // reportalo con la traza»— porque la rama se leía adentro del bloque que
    // solo atrapa las cuatro excepciones declaradas. No estar parado en un
    // repositorio no es un fallo del arnés.
    final afuera = Directory.systemTemp.createTempSync('ship_sin_repo_');
    addTearDown(() => afuera.deleteSync(recursive: true));
    final salida = StringBuffer();
    final codigo = await ejecutar(
      ['ship', ..._invocacion, '--yes'],
      directorio: afuera.path,
      salida: salida,
      error: StringBuffer(),
    );
    expect(codigo, Codigo.errorDeConfiguracion);
    expect(salida.toString(), contains('no se pudo leer el repositorio'));
    expect(salida.toString(), contains('repositorio de trabajo'));
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
