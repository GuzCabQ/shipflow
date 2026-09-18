/// El preflight de `ship`: todo lo que falla **antes de escribir nada**.
///
/// **Es una función pura sobre hechos ya leídos.** No corre `git`, no
/// consulta la configuración ni pregunta a la forja: recibe la rama actual
/// ([RepositorioGit.ramaActual], en `vcs`), la rama pedida, las tres fuentes
/// de la base y la credencial ya leída (por un [CredentialSource], en
/// `core`), y devuelve el resultado. Quien orquesta `ship` ya hizo esas
/// lecturas antes de llamar acá. Con eso, los siete casos del diseño se
/// prueban sin montar un repositorio por cada uno — el mismo criterio con el
/// que se escribió la recuperación de la rebanada anterior.
///
/// **Qué NO comprueba, a propósito: el directorio de corridas y su
/// `.gitignore`.** Ese directorio (`.shipflow/runs`) no existe todavía en el
/// primer uso, y exigirlo acá impediría exactamente eso: la primera corrida.
/// Se crea y se comprueba DESPUÉS de la compuerta y ANTES de persistir el
/// documento `prepared` — es trabajo de otra tarea de esta rebanada, no de
/// este archivo.
library;

import 'package:core/core.dart';

/// El resultado del preflight: **un tipo cerrado**, no un booleano con un
/// mensaje al costado. Que la rama, la base y la credencial solo existan
/// juntas del lado que salió bien es lo que impide construir un «éxito» al
/// que le falte alguna.
sealed class ResultadoDePreflight {
  const ResultadoDePreflight();
}

/// El preflight pasó: hay rama, hay base y hay credencial.
///
/// **`credencial` viaja entera, no su secreto.** [Credential] presta el
/// secreto con `use` y enmascara todo lo demás; quien reciba este resultado
/// tiene que seguir pidiéndole permiso al tipo, no obtener el texto acá.
class PreflightOk extends ResultadoDePreflight {
  /// La rama sobre la que se va a trabajar. Es la rama ACTUAL: `ship` nunca
  /// cambia de rama, así que no hay una «rama resultante» distinta de la que
  /// ya había.
  final String rama;

  /// La base ya resuelta, al final de la cadena de tres fuentes.
  final String base;

  final Credential credencial;

  const PreflightOk({
    required this.rama,
    required this.base,
    required this.credencial,
  });
}

/// Por qué el preflight rechazó la corrida. Las cinco causas terminan en el
/// mismo código de proceso —`4`, cero escrituras— pero un mensaje que no
/// distingue cuál de las cinco pasó manda a buscar en el lugar equivocado.
enum CausaDePreflight {
  /// `--branch` es una aserción y no coincidió con la rama actual.
  ramaNoCoincide,

  /// `HEAD` está suelto. [RepositorioGit.ramaActual] devuelve vacío para
  /// decir esto, y ese vacío es un estado y no un error — pero un `HEAD`
  /// suelto no es una rama sobre la que `ship` pueda afirmar nada: no hay a
  /// qué compararle `--branch`, y no hay qué mostrar en la previsualización.
  headSuelto,

  /// La rama actual coincide con la base. Commitear sobre la base y pedir un
  /// pull request contra ella misma no es una entrega: es un cambio directo
  /// sin revisión.
  baseIgualALaRama,

  /// Ninguna de las tres fuentes de la base dio un valor. La base no se
  /// asume: una corrida que adivinara silenciaría exactamente el error que
  /// esta causa existe para nombrar.
  baseIndeterminada,

  /// No hay credencial. Fallar acá y no más adelante es lo que hace cierto
  /// que el preflight es cero escrituras: sin credencial no hay con qué
  /// publicar, y no tiene sentido preparar un candidato para terminar
  /// detenido después de haber tocado el repositorio.
  credencialAusente,
}

/// El preflight rechazó la corrida. **Sin escribir nada.**
class PreflightFallo extends ResultadoDePreflight {
  final CausaDePreflight causa;

  /// Qué se encontró. Nunca el secreto de una credencial: eso [Credential]
  /// ni siquiera lo expone fuera de [Credential.use].
  final String detalle;

  /// Qué hacer para pasar el preflight. Cuando la causa es [CausaDePreflight.
  /// ramaNoCoincide], nombra la rama que se pidió — es la que hay que crear o
  /// a la que hay que cambiarse, y `ship` no lo hace por quien lo corre.
  final String queHacer;

  const PreflightFallo({
    required this.causa,
    required this.detalle,
    required this.queHacer,
  });
}

/// Corre las cinco comprobaciones del preflight, en el orden en que el
/// diseño las presenta: primero la rama —sin una rama sobre la que pararse,
/// preguntar por la base o por la credencial no tiene con qué contestarse—,
/// después la base, y por último la credencial.
///
/// [ramaActual] es lo que devuelve [RepositorioGit.ramaActual]: **vacío
/// significa `HEAD` suelto**, no «sin rama detectada». [branchPedida] es el
/// valor de `--branch`, o nulo si no se pasó.
///
/// La base se encadena por tres fuentes, en este orden de precedencia:
/// [baseExplicita] (`--base`), después [baseConfigurada] (la configuración de
/// shipflow) y por último [baseDeLaForja] (la rama por defecto que informa la
/// forja). La primera que no sea nula gana.
ResultadoDePreflight preflight({
  required String ramaActual,
  required String? branchPedida,
  String? baseExplicita,
  String? baseConfigurada,
  String? baseDeLaForja,
  required Credential? credencial,
}) {
  // **`HEAD` suelto se decide antes que la aserción de `--branch`.** Con
  // `ramaActual` vacía, compararla contra lo que pidió `--branch` daría
  // `ramaNoCoincide` con un mensaje que habla de una rama que no existe en
  // vez de decir la causa real: no hay rama ninguna donde pararse.
  if (ramaActual.isEmpty) {
    return const PreflightFallo(
      causa: CausaDePreflight.headSuelto,
      detalle:
          'HEAD está suelto: no hay una rama actual sobre la que '
          'trabajar.',
      queHacer:
          'Cambiate a una rama antes de correr `ship`. `ship` nunca '
          'cambia de rama por su cuenta: cambiarla después de verificar '
          'invalidaría el candidato.',
    );
  }

  // **`--branch` es una aserción, no una instrucción.** El diseño ya la
  // resolvió contra la rama de la rebanada en `interpretarShip`/
  // `resolverRebanada`; acá se la compara contra la rama en la que el
  // repositorio ya está, que es la única fuente de verdad sobre dónde se va
  // a commitear.
  if (branchPedida != null && branchPedida != ramaActual) {
    return PreflightFallo(
      causa: CausaDePreflight.ramaNoCoincide,
      detalle:
          '--branch pidió «$branchPedida» y la rama actual es '
          '«$ramaActual».',
      queHacer:
          'Cambiate a «$branchPedida» antes de correr `ship`, o sacá '
          '--branch si la intención era la rama en la que ya estás. `ship` '
          'no cambia de rama: cambiarla después de verificar invalidaría el '
          'candidato.',
    );
  }

  // **La base no se asume.** La cadena de tres fuentes vive acá, y no en
  // `??` sueltos en el llamador, porque «cuál gana» es una regla del diseño y
  // no un detalle de quien junta los hechos.
  final base = baseExplicita ?? baseConfigurada ?? baseDeLaForja;
  if (base == null) {
    return const PreflightFallo(
      causa: CausaDePreflight.baseIndeterminada,
      detalle:
          'No hay --base, ni configuración de shipflow, ni una rama '
          'por defecto que informe la forja.',
      queHacer:
          'Pasá --base explícitamente, o configurá una base por '
          'defecto en shipflow.',
    );
  }

  // Commitear sobre la base y pedir un pull request contra ella misma no es
  // una entrega: es un cambio directo sin revisión.
  if (ramaActual == base) {
    return PreflightFallo(
      causa: CausaDePreflight.baseIgualALaRama,
      detalle: 'La rama actual y la base son la misma: «$base».',
      queHacer:
          'Trabajá en una rama distinta de «$base» y volvé a correr '
          '`ship`. `ship` no cambia de rama: creala o cambiate vos antes.',
    );
  }

  if (credencial == null) {
    return const PreflightFallo(
      causa: CausaDePreflight.credencialAusente,
      detalle: 'No hay credencial para publicar en la forja.',
      queHacer:
          'Configurá la credencial de la forja antes de correr '
          '`ship`.',
    );
  }

  return PreflightOk(rama: ramaActual, base: base, credencial: credencial);
}
