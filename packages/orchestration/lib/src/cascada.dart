/// La cascada: un registro ordenado de pasos, y lo que resulta de correrlos.
///
/// **No sabe qué pasos existen.** Solo que son [Verifier]. Quién los compone es
/// el composition root, y una regla de arquitectura lo hace cumplir: este
/// paquete no puede ver ningún plugin. Esa ignorancia es la que permite que
/// cambiar de stack no toque la orquestación.
library;

import 'package:core/core.dart';

/// Se lanza cuando un registro de pasos no se puede usar como registro.
class CascadaNoRegistrable implements Exception {
  final String reason;
  const CascadaNoRegistrable(this.reason);

  @override
  String toString() => 'CascadaNoRegistrable: $reason';
}

/// Cómo terminó una corrida entera. **No es [Verdict]**, y la diferencia es
/// el punto: un veredicto es de un paso, y una corrida puede terminar por
/// cosas que no son veredictos de nadie.
///
/// Faltan estados que el producto va a necesitar —una detención por
/// presupuesto agotado (ADR-014)— y **no se declaran todavía**: no hay
/// presupuestos, y un estado que nada produce es una promesa, no un dato.
enum EstadoDeCorrida {
  verde,
  rojo,

  /// Algo no se pudo observar. Se trata como rojo (ADR-011).
  noConcluyente,

  /// El arnés se rompió. **Distinto de «el cambio no verificó»**: acá no se
  /// puede afirmar nada sobre el cambio.
  errorInterno,
}

/// Un paso que **no tuvo nada que hacer**, con su motivo.
///
/// Es un tercer estado, distinto de «corrió» y de «no pudo mirar», y el corpus
/// lo traza: *«sin anotaciones tocadas → SALTAR · testigo: motivo registrado»*,
/// y su meta-check lo cuenta aparte —*«registrados: 7 · ejecutados: 6 ·
/// saltados: 1 con motivo → sin discrepancia»*—.
///
/// **Confundirlo con «no pude mirar» es el falso rojo simétrico del falso verde
/// que ADR-011 caza**, y estaba ocurriendo: un alcance sin archivos del stack
/// daba «no concluyente: algún paso no pudo observar su alcance» cuando el paso
/// había terminado completo y no tenía nada suyo que mirar.
///
/// **La herramienta NO corrió, y ahora el tipo lo dice.** Antes esto se
/// representaba con un testigo de `Termination.completa` y código 0 —«la
/// herramienta corrió y produjo un resultado»— y la cascada **exigía ese hecho
/// falso** para clasificar bien. Dos reviews seguidos lo señalaron: primero la
/// prosa que no se comprobaba, y después la mentira de la que dependía lo
/// correcto.
///
/// **Lo clasifica la cascada, no el paso.** ADR-011 corolario 4: ningún
/// verificador juzga su propia cobertura. El paso declara un hecho contable
/// sobre su entrada —`Witness.ownSubjects`— y quien compone la corrida decide
/// qué significa.
class PasoSaltado {
  final String id;

  /// Por qué. **Sale del testigo, no de una frase escrita acá**: es lo que el
  /// propio paso declaró haber omitido.
  final List<String> motivos;

  /// Lo que el paso declaró. **No es un testigo**: no hubo invocación que
  /// atestiguar, y fabricar una era el hecho falso del que dependía esta
  /// clasificación.
  final NotApplicable declaracion;

  PasoSaltado({
    required this.id,
    required List<String> motivos,
    required this.declaracion,
  }) : motivos = List.unmodifiable(motivos) {
    // **Un salto sin motivo es un salto silencioso**, que es justo lo que
    // ADR-011 corolario 1 prohíbe y lo que la documentación de este tipo
    // promete que no pasa. La promesa estaba escrita y el tipo la dejaba
    // romper: un review construyó uno con la lista vacía.
    if (this.motivos.every((m) => m.trim().isEmpty)) {
      throw ArgumentError.value(
          motivos,
          'motivos',
          'Un salto sin motivo es un salto silencioso. Si el paso no supo '
              'decir por qué no tenía nada que hacer, no se puede afirmar que '
              'no lo tenía');
    }
  }
}

/// Cómo terminó **un paso**, para quien mira la corrida mientras ocurre.
///
/// **Todo `started` necesita un desenlace observable.** Solo se avisaba de los
/// pasos que producían resultado: un salto y un fallo interno dejaban el
/// evento de inicio abierto para siempre, y un consumidor del protocolo en
/// streaming se quedaba esperando. Lo encontró un review sobre `--verbose`, que
/// además prometía el testigo de cada paso y no lo daba para los saltos.
sealed class DesenlaceDePaso {
  final String id;
  const DesenlaceDePaso(this.id);
}

/// Corrió y produjo su veredicto.
class PasoEjecutado extends DesenlaceDePaso {
  final VerificationOutcome resultado;
  PasoEjecutado(this.resultado) : super(resultado.verifierId);
}

/// No tuvo nada que hacer.
class PasoSinNadaQueHacer extends DesenlaceDePaso {
  final NotApplicable declaracion;
  PasoSinNadaQueHacer(super.id, this.declaracion);
}

/// Se rompió. **No es un veredicto sobre el cambio**: es el arnés.
class PasoRoto extends DesenlaceDePaso {
  final String causa;
  PasoRoto(super.id, this.causa);
}

/// Lo que resulta de correr una cascada.
///
/// [estado] se **deriva**, igual que `VerificationOutcome.verdict`. No hay
/// campo donde escribirlo, así que no hay forma de poner una corrida en verde
/// desde afuera.
class ResultadoDeCascada {
  /// Los pasos que el registro declara. **Es el denominador.**
  final List<String> registrados;

  /// Lo que devolvió cada paso que llegó a devolver algo.
  final List<VerificationOutcome> resultados;

  /// Los pasos que se rompieron, con su causa. Un paso que lanza no produjo
  /// un veredicto: produjo un error del arnés.
  final Map<String, String> fallosInternos;

  /// Los pasos que **no tuvieron nada que hacer**, con su motivo.
  final List<PasoSaltado> saltados;

  ResultadoDeCascada({
    required List<String> registrados,
    required List<VerificationOutcome> resultados,
    Map<String, String> fallosInternos = const {},
    List<PasoSaltado> saltados = const [],
  })  : registrados = List.unmodifiable(registrados),
        resultados = List.unmodifiable(resultados),
        fallosInternos = Map.unmodifiable(fallosInternos),
        saltados = List.unmodifiable(saltados);

  /// Qué pasos produjeron un resultado.
  List<String> get ejecutados =>
      List.unmodifiable([for (final r in resultados) r.verifierId]);

  /// **Registrados menos ejecutados menos saltados.** Es el corolario 2 de
  /// ADR-011: la diferencia se reporta. Sin esto, un paso que no corre se lee
  /// igual que un paso que corrió y no encontró nada — que es el modo de fallo
  /// que `docs/03` §6 nombra con nombre y apellido.
  ///
  /// **Un salto está contado**: Un salto está contado:
  /// no es una discrepancia, es un desenlace declarado con su motivo. Lo que
  /// queda acá es lo que no corrió **y nadie explicó**.
  List<String> get sinEjecutar {
    final contados = {...ejecutados, for (final s in saltados) s.id};
    return List.unmodifiable([
      for (final id in registrados)
        if (!contados.contains(id)) id,
    ]);
  }

  /// El estado de la corrida, calculado. La precedencia es
  /// `errorInterno > noConcluyente > rojo > verde`.
  ///
  /// **Que lo no concluyente gane sobre el rojo no es un descuido.** No se
  /// puede afirmar que el cambio falló cuando parte de la verificación no se
  /// ejecutó: el rojo invita a arreglar y volver a correr, y volver a correr
  /// puede seguir sin observar lo que faltó. Los diagnósticos bloqueantes
  /// igual se reportan; lo que cambia es qué se afirma del conjunto.
  EstadoDeCorrida get estado {
    if (fallosInternos.isNotEmpty) return EstadoDeCorrida.errorInterno;

    // Una cascada sin pasos que «termina bien» sería el falso verde más barato
    // de todos: no miró nada y nadie se lo preguntó.
    if (registrados.isEmpty) return EstadoDeCorrida.noConcluyente;

    // **Hoy `Cascada` no puede producir este estado**: todo paso que no
    // ejecuta queda además anotado como fallo interno, así que la rama de
    // arriba dispara primero. La comprobación no sobra: protege al TIPO de
    // cualquier otro constructor, y el primero que va a producir esa forma es
    // el corte temprano —un paso salteado por política está registrado, no
    // ejecutado, y no es un fallo—. Su prueba construye el resultado
    // directamente, porque un guardia que otro tapa no está probado.
    if (sinEjecutar.isNotEmpty) return EstadoDeCorrida.noConcluyente;

    // **Si se saltaron los pasos enteros, no se verificó nada.** Cada salto por separado es
    // legítimo; todos juntos son una corrida que no miró. Es el mismo falso
    // verde que la rama de arriba impide para la cascada vacía, por la otra
    // puerta: acá hay pasos registrados y ninguno tuvo nada que hacer.
    if (resultados.isEmpty) return EstadoDeCorrida.noConcluyente;

    // **Un alcance que no se pudo observar entero no da verde.**
    //
    // `docs/03` §6 dejaba esta decisión explícitamente acá —*«si una omisión
    // debe detener algo es política de `orchestration`»*— y hasta ahora
    // `orchestration` no consumía el dato: un paso que cubría `lib/` y no
    // podía mirar `no/existe` atestiguaba igual, y con otro paso en verde la
    // corrida salía VERDE sobre un alcance parcialmente no observado. La
    // seguridad dependía de que OTRO paso tropezara con el mismo obstáculo.
    //
    // `null` no es cero: es «no pude establecerlo». Un verde sobre eso es
    // exactamente el verde que nadie miró.
    if (resultados.any((r) => r.witness?.ownSubjects == null)) {
      return EstadoDeCorrida.noConcluyente;
    }

    if (resultados.any((r) => r.verdict == Verdict.noConcluyente)) {
      return EstadoDeCorrida.noConcluyente;
    }
    if (resultados.any((r) => r.verdict == Verdict.rojo)) {
      return EstadoDeCorrida.rojo;
    }
    return EstadoDeCorrida.verde;
  }

  /// Todos los diagnósticos, en el orden en que los pasos los produjeron.
  List<Diagnostic> get diagnosticos =>
      List.unmodifiable([for (final r in resultados) ...r.diagnostics]);
}

/// Un registro ordenado de pasos.
///
/// El orden es de costo creciente y lo decide quien compone. **No hay corte
/// temprano todavía**: todos los pasos corren. `D-099` lo congeló — aparece dos
/// veces en el corpus y ninguna dice **cuándo** corta—, y su precondición sí
/// está: un paso que no ejecuta y no es una falla.
///
/// **El orden no está «medido», aunque `D-050` lo pida.** Los tiempos salen de
/// la línea base A0, que el plan declara fuera de alcance; se declara a mano y
/// queda dicho (`D-100`).
class Cascada {
  final List<Verifier> pasos;

  Cascada(List<Verifier> pasos) : pasos = List.unmodifiable(pasos) {
    // **El id de un paso es una CLAVE**, no una etiqueta: es con lo que se
    // comparan registrados contra ejecutados. Dos pasos con el mismo id
    // dejarían ese meta-check ciego —uno taparía al otro— y un paso podría no
    // correr sin que nada lo note.
    //
    // Es la misma lección que el motor de checks aprendió con las clases
    // homónimas de `core`, y por eso se rechaza al construir en vez de
    // esperar a que alguien se acuerde.
    final vistos = <String>{};
    for (final p in this.pasos) {
      if (p.id.trim().isEmpty) {
        throw const CascadaNoRegistrable(
            'Hay un paso sin id. El id es con lo que se comprueba que el paso '
            'corrió: sin él no se puede saber si faltó.');
      }
      if (!vistos.add(p.id)) {
        throw CascadaNoRegistrable(
            'El id «${p.id}» está registrado más de una vez. Se comparan '
            'registrados contra ejecutados por id, así que uno taparía al otro '
            'y un paso podría no correr sin que nadie se entere.');
      }
    }
  }

  /// Los ids registrados, en orden.
  List<String> get registrados =>
      List.unmodifiable([for (final p in pasos) p.id]);

  /// Corre todos los pasos y devuelve lo que resultó.
  ///
  /// **[alEmpezar] y [alTerminar] se llaman mientras la corrida ocurre**, no
  /// después. La primera versión devolvía todo junto y el CLI recorría los
  /// resultados al final: no había nada que mirar mientras una herramienta
  /// tardaba, y los eventos llevaban la hora de cuando se armó el reporte, no
  /// la del paso. La superficie pide que una operación de más de tres segundos
  /// muestre el paso en curso, y eso no se puede hacer desde el final.
  ///
  /// **Un paso que lanza no interrumpe la cascada**: se registra como fallo
  /// interno y los demás corren igual. Cortar ahí dejaría a los siguientes sin
  /// ejecutar Y sin explicación, y las dos cosas se confundirían en el
  /// reporte de registrados contra ejecutados.
  Future<ResultadoDeCascada> correr(
    List<String> sujetos, {
    void Function(String id)? alEmpezar,
    void Function(DesenlaceDePaso desenlace)? alTerminar,
  }) async {
    // **Se congela al entrar.** La lista es del llamador, que puede mutarla
    // entre paso y paso: el primero correría sobre un alcance y el segundo
    // sobre otro, y el reporte diría que los dos cubrieron lo mismo. Es el
    // mismo invariante que `PasoDeCascada.run` ya aplica un nivel más abajo, y
    // que acá faltaba.
    final alcance = List<String>.unmodifiable(sujetos);
    final resultados = <VerificationOutcome>[];
    final fallos = <String, String>{};
    final saltados = <PasoSaltado>[];

    for (final paso in pasos) {
      alEmpezar?.call(paso.id);
      DesenlaceDePaso? desenlace;
      try {
        final r = await paso.run(alcance);
        // Un paso que devuelve el resultado de OTRO paso rompe la cuenta.
        if (r.verifierId != paso.id) {
          fallos[paso.id] = 'devolvió un resultado con id «${r.verifierId}»; '
              'la cuenta de registrados contra ejecutados se apoya en que '
              'coincidan.';
          desenlace = PasoRoto(paso.id, fallos[paso.id]!);
        } else {
          // **La clasificación es una distinción de tipo, no un conjunto de
          // condiciones.** Eran cuatro —cero propios, nada cubierto,
          // terminación completa, algún motivo— y cada review encontraba la
          // combinación que faltaba, porque intentaban reconstruir desde los
          // campos un hecho que el tipo no sabía expresar.
          //
          // Queda una sola condición extra: un salto es la ausencia de
          // trabajo, **no la desaparición de un hallazgo**.
          final na = r.notApplicable;
          if (na != null && r.diagnostics.isEmpty) {
            saltados.add(
                PasoSaltado(id: paso.id, motivos: na.reasons, declaracion: na));
            desenlace = PasoSinNadaQueHacer(paso.id, na);
          } else {
            resultados.add(r);
            desenlace = PasoEjecutado(r);
          }
        }
      } on Object catch (e) {
        // Se atrapa cualquier excepción a propósito, y solo acá: un paso que
        // se rompe es un error del arnés, no un veredicto sobre el cambio, y
        // confundirlos es lo que el código de salida `70` existe para impedir.
        fallos[paso.id] = '$e';
        desenlace = PasoRoto(paso.id, '$e');
      }

      // **Todo `started` termina con un desenlace.** Antes esto vivía dentro
      // del cuerpo y los `continue` lo salteaban: un salto y un fallo interno
      // dejaban el evento de inicio abierto para siempre, y quien consumiera
      // el protocolo en streaming se quedaba esperando. Por eso ya no hay
      // `continue`: las tres ramas asignan y la notificación es una sola, al
      // final, fuera del `try` —una excepción del observador es del arnés, no
      // del verificador que hizo su trabajo—.
      // Sin `!`: el analizador prueba que las tres ramas asignan. **La
      // garantía de que todo `started` cierra la sostiene el compilador**, no
      // un comentario ni una prueba.
      alTerminar?.call(desenlace);
    }

    return ResultadoDeCascada(
      registrados: registrados,
      resultados: resultados,
      fallosInternos: fallos,
      saltados: saltados,
    );
  }
}
