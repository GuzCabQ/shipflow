/// `EntornoDart` contra el resolvedor de verdad, sobre fixtures que resuelven
/// sin red.
///
/// **Precondición declarada:** la toolchain en el `PATH`, y `meta` en el cache
/// local. Lo segundo lo cumple cualquier máquina que haya resuelto este
/// repositorio alguna vez; si falta, los casos que la usan abortan con la
/// evidencia citada en vez de mentir.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

const presupuesto = Duration(minutes: 2);

/// El padre con `PUB_CACHE` apuntando a donde se le diga. Sirve para las dos
/// preguntas: con el cache real, derivar; con uno vacío, qué pasa sin él.
Map<String, String> padreCon(String? cache) => {
  'PATH': Platform.environment['PATH']!,
  'HOME': Platform.environment['HOME']!,
  if (cache != null) 'PUB_CACHE': cache,
  if (cache == null && Platform.environment['PUB_CACHE'] != null)
    'PUB_CACHE': Platform.environment['PUB_CACHE']!,
};

void main() {
  late Directory raiz;

  void escribir(String ruta, String contenido) {
    final f = File('${raiz.path}/$ruta');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  /// Resuelve UNA vez con el cache real para dejar el lockfile —que es lo que un
  /// candidato SÍ trae— y borra lo generado —que es lo que un candidato NO
  /// trae—. Sin esto el fixture no representa un candidato.
  void fijarLockfile(String dir) {
    final d = rutas.join(raiz.path, dir);
    final r = Process.runSync('dart', [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: d);
    if (r.exitCode != 0) {
      throw StateError('no pude fijar el lockfile de $dir: ${r.stderr}');
    }
    // **Todo lo generado, no solo lo de este directorio.** Resolver la raíz de
    // un workspace deja un rastro dentro de CADA miembro —medido: un
    // `workspace_ref.json` por paquete—, y un candidato no trae ninguno. Borrar
    // solo el de la raíz dejaba un fixture que no representa un candidato.
    for (final e in Directory(raiz.path).listSync(recursive: true)) {
      if (e is Directory && rutas.basename(e.path) == '.dart_tool') {
        e.deleteSync(recursive: true);
      }
    }
  }

  /// Un paquete cuyo manifiesto no pide nada de fuera: resuelve incluso con el
  /// cache vacío.
  void paquete(String dir, {String extra = ''}) {
    final nombre = dir == '.' ? 'raiz' : rutas.basename(dir);
    escribir(
      '$dir/pubspec.yaml',
      'name: $nombre\nenvironment:\n  sdk: ^3.11.0\n$extra',
    );
    escribir('$dir/lib/a.dart', 'void a() {}\n');
  }

  Future<ResultadoDeEntorno> derivar(
    List<String> archivos, {
    EjecutorDeProceso? ejecutor,
    String? cache,
    String programa = 'dart',
  }) => EntornoDart(
    ejecutor: ejecutor ?? EjecutorDelSistema(entornoDelPadre: padreCon(cache)),
    programa: programa,
  ).derivar(raiz.path, archivos: archivos, presupuesto: presupuesto);

  setUp(() => raiz = Directory.systemTemp.createTempSync('entorno_'));
  tearDown(() => raiz.deleteSync(recursive: true));

  group('deriva', () {
    test(
      'un paquete con lockfile queda derivado, y el lockfile no se toca',
      () async {
        paquete('.');
        fijarLockfile('.');
        final antes = File('${raiz.path}/pubspec.lock').readAsBytesSync();

        final r = await derivar(['lib/a.dart']);
        expect(r, isA<EntornoDerivado>(), reason: '$r');
        final d = r as EntornoDerivado;
        expect(d.raices, 1);
        expect(d.paquetes, greaterThanOrEqualTo(1));
        expect(d.toolchain.version.content, contains('version'));
        expect(
          File('${raiz.path}/.dart_tool/package_config.json').existsSync(),
          isTrue,
          reason: 'la derivación escribe DENTRO del candidato',
        );
        expect(
          File('${raiz.path}/pubspec.lock').readAsBytesSync(),
          antes,
          reason: 'el lockfile del candidato manda: no se reescribe',
        );
      },
    );

    test(
      'con el cache VACÍO, un paquete que no pide nada de fuera igual deriva',
      () async {
        paquete('.');
        fijarLockfile('.');
        final cache = Directory.systemTemp.createTempSync('cache_vacio_');
        try {
          final r = await derivar(['lib/a.dart'], cache: cache.path);
          expect(r, isA<EntornoDerivado>(), reason: '$r');
        } finally {
          cache.deleteSync(recursive: true);
        }
      },
    );

    test(
      'una restricción nueva que el lockfile ya satisface queda derivada',
      () async {
        paquete('.', extra: 'dependencies:\n  meta: ^1.0.0\n');
        fijarLockfile('.');
        // Se relaja la restricción: el lockfile sigue satisfaciéndola, así que
        // no hay nada que re-resolver y `--enforce-lockfile` no se queja.
        escribir(
          'pubspec.yaml',
          'name: raiz\nenvironment:\n  sdk: ^3.11.0\n'
              'dependencies:\n  meta: ">=1.0.0"\n',
        );
        expect(await derivar(['lib/a.dart']), isA<EntornoDerivado>());
      },
    );

    /// La forma de este repositorio, en un fixture: raíz de workspace con
    /// miembros, un paquete que no es miembro y tiene lockfile propio, y uno con
    /// otra toolchain que ninguna rebanada de acá toca.
    void comoEsteRepositorio() {
      escribir(
        'pubspec.yaml',
        'name: ws\nenvironment:\n  sdk: ^3.11.0\n'
            'workspace:\n  - packages/a\n  - packages/b\n',
      );
      paquete('packages/a', extra: 'resolution: workspace\n');
      paquete(
        'packages/b',
        extra: 'resolution: workspace\ndependencies:\n  a:\n    path: ../a\n',
      );
      paquete('tool/analisis');
      escribir(
        'fixtures/app/pubspec.yaml',
        'name: app\nenvironment:\n  sdk: ^3.11.0\n  flutter: ">=3.18.0"\n'
            'dependencies:\n  flutter:\n    sdk: flutter\n',
      );
      escribir('fixtures/app/lib/main.dart', 'void main() {}\n');
      fijarLockfile('.');
      fijarLockfile('tool/analisis');
    }

    test('una rebanada que toca un miembro deriva UNA raíz, y lo que no toca '
        'no se deriva ni se rechaza', () async {
      comoEsteRepositorio();
      final r = await derivar(['packages/a/lib/a.dart']);
      expect(r, isA<EntornoDerivado>(), reason: '$r');
      expect((r as EntornoDerivado).raices, 1);
      expect(
        Directory('${raiz.path}/tool/analisis/.dart_tool').existsSync(),
        isFalse,
      );
      expect(
        Directory('${raiz.path}/fixtures/app/.dart_tool').existsSync(),
        isFalse,
        reason:
            'el de la otra toolchain no se toca, así que no se deriva ni se '
            'rechaza: derivarlo sería pagar por nada el riesgo de una '
            'toolchain que acá está y en el runner no',
      );
    });

    test('una rebanada que toca el miembro Y el que no es miembro deriva DOS '
        'raíces', () async {
      comoEsteRepositorio();
      final r = await derivar([
        'packages/a/lib/a.dart',
        'tool/analisis/lib/a.dart',
      ]);
      expect(r, isA<EntornoDerivado>(), reason: '$r');
      expect((r as EntornoDerivado).raices, 2);
      expect(
        Directory('${raiz.path}/tool/analisis/.dart_tool').existsSync(),
        isTrue,
      );
      expect(
        Directory('${raiz.path}/fixtures/app/.dart_tool').existsSync(),
        isFalse,
      );
    });

    test(
      'derivar dos veces sobre el MISMO candidato rechaza la segunda',
      () async {
        // **Precondición del puerto, no un defecto.** El control mira el disco
        // —acá no hay git ni debe haberlo—, y después de derivar el disco ya tiene
        // lo generado. Quien recomponga una corrida prepara un candidato nuevo.
        // Esta prueba fija esa lectura para que nadie la descubra en producción.
        paquete('.');
        fijarLockfile('.');
        expect(await derivar(['lib/a.dart']), isA<EntornoDerivado>());
        final segunda = await derivar(['lib/a.dart']);
        expect(segunda, isA<CandidatoRechazado>(), reason: '$segunda');
        expect(
          (segunda as CandidatoRechazado).causa,
          CausaDeRechazo.elArbolVersionaLoQueSeGenera,
        );
      },
    );

    test('sin ningún manifiesto: cero raíces, derivado igual', () async {
      escribir('a.txt', 'x');
      final r = await derivar(['a.txt']);
      expect(r, isA<EntornoDerivado>(), reason: '$r');
      expect((r as EntornoDerivado).raices, 0);
      expect(r.paquetes, 0);
      expect(
        r.toolchain.version.content,
        contains('version'),
        reason:
            'el testigo dice con qué se midió aunque no haya nada que medir',
      );
    });
  });

  group('rechaza al candidato', () {
    test(
      'un lockfile que no satisface el manifiesto, y el lockfile no se toca',
      () async {
        paquete('.');
        fijarLockfile('.');
        final antes = File('${raiz.path}/pubspec.lock').readAsBytesSync();
        escribir(
          'pubspec.yaml',
          'name: raiz\nenvironment:\n  sdk: ^3.11.0\n'
              'dependencies:\n  meta: ^1.0.0\n',
        );
        final r = await derivar(['lib/a.dart']);
        expect(r, isA<CandidatoRechazado>(), reason: '$r');
        expect(
          (r as CandidatoRechazado).causa,
          CausaDeRechazo.pubRechazoLaResolucion,
        );
        expect(r.evidencia.content, contains('lock'));
        expect(File('${raiz.path}/pubspec.lock').readAsBytesSync(), antes);
      },
    );

    test('una raíz tocada SIN lockfile se rechaza', () async {
      // La respuesta a la pregunta abierta: `--enforce-lockfile` no tiene
      // contra qué comprobar, así que el candidato no dice qué se ejecuta.
      paquete('.');
      final r = await derivar(['lib/a.dart']);
      expect(r, isA<CandidatoRechazado>(), reason: '$r');
      expect(
        (r as CandidatoRechazado).causa,
        CausaDeRechazo.pubRechazoLaResolucion,
      );
      expect(r.evidencia.content, contains('lock'));
    });

    test(
      'cache vacío con una dependencia de fuera: dijo que no, y se cita',
      () async {
        // **No se adivina la causa.** Está medido que el resolvedor sale con el
        // mismo código acá que con un SDK desconocido en el manifiesto, así que
        // distinguirlos exigiría leerle frases a la salida de error. Es un
        // rechazo con la evidencia literal, y la corrida sale no concluyente
        // igual que si fuera un aborto.
        paquete('.', extra: 'dependencies:\n  meta: ^1.0.0\n');
        fijarLockfile('.');
        final cache = Directory.systemTemp.createTempSync('cache_vacio_');
        try {
          final r = await derivar(['lib/a.dart'], cache: cache.path);
          expect(r, isA<CandidatoRechazado>(), reason: '$r');
          expect(
            (r as CandidatoRechazado).causa,
            CausaDeRechazo.pubRechazoLaResolucion,
          );
          expect(r.evidencia.content, isNotEmpty);
        } finally {
          cache.deleteSync(recursive: true);
        }
      },
    );

    test('lo generado versionado se rechaza ANTES de correr nada', () async {
      paquete('.');
      fijarLockfile('.');
      escribir('.dart_tool/package_config.json', '{}');
      final ejecutor = EjecutorDeclarado(
        const ResultadoDeProceso(
          terminacion: Termination.completa,
          codigo: 0,
          salidaEstandar: '',
          salidaDeError: '',
        ),
      );
      final r = await derivar(['lib/a.dart'], ejecutor: ejecutor);
      expect(r, isA<CandidatoRechazado>(), reason: '$r');
      expect(
        (r as CandidatoRechazado).causa,
        CausaDeRechazo.elArbolVersionaLoQueSeGenera,
      );
      expect(
        ejecutor.invocaciones,
        isEmpty,
        reason: 'derivar lo destruiría, así que se detecta antes de invocar',
      );
    });

    test('una dependencia por ruta que escapa del candidato', () async {
      final fuera = Directory.systemTemp.createTempSync('fuera_');
      try {
        File(
          '${fuera.path}/pubspec.yaml',
        ).writeAsStringSync('name: fuera\nenvironment:\n  sdk: ^3.11.0\n');
        Directory('${fuera.path}/lib').createSync();
        paquete(
          '.',
          extra: 'dependencies:\n  fuera:\n    path: ${fuera.path}\n',
        );
        fijarLockfile('.');
        final r = await derivar(['lib/a.dart']);
        expect(r, isA<CandidatoRechazado>(), reason: '$r');
        expect(
          (r as CandidatoRechazado).causa,
          CausaDeRechazo.dependenciaPathQueEscapa,
        );
        expect(r.evidencia.content, contains('fuera'));
      } finally {
        fuera.deleteSync(recursive: true);
      }
    });

    test('una dependencia por ruta que queda adentro no escapa', () async {
      paquete('adentro');
      paquete('.', extra: 'dependencies:\n  adentro:\n    path: adentro\n');
      fijarLockfile('.');
      final r = await derivar(['lib/a.dart']);
      expect(r, isA<EntornoDerivado>(), reason: '$r');
    });
  });

  group('aborta la derivación', () {
    ResultadoDeProceso incompleto(Termination t) => ResultadoDeProceso(
      terminacion: t,
      codigo: -1,
      salidaEstandar: '',
      salidaDeError: 'no se pudo invocar',
    );

    test('herramienta ausente, nunca un verde', () async {
      paquete('.');
      fijarLockfile('.');
      final r = await derivar(
        ['lib/a.dart'],
        ejecutor: EjecutorDeclarado(incompleto(Termination.herramientaAusente)),
      );
      expect(r, isA<DerivacionAbortada>(), reason: '$r');
      expect(
        (r as DerivacionAbortada).terminacion,
        Termination.herramientaAusente,
      );
      expect(r.evidencia.content, contains('no se pudo invocar'));
    });

    test('presupuesto agotado', () async {
      paquete('.');
      fijarLockfile('.');
      final r = await derivar([
        'lib/a.dart',
      ], ejecutor: EjecutorDeclarado(incompleto(Termination.tiempoAgotado)));
      expect(r, isA<DerivacionAbortada>(), reason: '$r');
      expect((r as DerivacionAbortada).terminacion, Termination.tiempoAgotado);
    });

    test('la toolchain que sale con código distinto de cero NO identifica '
        'nada', () async {
      // Reproducido en el review: terminación completa y código 17 producían un
      // entorno DERIVADO cuya identidad de toolchain era el texto de un error.
      paquete('.');
      fijarLockfile('.');
      final r = await derivar(
        ['lib/a.dart'],
        ejecutor: EjecutorDeclarado(
          const ResultadoDeProceso(
            terminacion: Termination.completa,
            codigo: 17,
            salidaEstandar: '',
            salidaDeError: 'la toolchain se rompió',
          ),
        ),
      );
      expect(r, isA<DerivacionAbortada>(), reason: '$r');
      expect(
        (r as DerivacionAbortada).causa,
        CausaDeAborto.laToolchainNoSeIdentifico,
      );
      expect(r.terminacion, Termination.completa);
      expect(r.evidencia.content, contains('la toolchain se rompió'));
    });

    test('la toolchain MUDA tampoco identifica nada', () async {
      // El peor de los dos: la «identidad» era la frase que arma `_texto` para
      // poder citar un proceso mudo. Una cadena nuestra satisfaciendo al
      // constructor que existe para rechazar justo eso.
      paquete('.');
      fijarLockfile('.');
      final r = await derivar(
        ['lib/a.dart'],
        ejecutor: EjecutorDeclarado(
          const ResultadoDeProceso(
            terminacion: Termination.completa,
            codigo: 0,
            salidaEstandar: '',
            salidaDeError: '',
          ),
        ),
      );
      expect(r, isA<DerivacionAbortada>(), reason: '$r');
      expect(
        (r as DerivacionAbortada).causa,
        CausaDeAborto.laToolchainNoSeIdentifico,
      );
    });

    test('la identidad es lo que la herramienta DIJO, no lo que armamos para '
        'citarla', () async {
      paquete('.');
      fijarLockfile('.');
      final r = await derivar(['lib/a.dart']) as EntornoDerivado;
      expect(r.toolchain.version.content, isNot(contains('sin salida')));
      expect(r.toolchain.version.content, contains('version'));
    });

    test(
      'con el ejecutable ausente DE VERDAD, el ejecutor real lo dice',
      () async {
        // El ejecutor declarado es donde uno escribiría lo que cree que pasa.
        // Esto lo comprueba contra el sistema.
        paquete('.');
        fijarLockfile('.');
        final r = await derivar([
          'lib/a.dart',
        ], programa: '/no/existe/toolchain');
        expect(r, isA<DerivacionAbortada>(), reason: '$r');
        expect(
          (r as DerivacionAbortada).terminacion,
          Termination.herramientaAusente,
        );
      },
    );
  });
}
