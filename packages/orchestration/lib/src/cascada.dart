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

  ResultadoDeCascada({
    required List<String> registrados,
    required List<VerificationOutcome> resultados,
    Map<String, String> fallosInternos = const {},
  })  : registrados = List.unmodifiable(registrados),
        resultados = List.unmodifiable(resultados),
        fallosInternos = Map.unmodifiable(fallosInternos);

  /// Qué pasos produjeron un resultado.
  List<String> get ejecutados =>
      List.unmodifiable([for (final r in resultados) r.verifierId]);

  /// **Registrados menos ejecutados.** Es el corolario 2 de ADR-011: la
  /// diferencia se reporta. Sin esto, un paso que no corre se lee igual que un
  /// paso que corrió y no encontró nada — que es el modo de fallo que
  /// `docs/03` §6 nombra con nombre y apellido.
  List<String> get sinEjecutar {
    final hechos = ejecutados.toSet();
    return List.unmodifiable([
      for (final id in registrados)
        if (!hechos.contains(id)) id,
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
/// temprano todavía**: todos los pasos corren. El corte es política de este
/// paquete y llega con su presupuesto; agregarlo ahora significaría que un
/// paso registrado deje de ejecutarse, y eso necesita que el reporte de
/// registrados contra ejecutados exista primero — que es lo que instala esta
/// rebanada.
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
  /// **Un paso que lanza no interrumpe la cascada**: se registra como fallo
  /// interno y los demás corren igual. Cortar ahí dejaría a los siguientes sin
  /// ejecutar Y sin explicación, y las dos cosas se confundirían en el
  /// reporte de registrados contra ejecutados.
  Future<ResultadoDeCascada> correr(List<String> sujetos) async {
    final resultados = <VerificationOutcome>[];
    final fallos = <String, String>{};

    for (final paso in pasos) {
      try {
        final r = await paso.run(sujetos);
        // Un paso que devuelve el resultado de OTRO paso rompe la cuenta.
        if (r.verifierId != paso.id) {
          fallos[paso.id] = 'devolvió un resultado con id «${r.verifierId}»; '
              'la cuenta de registrados contra ejecutados se apoya en que '
              'coincidan.';
          continue;
        }
        resultados.add(r);
      } on Object catch (e) {
        // Se atrapa cualquier excepción a propósito, y solo acá: un paso
        // que se rompe es un error del arnés, no un veredicto sobre el
        // cambio, y confundirlos es lo que el código de salida `70` existe
        // para impedir.
        fallos[paso.id] = '$e';
      }
    }

    return ResultadoDeCascada(
      registrados: registrados,
      resultados: resultados,
      fallosInternos: fallos,
    );
  }
}
