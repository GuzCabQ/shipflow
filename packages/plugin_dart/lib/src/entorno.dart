/// La primera implementación de `VerificationEnvironment`: el entorno se
/// **deriva** del candidato, nunca se presta del árbol de trabajo del usuario.
///
/// Prestarlo haría que la cascada midiera sobre resoluciones que ningún commit
/// contiene; y está medido que un candidato recién materializado **no trae**
/// entorno: lo que se genera al resolver no se versiona.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;
import 'package:yaml/yaml.dart';

import 'ejecutor.dart';
import 'raices.dart';

class EntornoDart implements VerificationEnvironment {
  final EjecutorDeProceso ejecutor;

  /// Con qué se invoca la toolchain. **Inyectable para poder probar su
  /// ausencia** sin desinstalar nada, igual que el programa de `git` en el
  /// adapter de repositorio.
  final String programa;

  const EntornoDart({
    this.ejecutor = const EjecutorDelSistema(),
    this.programa = 'dart',
  });

  /// **`--offline` y `--enforce-lockfile`, las dos.** La primera impide que la
  /// derivación salga a la red a buscar algo que el candidato no fijó; la
  /// segunda, que reescriba el lockfile: el del candidato manda, y si no
  /// alcanza, el candidato se rechaza en vez de resolverse otra cosa.
  static const _resolver = ['pub', 'get', '--offline', '--enforce-lockfile'];

  /// Lo que la derivación genera, y que por eso el árbol no puede versionar.
  static const _generado = '.dart_tool';

  /// [presupuesto] es **por subproceso**, no por derivación entera: es lo que el
  /// ejecutor sabe cortar. Va dicho acá y no supuesto por quien llame.
  @override
  Future<ResultadoDeEntorno> derivar(
    String candidateRoot, {
    required List<String> archivos,
    required Duration presupuesto,
  }) async {
    final raiz = rutas.canonicalize(candidateRoot);
    final raices = raicesDeResolucion(raiz, archivos);

    // **Antes de invocar nada.** Si el árbol versiona lo que la derivación
    // genera, derivar lo destruiría: está medido que resolver borra el lockfile
    // y el mapa de paquetes de un miembro que pasa a resolverse desde la raíz.
    //
    // **Esto mira el disco, no el commit**, porque acá no hay git ni debe
    // haberlo. La consecuencia está declarada en el puerto: derivar dos veces
    // sobre el mismo candidato rechaza la segunda, y tiene razón según lo que
    // puede ver. Un candidato nuevo no tiene nada generado — está medido.
    for (final r in raices) {
      final generado = Directory(rutas.join(raiz, r, _generado));
      if (generado.existsSync()) {
        return CandidatoRechazado(
          causa: CausaDeRechazo.elArbolVersionaLoQueSeGenera,
          evidencia: QuotedText(
            '${_relativa(generado.path, raiz)} está en el árbol fijado, y '
            'derivar lo destruiría.',
            source: 'el candidato',
          ),
        );
      }
    }

    // La toolchain se **atestigua**: la identidad del contenido nombra el
    // lockfile commiteado, no los bytes que se ejecutan.
    final invocacionDeVersion = '$programa --version';
    final version = await ejecutor.correr(
      programa,
      const ['--version'],
      directorio: raiz,
      presupuesto: presupuesto,
    );
    if (version.terminacion != Termination.completa) {
      return _abortada(version, invocacionDeVersion);
    }
    final toolchain = IdentidadDeToolchain(
      version: QuotedText(_texto(version), source: invocacionDeVersion),
    );

    var paquetes = 0;
    for (final r in raices) {
      final dir = rutas.join(raiz, r);
      final invocacion = '$programa ${_resolver.join(" ")} · en $r';
      final resuelto = await ejecutor.correr(
        programa,
        _resolver,
        directorio: dir,
        presupuesto: presupuesto,
      );
      if (resuelto.terminacion != Termination.completa) {
        return _abortada(resuelto, invocacion);
      }
      if (resuelto.codigo != 0) {
        // **Dijo que no, y no inventamos por qué.** Está medido que el mismo
        // código de salida cubre un cache frío y un SDK desconocido, así que
        // distinguirlos exigiría leerle frases a la salida de error — el parser
        // frágil que este proyecto rechaza en todas partes. La evidencia va
        // literal, y quien lea la corrida ve lo que la herramienta dijo.
        return CandidatoRechazado(
          causa: CausaDeRechazo.pubRechazoLaResolucion,
          evidencia: QuotedText(_texto(resuelto), source: invocacion),
        );
      }
      final escapa = _dependenciaQueEscapa(dir, raiz);
      if (escapa != null) {
        return CandidatoRechazado(
          causa: CausaDeRechazo.dependenciaPathQueEscapa,
          evidencia: QuotedText(escapa, source: '$r/pubspec.lock'),
        );
      }
      paquetes += _paquetesDe(dir);
    }

    return EntornoDerivado(
      paquetes: paquetes,
      raices: raices.length,
      toolchain: toolchain,
    );
  }

  DerivacionAbortada _abortada(ResultadoDeProceso r, String invocacion) =>
      DerivacionAbortada(
        terminacion: r.terminacion,
        evidencia: QuotedText(_texto(r), source: invocacion),
      );

  /// Las dos corrientes, siempre. La versión de la toolchain sale por una u otra
  /// según la versión, y el resolvedor explica por la de error.
  ///
  /// **Nunca en blanco**: los tipos lo rechazan, y un proceso mudo también es un
  /// hecho que hay que poder citar.
  static String _texto(ResultadoDeProceso r) {
    final t = '${r.salidaEstandar}${r.salidaDeError}'.trim();
    return t.isEmpty ? '(sin salida; código ${r.codigo})' : t;
  }

  /// Una dependencia por ruta que resuelve fuera del candidato, o nulo.
  ///
  /// **Se lee del lockfile que el resolvedor acaba de validar**, no del mapa de
  /// paquetes: ese mapa no distingue una dependencia por ruta de una hospedada
  /// —las dos apuntan fuera del candidato, la hospedada al cache— ni de una del
  /// SDK. El lockfile sí las distingue, y es el archivo que
  /// `--enforce-lockfile` acaba de comprobar sin reescribir.
  static String? _dependenciaQueEscapa(String dir, String raiz) {
    final lock = File(rutas.join(dir, 'pubspec.lock'));
    if (!lock.existsSync()) return null;
    final doc = loadYaml(lock.readAsStringSync());
    final paquetes = doc is Map ? doc['packages'] : null;
    if (paquetes is! Map) return null;
    for (final e in paquetes.entries) {
      final p = e.value;
      if (p is! Map || p['source'] != 'path') continue;
      final desc = p['description'];
      if (desc is! Map) continue;
      final ruta = desc['path'];
      if (ruta is! String) continue;
      final absoluta = rutas.canonicalize(
        rutas.isAbsolute(ruta) ? ruta : rutas.join(dir, ruta),
      );
      if (!rutas.isWithin(raiz, absoluta) && !rutas.equals(raiz, absoluta)) {
        return '${e.key}: «$ruta» resuelve fuera del candidato, así que su '
            'contenido no quedó fijado.';
      }
    }
    return null;
  }

  /// Cuántas entradas tiene el mapa de paquetes resultante. Es el hecho contable
  /// de que la derivación produjo algo.
  static int _paquetesDe(String dir) {
    final f = File(rutas.join(dir, _generado, 'package_config.json'));
    if (!f.existsSync()) return 0;
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    return (json['packages'] as List).length;
  }

  static String _relativa(String absoluto, String raiz) =>
      rutas.relative(absoluto, from: raiz).replaceAll(r'\', '/');
}
