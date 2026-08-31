/// Los dos primeros pasos de la cascada, con su testigo.
///
/// **Toda la disciplina de atestación vive en [PasoDeCascada] y en ningún otro
/// lado.** Un paso nuevo no puede olvidarse de construir su testigo porque no
/// es él quien lo construye: aporta qué invocar y sobre qué puede atestiguar,
/// y el veredicto sale de ahí. Que cada paso armara su propio testigo sería
/// pedirle a cada uno que se acuerde del invariante, y eso ya falló.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;

import 'ejecutor.dart';
import 'normalizadores.dart';

/// Sobre qué pudo atestiguar un paso, y qué quedó afuera.
typedef Cobertura = ({List<String> cubierto, List<String> omitido});

/// Un paso de la cascada que invoca una herramienta y normaliza su salida.
abstract base class PasoDeCascada implements Verifier {
  final EjecutorDeProceso ejecutor;
  final String directorio;
  final Duration presupuesto;

  const PasoDeCascada({
    required this.ejecutor,
    required this.directorio,
    this.presupuesto = const Duration(minutes: 5),
  });

  /// El programa y sus argumentos para un alcance dado.
  String get programa;
  List<String> argumentos(List<String> sujetos);

  /// **Los códigos de salida que significan «corrí».** Es una lista blanca a
  /// propósito: un código que no está acá deja el resultado no concluyente, en
  /// vez de leerse como el más benigno. Una herramienta que empieza a devolver
  /// un código nuevo tiene que hacernos parar, no pasar.
  Set<int> get codigosDeCorrida;

  DiagnosticNormalizer get normalizador;

  /// Cómo se arma el texto que lee el normalizador a partir de las dos
  /// corrientes. No es igual para todos: hay herramientas que escriben todo
  /// por la estándar y otras que reparten.
  String ensamblar(ResultadoDeProceso resultado);

  /// **Sobre qué puede este paso atestiguar que corrió, y qué quedó afuera.**
  ///
  /// Devolver `cubierto` vacío es la forma de decir «no concluyente»: el
  /// testigo deja de atestiguar y el veredicto se deriva solo. No hay que
  /// acordarse de ponerlo en rojo.
  Cobertura cobertura(List<String> pedidos, QuotedText salida);

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    final invocacion = [programa, ...argumentos(subjects)].join(' ');

    VerificationOutcome sinCobertura(
            Termination t, int codigo, String porQue) =>
        VerificationOutcome(
          verifierId: id,
          diagnostics: const [],
          witness: Witness(
            invocation: invocacion,
            subjects: const [],
            omitted: [porQue],
            termination: t,
            exitCode: codigo,
            finishedAt: DateTime.now().toUtc(),
          ),
        );

    if (subjects.isEmpty) {
      return sinCobertura(Termination.interrumpida, -1,
          'No se le dio ningun sujeto, asi que no se invoco nada.');
    }

    final r = await ejecutor.correr(programa, argumentos(subjects),
        directorio: directorio, presupuesto: presupuesto);

    if (r.terminacion != Termination.completa) {
      return sinCobertura(r.terminacion, r.codigo,
          'La herramienta no llego a producir un resultado: ${r.salidaDeError}');
    }

    if (!codigosDeCorrida.contains(r.codigo)) {
      return sinCobertura(
          Termination.interrumpida,
          r.codigo,
          'Codigo de salida ${r.codigo}, que no esta entre los que significan '
          'que la herramienta corrio (${codigosDeCorrida.join(", ")}). '
          'Suponer que es benigno seria adivinar.');
    }

    final salida = QuotedText(ensamblar(r), source: invocacion);

    final List<Diagnostic> diagnosticos;
    try {
      diagnosticos = normalizador.normalize(salida);
    } on UnreadableToolOutput catch (e) {
      // El resultado NO es un diagnostico contra el codigo del usuario: es que
      // el arnes no sabe leer lo que tiene delante. Esa es exactamente la
      // categoria que ADR-011 creo, y el motivo viaja en el testigo.
      return sinCobertura(Termination.interrumpida, r.codigo,
          'No se pudo interpretar la salida: ${e.reason}');
    }

    final c = cobertura(subjects, salida);
    return VerificationOutcome(
      verifierId: id,
      diagnostics: diagnosticos,
      witness: Witness(
        invocation: invocacion,
        subjects: c.cubierto,
        omitted: c.omitido,
        termination: Termination.completa,
        exitCode: r.codigo,
        finishedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

/// `FormatCheck` — comprueba el formato sin escribir nada.
///
/// **Es el paso que SI puede detectar su propia ceguera.** La herramienta
/// informa cuantos archivos miro, y esta medido que con un directorio que no
/// existe sale con codigo 0 y una queja por la corriente de error que nadie
/// lee. Cero archivos mirados deja el testigo sin sujetos, y sin sujetos no
/// hay verde.
final class PasoDeFormato extends PasoDeCascada {
  const PasoDeFormato({
    required super.ejecutor,
    required super.directorio,
    super.presupuesto,
  });

  @override
  String get id => 'FormatCheck';

  @override
  String get programa => 'dart';

  @override
  List<String> argumentos(List<String> sujetos) =>
      ['format', '--output=none', ...sujetos];

  /// `0` corrio; `65` corrio y encontro codigo que no parsea. **No se usa
  /// `--set-exit-if-changed`**: el veredicto sale de los diagnosticos, no del
  /// codigo de salida, que es lo que dice el propio `Witness.exitCode`.
  @override
  Set<int> get codigosDeCorrida => const {0, 65};

  @override
  DiagnosticNormalizer get normalizador => const NormalizadorDeFormato();

  /// El resumen y los archivos cambiados salen por la corriente estandar; los
  /// errores de parseo, por la de error. El normalizador cuenta con este orden.
  @override
  String ensamblar(ResultadoDeProceso r) =>
      '${r.salidaEstandar}\n${r.salidaDeError}';

  @override
  Cobertura cobertura(List<String> pedidos, QuotedText salida) {
    final mirados = const NormalizadorDeFormato().archivosMirados(salida);
    if (mirados == 0) {
      return (
        cubierto: const <String>[],
        omitido: [
          'La herramienta informo que no miro NINGUN archivo, con el alcance '
              '${pedidos.join(", ")}. Su codigo de salida es 0 igual, asi que '
              'esto no se puede leer del codigo: sale del resumen.',
        ],
      );
    }
    // Los archivos que no parsean no entran en la cuenta de formateados: la
    // herramienta los salta. Que los salte esta bien; que no se diga, no.
    final noParsearon = salida.content.contains(
            'Could not format because the source could not be parsed:')
        ? [
            'Hubo archivos que no parsean y quedaron sin formatear. Estan '
                'reportados como diagnostico, no omitidos en silencio.'
          ]
        : <String>[];
    return (cubierto: pedidos, omitido: noParsearon);
  }
}

/// `StaticAnalysis` — el analizador estatico.
///
/// **Este paso NO puede detectar su propia ceguera, y lo declara.** Esta
/// medido: sobre un directorio vacio la herramienta devuelve exactamente lo
/// mismo que sobre un directorio lleno de codigo limpio —codigo 0 y la lista
/// de hallazgos vacia—, asi que de su salida no se puede saber si leyo algo.
///
/// Se compensa por dos lados, y los dos quedan escritos en el testigo:
/// una ruta que no existe le hace devolver un codigo que no esta en la lista
/// blanca, y la cantidad de archivos del alcance la cuenta el arnes en vez de
/// pedirsela a la herramienta. Lo que sigue sin cubrirse —que haya leido todos
/// los que contamos— es residuo declarado, no un hueco silencioso.
final class PasoDeAnalisis extends PasoDeCascada {
  const PasoDeAnalisis({
    required super.ejecutor,
    required super.directorio,
    super.presupuesto,
  });

  static const _sufijoDeFuente = '.dart';

  @override
  String get id => 'StaticAnalysis';

  @override
  String get programa => 'dart';

  /// El formato se eligio por su caso vacio: el otro escribe cero bytes cuando
  /// no encuentra nada, y cero bytes es lo mismo que deja una herramienta que
  /// no corrio. Ver [NormalizadorDeAnalisis].
  @override
  List<String> argumentos(List<String> sujetos) =>
      ['analyze', '--format=json', ...sujetos];

  /// `0` sin hallazgos —incluidos los informativos, esta medido—; `1`, `2` y
  /// `3` con hallazgos de distinta gravedad. Una ruta inexistente da `64`, que
  /// deliberadamente NO esta: es el unico caso ciego que la herramienta si
  /// delata.
  @override
  Set<int> get codigosDeCorrida => const {0, 1, 2, 3};

  @override
  DiagnosticNormalizer get normalizador => const NormalizadorDeAnalisis();

  @override
  String ensamblar(ResultadoDeProceso r) => r.salidaEstandar;

  @override
  Cobertura cobertura(List<String> pedidos, QuotedText salida) {
    final cuenta = _archivosDeFuente(pedidos);
    final residuo =
        'La herramienta no informa que archivos leyo: sobre un alcance vacio '
        'devuelve lo mismo que sobre uno limpio. La cobertura se comprobo '
        'contando los archivos del alcance ($cuenta), no leyendo su reporte. '
        'Que los haya leido TODOS no lo verifica este paso.';
    if (cuenta == 0) {
      return (
        cubierto: const <String>[],
        omitido: [
          'No hay ningun archivo de fuente bajo ${pedidos.join(", ")}, asi que '
              'no hubo nada que analizar. $residuo',
        ],
      );
    }
    return (cubierto: pedidos, omitido: [residuo]);
  }

  /// Cuenta los archivos de fuente del alcance. **Lo hace el arnes porque la
  /// herramienta no lo dice**, y no al reves.
  int _archivosDeFuente(List<String> pedidos) {
    var n = 0;
    for (final pedido in pedidos) {
      final absoluto =
          rutas.isAbsolute(pedido) ? pedido : rutas.join(directorio, pedido);
      final archivo = File(absoluto);
      if (archivo.existsSync()) {
        if (absoluto.endsWith(_sufijoDeFuente)) n++;
        continue;
      }
      final carpeta = Directory(absoluto);
      if (!carpeta.existsSync()) continue;
      n += carpeta
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith(_sufijoDeFuente))
          .length;
    }
    return n;
  }
}
