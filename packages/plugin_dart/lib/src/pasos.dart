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

/// Lo que el arnés sabe del alcance ANTES de creerle a la herramienta: qué
/// sujetos son utilizables, por qué no lo son los demás, y **cuántos archivos
/// hay que mirar**. Ese número es la mitad de una reconciliación; la otra la
/// pone la herramienta.
typedef Alcance = ({List<String> sanos, List<String> motivos, int archivos});

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

  /// El sufijo de los archivos que estas herramientas leen. Vive en la base
  /// porque los dos pasos necesitan contar el alcance por su cuenta.
  static const sufijoDeFuente = '.dart';

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

  /// Cuántos archivos de fuente hay bajo un sujeto, o el motivo por el que no
  /// se pudo saber.
  ///
  /// **Los componentes ocultos no se cuentan al recorrer un directorio**, y
  /// eso está medido: la herramienta salta todo lo que cuelga de una carpeta
  /// que empieza con punto. Un sujeto nombrado explícitamente SÍ se procesa
  /// aunque sea oculto, también medido, y por eso la regla se aplica a lo que
  /// hay debajo del sujeto y no al sujeto.
  ///
  /// Sin esta fidelidad la reconciliación sería siempre distinta de cero y
  /// todo terminaría no concluyente. Es un fallo ruidoso, no silencioso, pero
  /// igual inservible.
  ({int archivos, String? problema}) _mirar(String pedido) {
    final absoluto =
        rutas.isAbsolute(pedido) ? pedido : rutas.join(directorio, pedido);
    try {
      if (File(absoluto).existsSync()) {
        return absoluto.endsWith(sufijoDeFuente)
            ? (archivos: 1, problema: null)
            : (
                archivos: 0,
                problema: 'no es un archivo de fuente de este stack'
              );
      }
      final carpeta = Directory(absoluto);
      if (!carpeta.existsSync()) {
        return (archivos: 0, problema: 'no existe en el árbol');
      }
      final cuantos = carpeta
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith(sufijoDeFuente))
          .where((f) => !rutas
              .split(rutas.relative(f.path, from: absoluto))
              .any((parte) => parte.startsWith('.')))
          .length;
      return cuantos == 0
          ? (archivos: 0, problema: 'no contiene ningún archivo de fuente')
          : (archivos: cuantos, problema: null);
    } on FileSystemException catch (e) {
      // **No poder mirar es un dato, no una excepción que se escapa.** Un
      // directorio sin permisos hacía que `run` lanzara y el paso no
      // devolviera testigo NINGUNO, que rompe la primera cláusula del puerto.
      // Se atrapa esta familia y no `Object`: un error de programación tiene
      // que seguir subiendo.
      return (
        archivos: 0,
        problema: 'no se pudo mirar: ${e.osError?.message ?? e.message}',
      );
    }
  }

  /// El alcance separado en lo utilizable y lo que no, con la cuenta de
  /// archivos de lo utilizable.
  Alcance separar(List<String> pedidos) {
    final sanos = <String>[];
    final motivos = <String>[];
    var archivos = 0;
    for (final pedido in pedidos) {
      final r = _mirar(pedido);
      if (r.problema == null) {
        sanos.add(pedido);
        archivos += r.archivos;
      } else {
        motivos.add('$pedido: ${r.problema}');
      }
    }
    return (sanos: sanos, motivos: motivos, archivos: archivos);
  }

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    // **Se copia y se congela antes de nada.** La lista es del llamador, que
    // puede mutarla mientras el proceso está suspendido en el `await`: pasó, y
    // el testigo quedó nombrando una invocación sobre un alcance y declarando
    // cobertura sobre otro. Es el mismo invariante que `colecciones-inmutables`
    // exige en `core`, acá en el punto donde se construye la evidencia.
    final pedidos = List<String>.unmodifiable(subjects);

    VerificationOutcome conTestigo({
      required String invocacion,
      required List<String> cubierto,
      required List<String> omitido,
      required Termination terminacion,
      required int codigo,
      List<Diagnostic> diagnosticos = const [],
    }) =>
        VerificationOutcome(
          verifierId: id,
          diagnostics: diagnosticos,
          witness: Witness(
            invocation: invocacion,
            subjects: cubierto,
            omitted: omitido,
            termination: terminacion,
            exitCode: codigo,
            finishedAt: DateTime.now().toUtc(),
          ),
        );

    if (pedidos.isEmpty) {
      // **La invocación queda VACÍA porque no hubo ninguna.** Nombraba el
      // comando que se habría corrido, y eso es peor que no nombrar nada: la
      // cuarta cláusula del puerto pide que el testigo nombre la invocación
      // que de verdad se hizo, y acá no se hizo ninguna.
      return conTestigo(
        invocacion: '',
        cubierto: const [],
        omitido: const [
          'No se le dio ningún sujeto, así que no se invocó ninguna herramienta.'
        ],
        terminacion: Termination.interrumpida,
        codigo: -1,
      );
    }

    // El programa y los argumentos se calculan UNA vez y se reusan. Se
    // calculaban dos veces —una para el texto del testigo y otra para la
    // invocación real— y nada garantizaba que dieran lo mismo.
    final prog = programa;
    final args = List<String>.unmodifiable(argumentos(pedidos));
    final invocacion = [prog, ...args].join(' ');

    final r = await ejecutor.correr(prog, args,
        directorio: directorio, presupuesto: presupuesto);

    if (r.terminacion != Termination.completa) {
      return conTestigo(
        invocacion: invocacion,
        cubierto: const [],
        omitido: [
          'La herramienta no llegó a producir un resultado: ${r.salidaDeError}',
          if (r.terminacion == Termination.tiempoAgotado)
            'Los procesos descendientes no se rastrean: si la herramienta dejó '
                'hijos, pueden seguir vivos.',
        ],
        terminacion: r.terminacion,
        codigo: r.codigo,
      );
    }

    // **Desde acá la terminación es `completa` y no se toca más.** Se
    // reescribía a `interrumpida` cuando el código era desconocido o cuando la
    // salida no se podía leer, y eso es falso: la herramienta corrió y produjo
    // un resultado, que es la definición literal de `completa`. Que nosotros
    // no sepamos interpretarlo es nuestro problema, y va en `omitted`. El
    // veredicto no concluyente sale igual, porque no hay sujetos cubiertos.
    if (!codigosDeCorrida.contains(r.codigo)) {
      return conTestigo(
        invocacion: invocacion,
        cubierto: const [],
        omitido: [
          'Código de salida ${r.codigo}, que no está entre los que significan '
              'que la herramienta corrió (${codigosDeCorrida.join(", ")}). '
              'Suponer que es benigno sería adivinar.',
        ],
        terminacion: Termination.completa,
        codigo: r.codigo,
      );
    }

    final salida = QuotedText(ensamblar(r), source: invocacion);

    final List<Diagnostic> diagnosticos;
    try {
      diagnosticos = normalizador.normalize(salida);
    } on UnreadableToolOutput catch (e) {
      // El resultado NO es un diagnóstico contra el código del usuario: es que
      // el arnés no sabe leer lo que tiene delante.
      return conTestigo(
        invocacion: invocacion,
        cubierto: const [],
        omitido: ['No se pudo interpretar la salida: ${e.reason}'],
        terminacion: Termination.completa,
        codigo: r.codigo,
      );
    }

    final c = cobertura(pedidos, salida);
    return conTestigo(
      invocacion: invocacion,
      cubierto: c.cubierto,
      omitido: c.omitido,
      terminacion: Termination.completa,
      codigo: r.codigo,
      diagnosticos: diagnosticos,
    );
  }
}

/// `FormatCheck` — comprueba el formato sin escribir nada.
///
/// **Es el paso que SÍ puede detectar su propia ceguera.** La herramienta
/// informa cuántos archivos miró, y está medido que con un directorio que no
/// existe sale con código 0 y una queja por la corriente de error que nadie
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

  /// `0` corrió; `65` corrió y encontró código que no parsea. **No se usa
  /// `--set-exit-if-changed`**: el veredicto sale de los diagnósticos, no del
  /// código de salida, que es lo que dice el propio `Witness.exitCode`.
  @override
  Set<int> get codigosDeCorrida => const {0, 65};

  @override
  DiagnosticNormalizer get normalizador => const NormalizadorDeFormato();

  /// El resumen y los archivos cambiados salen por la corriente estándar; los
  /// errores de parseo, por la de error. El normalizador cuenta con este orden.
  @override
  String ensamblar(ResultadoDeProceso r) =>
      '${r.salidaEstandar}\n${r.salidaDeError}';

  @override
  Cobertura cobertura(List<String> pedidos, QuotedText salida) {
    const norma = NormalizadorDeFormato();
    final (:sanos, :motivos, :archivos) = separar(pedidos);
    final mirados = norma.archivosMirados(salida);
    final sinParsear = norma.archivosQueNoParsean(salida).length;

    if (mirados == 0) {
      return (
        cubierto: const <String>[],
        omitido: [
          ...motivos,
          'La herramienta informó que no miró NINGÚN archivo. Su código de '
              'salida es 0 igual, así que esto no se puede leer del código: '
              'sale del resumen.',
        ],
      );
    }

    // **La cuenta se reconcilia, no se toma como suficiente.** Que la
    // herramienta haya mirado ALGO no dice que haya mirado lo que se le pidió:
    // con dos sujetos de un archivo cada uno y un resumen que decía «1 file»,
    // el testigo certificaba los dos. Los archivos que no parsean no entran en
    // la cuenta de formateados —la herramienta los salta— así que se suman de
    // vuelta antes de comparar.
    //
    // Y no se puede atribuir el faltante a ningún sujeto: el resumen es un
    // total, no una lista. Si no cierra, no se certifica ninguno.
    //
    // Es la misma reconciliación que el normalizador hace un nivel más abajo
    // entre las líneas «Changed» y el «(N changed)» del resumen. Estaba
    // aplicada a los diagnósticos y no a la cobertura, que es donde decide el
    // verde.
    if (mirados + sinParsear != archivos) {
      return (
        cubierto: const <String>[],
        omitido: [
          ...motivos,
          'El alcance tiene $archivos archivo(s) de fuente y la herramienta '
              'informó $mirados formateado(s) más $sinParsear que no '
              'parsean. No cierra, y el resumen es un total: no hay forma de '
              'saber a qué sujeto le faltó, así que no se certifica ninguno.',
        ],
      );
    }

    // Los archivos que no parsean quedaron sin formatear. Que la herramienta
    // los salte está bien; que no se diga, no.
    return (
      cubierto: sanos,
      omitido: [
        ...motivos,
        if (sinParsear > 0)
          '$sinParsear archivo(s) no parsean y quedaron sin formatear. Están '
              'reportados como diagnóstico, no omitidos en silencio.',
      ],
    );
  }
}

/// `StaticAnalysis` — el analizador estático.
///
/// **Este paso NO puede detectar su propia ceguera, y lo declara.** Está
/// medido: sobre un directorio vacío la herramienta devuelve exactamente lo
/// mismo que sobre un directorio lleno de código limpio —código 0 y la lista
/// de hallazgos vacía—, así que de su salida no se puede saber si leyó algo.
///
/// Se compensa por dos lados, y los dos quedan escritos en el testigo: una
/// ruta que no existe le hace devolver un código que no está en la lista
/// blanca, y los archivos del alcance los cuenta el arnés, sujeto por sujeto.
/// Lo que sigue sin cubrirse —que haya leído todos los que contamos— es
/// residuo declarado, no un hueco silencioso.
final class PasoDeAnalisis extends PasoDeCascada {
  const PasoDeAnalisis({
    required super.ejecutor,
    required super.directorio,
    super.presupuesto,
  });

  @override
  String get id => 'StaticAnalysis';

  @override
  String get programa => 'dart';

  /// El formato se eligió por su caso vacío: el otro escribe cero bytes cuando
  /// no encuentra nada, y cero bytes es lo mismo que deja una herramienta que
  /// no corrió. Ver [NormalizadorDeAnalisis].
  @override
  List<String> argumentos(List<String> sujetos) =>
      ['analyze', '--format=json', ...sujetos];

  /// `0` sin hallazgos —incluidos los informativos, está medido—; `1`, `2` y
  /// `3` con hallazgos de distinta gravedad. Una ruta inexistente da `64`, que
  /// deliberadamente NO está: es el único caso ciego que la herramienta sí
  /// delata.
  @override
  Set<int> get codigosDeCorrida => const {0, 1, 2, 3};

  @override
  DiagnosticNormalizer get normalizador => const NormalizadorDeAnalisis();

  @override
  String ensamblar(ResultadoDeProceso r) => r.salidaEstandar;

  @override
  Cobertura cobertura(List<String> pedidos, QuotedText salida) {
    final (:sanos, :motivos, :archivos) = separar(pedidos);
    // **No hay nada que reconciliar acá, y ese es el punto.** El formateador
    // informa cuántos archivos miró y por eso su cobertura se puede comprobar;
    // este no informa nada, así que la única cuenta es la del arnés y queda
    // dicha en el testigo con su número.
    final residuo =
        'La herramienta no informa qué archivos leyó: sobre un alcance vacío '
        'devuelve lo mismo que sobre uno limpio. La cobertura se comprobó '
        'contando los $archivos archivo(s) del alcance, no leyendo su reporte. '
        'Que los haya leído TODOS no lo verifica este paso.';
    return (cubierto: sanos, omitido: [...motivos, residuo]);
  }
}
