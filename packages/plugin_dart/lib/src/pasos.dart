/// Los dos primeros pasos de la cascada, con su testigo.
///
/// **Toda la disciplina de atestación vive en [PasoDeCascada] y en ningún otro
/// lado.** Un paso nuevo no puede olvidarse de construir su testigo porque no
/// es él quien lo construye: aporta qué invocar y sobre qué puede atestiguar,
/// y el veredicto sale de ahí. Que cada paso armara su propio testigo sería
/// pedirle a cada uno que se acuerde del invariante, y eso ya falló.
library;

import 'package:core/core.dart';

import 'alcance.dart';
import 'ejecutor.dart';
import 'normalizadores.dart';

/// Sobre qué pudo atestiguar un paso, y qué quedó afuera.
typedef Cobertura = ({List<String> cubierto, List<Omission> omitido});

/// Lo que el arnés sabe del alcance ANTES de creerle a la herramienta: qué
/// sujetos son utilizables, por qué no lo son los demás —ya como [Omission]
/// con su sujeto, porque eso salda la obligación de ese par paso-sujeto— y
/// **cuántos archivos hay que mirar**. Ese número es la mitad de una
/// reconciliación; la otra la pone la herramienta.
typedef Alcance = ({
  List<String> sanos,
  List<Omission> motivos,
  int archivos,
});

/// Un paso de la cascada que invoca una herramienta y normaliza su salida.
abstract base class PasoDeCascada implements Verifier {
  final EjecutorDeProceso ejecutor;
  final String directorio;
  final Duration presupuesto;

  /// Quién mira el alcance. **No lo mira el paso**: ADR-011 corolario 4.
  final ScopeObserver observador;

  PasoDeCascada({
    required this.ejecutor,
    required this.directorio,
    ScopeObserver? observador,
    this.presupuesto = const Duration(minutes: 5),
  }) : observador =
            observador ?? ObservadorDeAlcanceDart(directorio: directorio);

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
  Future<VerificationOutcome> run(List<String> subjects) async {
    // **Se copia y se congela antes de nada.** La lista es del llamador, que
    // puede mutarla mientras el proceso está suspendido en el `await`: pasó, y
    // el testigo quedó nombrando una invocación sobre un alcance y declarando
    // cobertura sobre otro. Es el mismo invariante que `colecciones-inmutables`
    // exige en `core`, acá en el punto donde se construye la evidencia.
    final pedidos = List<String>.unmodifiable(subjects);

    // **Una sola foto del árbol, y viaja.** De acá salen la partición, el
    // conteo del alcance y la reconciliación: si cada una volviera a mirar,
    // podrían discrepar y el testigo afirmaría dos cosas incompatibles.
    final observacion = await observador.observe(pedidos);

    // **Las omisiones se arman en el orden en que se PIDIERON, no en el orden
    // en que el observador las clasificó.** Recorrer `observed` y
    // `unobserved` como dos bloques separados da el mismo contenido, pero en
    // otro orden apenas una misma corrida mezcla un sujeto ajeno con uno
    // inobservable. Por eso se arma un mapa y se recorre `requested`.
    //
    // Cada omisión nombra su sujeto: es lo que salda la obligación de ese
    // par paso-sujeto, y por eso viene del observador y no se resume a texto.
    final omisionPorSujeto = <String, Omission>{
      for (final o in observacion.observed)
        if (!o.ofStack) o.subject: Omission(subject: o.subject, reason: o.reason!),
      for (final u in observacion.unobserved)
        u.subject: Omission(subject: u.subject, reason: u.cause),
    };
    final alcance = (
      sanos: observacion.usable(),
      motivos: <Omission>[
        for (final s in observacion.requested)
          if (omisionPorSujeto[s] case final omision?) omision,
      ],
      archivos: observacion.observed
          .where((o) => o.ofStack)
          .fold(0, (n, o) => n + o.files),
    );

    if (alcance.sanos.isEmpty) {
      // **No hay nada que invocar, y esto NO es un desenlace: es precondición
      // violada.** Invocar la herramienta sin rutas la haría mirar el
      // directorio entero, que es lo contrario de lo que el alcance dice. Y
      // fabricar un testigo sería declarar una ejecución que no ocurrió. Quien
      // compone la corrida —no este paso— decide qué significa un alcance
      // así: si es un salto legítimo o si el alcance esperado no se cumplió.
      throw ArgumentError.value(
          subjects,
          'subjects',
          'No hay ningún sujeto utilizable. Invocar la herramienta sin rutas '
              'la haría mirar el directorio entero, y fabricar un testigo '
              'sería declarar una ejecución que no ocurrió. Quien compone la '
              'corrida decide qué significa un alcance así');
    }

    // El programa y los argumentos se calculan UNA vez y se reusan. Se
    // calculaban dos veces —una para el texto del testigo y otra para la
    // invocación real— y nada garantizaba que dieran lo mismo.
    // **La herramienta recibe SOLO los sujetos utilizables.**
    //
    // Recibía `pedidos` entero, así que un sujeto ya descartado llegaba
    // igual: `verify README.md` le daba el markdown a la herramienta del
    // stack, que intentaba parsearlo y devolvía cinco diagnósticos sobre un
    // archivo que no es de su incumbencia. Lo cobró un review, y afecta a
    // cualquier cambio normal que mezcle código y documentación.
    //
    // Lo descartado no desaparece: sigue en `omitted` con su motivo, que es
    // donde el corolario 5 de ADR-011 pide que esté.
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
            ...alcance.motivos,
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
            ...alcance.motivos,
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
    super.observador,
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
    final (:sanos, :motivos, :archivos) = alcance;
    final mirados = norma.archivosMirados(salida);
    final sinParsear = norma.archivosQueNoParsean(salida).length;

    if (mirados == 0) {
      return (
        cubierto: const <String>[],
        omitido: [
          ...motivos,
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
          ...motivos,
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
        ...motivos,
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
    super.observador,
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
    final (:sanos, :motivos, :archivos) = alcance;
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
    return (cubierto: sanos, omitido: [...motivos, residuo]);
  }
}
