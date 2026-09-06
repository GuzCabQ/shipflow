/// Los dos primeros pasos de la cascada, con su testigo.
///
/// **Toda la disciplina de atestación vive en [PasoDeCascada] y en ningún otro
/// lado.** Un paso nuevo no puede olvidarse de construir su testigo porque no
/// es él quien lo construye: aporta qué invocar y sobre qué puede atestiguar,
/// y el veredicto sale de ahí. Que cada paso armara su propio testigo sería
/// pedirle a cada uno que se acuerde del invariante, y eso ya falló.
library;

import 'package:core/core.dart';

import 'ejecutor.dart';
import 'normalizadores.dart';

/// Sobre qué pudo atestiguar un paso, y qué quedó afuera.
typedef Cobertura = ({List<String> cubierto, List<Omission> omitido});

/// Lo que el arnés sabe del alcance ANTES de creerle a la herramienta: qué
/// sujetos son utilizables y **cuántos archivos hay que mirar**. Ese número
/// es la mitad de una reconciliación; la otra la pone la herramienta.
///
/// **No lleva los motivos de lo que no es utilizable.** Los llevaba, como
/// [Omission] con su sujeto, para que `run` los adjuntara al testigo — pero
/// eso era saldar la obligación de ese sujeto sin haberlo verificado, que es
/// justo el falso verde que la tarea 8b cierra. Un sujeto no utilizable
/// aborta la corrida antes de llegar acá: por el momento en que se
/// construye este record, todo sujeto pedido YA es sano, así que un campo de
/// motivos solo podría llegar vacío.
typedef Alcance = ({
  List<String> sanos,
  int archivos,
});

/// Un paso de la cascada que invoca una herramienta y normaliza su salida.
abstract base class PasoDeCascada implements Verifier {
  final EjecutorDeProceso ejecutor;
  final String directorio;
  final Duration presupuesto;

  /// **El paso no mira el alcance y ya no tiene con qué.** ADR-011 corolario
  /// 4 dice que ningún verificador juzga su propia incumbencia, y mientras el
  /// paso guardó un `ScopeObserver` eso dependía de que nadie lo usara. Lo
  /// usaba: una corrida de dos pasos leía el árbol tres veces. La observación
  /// llega por parámetro, que es la única forma de que no haya una segunda.
  PasoDeCascada({
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
  /// Recibe **el alcance ya separado**, no los pedidos.
  ///
  /// Antes lo volvía a separar por su cuenta, después del `await`: el mismo
  /// testigo podía afirmar «cero elementos propios» y «cubrí lib» a la vez,
  /// porque las dos afirmaciones salían de dos fotografías distintas del
  /// árbol. Lo encontró un review con un ejecutor que creaba un archivo
  /// durante la espera. Ahora hay una foto y viaja.
  Cobertura cobertura(Alcance alcance, QuotedText salida);

  @override
  Future<VerificationOutcome> run(VerificationScope pedido) async {
    // **El alcance lo trae quien compone, ya resuelto, y es el mismo para
    // toda la corrida.** De acá salen los sujetos a invocar y el conteo con
    // el que se reconcilia lo que la herramienta dice haber mirado. Cuando el
    // paso miraba el árbol por su cuenta, cada una de esas cosas podía salir
    // de una lectura distinta y el testigo afirmaba dos cosas incompatibles.
    //
    // **Y llega estrecho: acá adentro no existe un sujeto ajeno.** Una
    // versión anterior recibía la observación entera, y con ella la
    // posibilidad de certificar lo que no era nuestro escribiendo `requested`
    // donde iba `usable()`. `VerificationScope` es inmodificable y no vacío
    // por construcción, así que tampoco hace falta congelar ni comprobar nada
    // de eso acá.
    final alcance = (sanos: pedido.subjects, archivos: pedido.files);

    // **Acá vivía la precondición del alcance vacío, y se mudó al tipo.**
    // Era un `throw` adentro de `run` que decía de sí mismo «se comprueba
    // antes de invocar nada». Se comprobaba después de entrar, que no es lo
    // mismo: `VerificationScope` no se puede construir vacío, así que ahora
    // la frase es literal.

    // **Acá vivía una guardia de divergencia, y se fue con su causa.**
    // Comparaba la lectura del paso contra la que la cascada había vetado, y
    // era lo que hacía tolerable la doble lectura. No la hacía tolerable:
    // comparaba NOMBRES, así que un árbol que cambiaba de tamaño con el
    // sujeto todavía utilizable no divergía, y la corrida salía verde
    // reportando un alcance que los verificadores no habían visto. Con una
    // sola lectura no hay dos fotos que reconciliar, que es más barato y más
    // cierto que reconciliarlas bien.

    // El programa y los argumentos se calculan UNA vez y se reusan. Se
    // calculaban dos veces —una para el texto del testigo y otra para la
    // invocación real— y nada garantizaba que dieran lo mismo.
    //
    // **Se invoca sobre lo utilizable, y solo sobre eso.** Lo que la
    // observación no dio como del stack no se le pasa a la herramienta: no es
    // un descarte silencioso, es la partición que el observador ya decidió y
    // que este paso no vuelve a juzgar.
    final prog = programa;
    final args = List<String>.unmodifiable(argumentos(alcance.sanos));
    final invocacion = [prog, ...args].join(' ');

    final r = await ejecutor.correr(prog, args,
        directorio: directorio, presupuesto: presupuesto);

    if (r.terminacion != Termination.completa) {
      // **No es un testigo: es un intento.** La herramienta no llegó a
      // producir un resultado, y representar eso con el mismo tipo que un
      // `Witness` es exactamente el hecho falso que ADR-011 vino a impedir.
      return Aborted(
          attempt: Attempt(
        invocation: invocacion,
        subjects: alcance.sanos,
        termination: r.terminacion,
        exitCode: r.codigo,
        note: [
          'La herramienta no llegó a producir un resultado: ${r.salidaDeError}',
          if (r.terminacion == Termination.tiempoAgotado)
            'Los procesos descendientes no se rastrean: si la herramienta dejó '
                'hijos, pueden seguir vivos.',
        ].join(' '),
        finishedAt: DateTime.now().toUtc(),
      ));
    }

    // **Desde acá la terminación es `completa` y no se reinterpreta.** Se
    // reescribía a `interrumpida` cuando el código era desconocido o cuando la
    // salida no se podía leer, y eso es falso: la herramienta corrió y produjo
    // un resultado, que es la definición literal de `completa`. Que nosotros
    // no sepamos interpretarlo es nuestro problema, y va en `omitted` de un
    // `Executed` no concluyente — nunca falsea el desenlace.
    if (!codigosDeCorrida.contains(r.codigo)) {
      return Executed(
        witness: Witness(
          invocation: invocacion,
          subjects: const [],
          exitCode: r.codigo,
          finishedAt: DateTime.now().toUtc(),
          omitted: [
            Omission(
                reason: 'Código de salida ${r.codigo}, que no está entre los '
                    'que significan que la herramienta corrió '
                    '(${codigosDeCorrida.join(", ")}). Suponer que es '
                    'benigno sería adivinar.'),
          ],
        ),
        diagnostics: const [],
      );
    }

    final salida = QuotedText(ensamblar(r), source: invocacion);

    final List<Diagnostic> diagnosticos;
    try {
      diagnosticos = normalizador.normalize(salida);
    } on UnreadableToolOutput catch (e) {
      // El resultado NO es un diagnóstico contra el código del usuario: es que
      // el arnés no sabe leer lo que tiene delante.
      return Executed(
        witness: Witness(
          invocation: invocacion,
          subjects: const [],
          exitCode: r.codigo,
          finishedAt: DateTime.now().toUtc(),
          omitted: [
            Omission(reason: 'No se pudo interpretar la salida: ${e.reason}'),
          ],
        ),
        diagnostics: const [],
      );
    }

    final c = cobertura(alcance, salida);
    return Executed(
      witness: Witness(
        invocation: invocacion,
        subjects: c.cubierto,
        exitCode: r.codigo,
        finishedAt: DateTime.now().toUtc(),
        omitted: c.omitido,
      ),
      diagnostics: diagnosticos,
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
  PasoDeFormato({
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
  Cobertura cobertura(Alcance alcance, QuotedText salida) {
    const norma = NormalizadorDeFormato();
    final (:sanos, :archivos) = alcance;
    final mirados = norma.archivosMirados(salida);
    final sinParsear = norma.archivosQueNoParsean(salida).length;

    if (mirados == 0) {
      return (
        cubierto: const <String>[],
        omitido: [
          Omission(
              reason: 'La herramienta informó que no miró NINGÚN archivo. Su '
                  'código de salida es 0 igual, así que esto no se puede '
                  'leer del código: sale del resumen.'),
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
    // total, no una lista. Si no cierra, no se certifica ninguno, y la
    // omisión que lo dice tampoco lleva sujeto.
    //
    // Es la misma reconciliación que el normalizador hace un nivel más abajo
    // entre las líneas «Changed» y el «(N changed)» del resumen. Estaba
    // aplicada a los diagnósticos y no a la cobertura, que es donde decide el
    // verde.
    if (mirados + sinParsear != archivos) {
      return (
        cubierto: const <String>[],
        omitido: [
          Omission(
              reason: 'El alcance tiene $archivos archivo(s) de fuente y la '
                  'herramienta informó $mirados formateado(s) más '
                  '$sinParsear que no parsean. No cierra, y el resumen es '
                  'un total: no hay forma de saber a qué sujeto le faltó, '
                  'así que no se certifica ninguno.'),
        ],
      );
    }

    // Los archivos que no parsean quedaron sin formatear. Que la herramienta
    // los salte está bien; que no se diga, no. Tampoco se puede atribuir a un
    // sujeto: el resumen no dice cuáles fueron.
    return (
      cubierto: sanos,
      omitido: [
        if (sinParsear > 0)
          Omission(
              reason: '$sinParsear archivo(s) no parsean y quedaron sin '
                  'formatear. Están reportados como diagnóstico, no '
                  'omitidos en silencio.'),
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
  PasoDeAnalisis({
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
  Cobertura cobertura(Alcance alcance, QuotedText salida) {
    final (:sanos, :archivos) = alcance;
    // **No hay nada que reconciliar acá, y ese es el punto.** El formateador
    // informa cuántos archivos miró y por eso su cobertura se puede comprobar;
    // este no informa nada, así que la única cuenta es la del arnés y queda
    // dicha en el testigo con su número. Tampoco se puede atribuir a un
    // sujeto: es un residuo general del paso, no de ningún par paso-sujeto.
    final residuo = Omission(
        reason: 'La herramienta no informa qué archivos leyó: sobre un '
            'alcance vacío devuelve lo mismo que sobre uno limpio. La '
            'cobertura se comprobó contando los $archivos archivo(s) del '
            'alcance, no leyendo su reporte. Que los haya leído TODOS no lo '
            'verifica este paso.');
    return (cubierto: sanos, omitido: [residuo]);
  }
}
