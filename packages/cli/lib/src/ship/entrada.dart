/// La entrada de `ship`: qué se publica, y las reglas que lo impiden.
///
/// **No hay valor por omisión que barra el árbol de trabajo.** Sin
/// `--file` ni `--slice`, la invocación falla en vez de inferir «todos los
/// cambios detectados». Barrer el árbol metería en el pull request cambios
/// que nadie planeó, y el artefacto de revisión los declararía **cubiertos**
/// —por ADR-012—, que es pedirle a una persona que no los mire. Un default
/// que barre reintroduce **en la entrada** el falso verde que el resto del
/// diseño cierra en la salida: los archivos se declaran, no se detectan.
///
/// El estilo es el de `interpretarGlobales`: comprobar la presencia de una
/// bandera con `contains` no es interpretarla, y por eso una bandera
/// desconocida falla en vez de ignorarse.
library;

import 'dart:convert';
import 'dart:io' show FileSystemException;

import '../uso.dart';

/// Lo que la invocación de `ship` dijo, ya interpretado.
class EntradaDeShip {
  final String? intent;

  /// Los archivos declarados con `--file`. Vacía cuando la selección viene
  /// de `--slice`, y ahí es `rutaDeLaRebanada` la que tiene el dato.
  final List<String> archivos;

  /// La ruta declarada con `--slice`, **sin leer**. Nula cuando la selección
  /// vino de `--file`. Leerla y resolverla en `archivos` es trabajo de
  /// [resolverRebanada], que vive aparte porque sí toca disco: este
  /// intérprete no, y por eso sus pruebas son baratas.
  final String? rutaDeLaRebanada;

  final String? branch;
  final String? base;
  final bool dryRun;
  final bool yes;
  final bool allowIncomplete;

  /// El identificador de la corrida que `--retry-publication` pide terminar,
  /// o **nulo cuando no se pidió ningún reintento**.
  ///
  /// **No declara una rebanada: la rebanada ya está en el documento de esa
  /// corrida.** Por eso es excluyente con `--file`, `--slice` e `--intent` —
  /// declararlos junto con esto afirmaría dos veces, y distinto, de dónde
  /// sale la intención que se publica—, y por eso viaja como un campo más de
  /// esta misma clase en vez de un tipo aparte: el resto de la interpretación
  /// —`--branch`, `--base`, `--dry-run`— no cambia de forma según cuál de las
  /// dos formas de invocar se haya usado.
  final String? reintentarPublicacion;

  EntradaDeShip({
    required this.intent,
    required List<String> archivos,
    required this.rutaDeLaRebanada,
    required this.branch,
    required this.base,
    required this.dryRun,
    required this.yes,
    required this.allowIncomplete,
    required this.reintentarPublicacion,
  }) : archivos = List.unmodifiable(archivos);
}

/// Exige que ningún archivo se repita. **Una sola función para las dos
/// formas de declarar archivos** —`--file` y un archivo de rebanada—, porque
/// el motivo es el mismo en las dos: `apply` exige declarar cada archivo una
/// sola vez, porque compara con igualdad literal. La forma en que la lista
/// llegó no cambia esa comparación, así que tampoco cambia esta regla.
void _exigirSinRepetidos(List<String> archivos) {
  final vistos = <String>{};
  for (final archivo in archivos) {
    if (!vistos.add(archivo)) {
      throw UsoInvalido(
        'archivo repetido: «$archivo»',
        'Cada archivo se declara una sola vez: sacá el duplicado.',
      );
    }
  }
}

/// Interpreta la invocación de `ship` entera.
///
/// El orden de las comprobaciones repite el de `interpretarGlobales`: la
/// contradicción entre `--file` y `--slice` se rechaza antes que nada, porque
/// no hay forma de honrar las dos. Después, las banderas que nadie puede
/// aceptar. Recién ahí las reglas que dependen de cuál de las dos formas se
/// usó, y por último la que motiva este archivo: cero archivos —el default
/// que se rechaza— y archivos repetidos, que `apply` exige declarar una sola
/// vez porque compara con igualdad literal.
EntradaDeShip interpretarShip(List<String> args) {
  String? intent;
  String? slice;
  String? branch;
  String? base;
  String? reintentarPublicacion;
  var dryRun = false, yes = false, allowIncomplete = false;
  final archivos = <String>[];
  final desconocidas = <String>[];

  // La misma guardia que ya protege a las banderas booleanas —no comerse el
  // argumento siguiente— hacía falta acá también. Sin ella, `--intent
  // --file a.txt` le daba `--file` a `--intent` como valor y culpaba a
  // `a.txt` de ser una bandera desconocida: el mensaje mandaba a buscar el
  // problema donde no estaba. Un valor no puede ser, a su vez, una bandera:
  // ninguna ruta ni ninguna intención empieza con `--`.
  String valorDe(int indiceDeBandera, String bandera) {
    final indiceDeValor = indiceDeBandera + 1;
    final sinValor =
        indiceDeValor >= args.length || args[indiceDeValor].startsWith('--');
    if (sinValor) {
      throw UsoInvalido(
        '$bandera necesita un valor',
        'Pasá $bandera seguido de un valor que no sea otra bandera.',
      );
    }
    return args[indiceDeValor];
  }

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--intent':
        intent = valorDe(i, a);
        i++;
      case '--file':
        archivos.add(valorDe(i, a));
        i++;
      case '--slice':
        slice = valorDe(i, a);
        i++;
      case '--branch':
        branch = valorDe(i, a);
        i++;
      case '--base':
        base = valorDe(i, a);
        i++;
      case '--retry-publication':
        reintentarPublicacion = valorDe(i, a);
        i++;
      case '--dry-run':
        dryRun = true;
      case '--yes':
        yes = true;
      case '--allow-incomplete':
        allowIncomplete = true;
      default:
        desconocidas.add(a);
    }
  }

  // **La exclusión con el reintento se comprueba antes que ninguna otra
  // cosa**, igual que `--file` y `--slice` entre sí: un reintento no declara
  // una rebanada —la rebanada ya está en el documento de la corrida que se
  // quiere terminar— así que pasar `--file`, `--slice` o `--intent` junto con
  // `--retry-publication` no es una preferencia entre dos formas válidas, es
  // una contradicción sobre el mismo hecho —de dónde sale lo que se publica—,
  // y este proyecto ya decidió que esas no se resuelven eligiendo una en
  // silencio. El mensaje nombra las DOS banderas en conflicto, para que quien
  // lo lee no tenga que adivinar cuál de las dos sobra.
  if (reintentarPublicacion != null) {
    if (archivos.isNotEmpty) {
      throw const UsoInvalido(
        '--retry-publication y --file se contradicen',
        'La rebanada de un reintento ya está en el documento de la corrida '
            'que se quiere terminar, no en la línea de comandos: sacá --file, '
            'o sacá --retry-publication si lo que querés es una corrida '
            'nueva.',
      );
    }
    if (slice != null) {
      throw const UsoInvalido(
        '--retry-publication y --slice se contradicen',
        'La rebanada de un reintento ya está en el documento de la corrida '
            'que se quiere terminar, no en un archivo aparte: sacá --slice, '
            'o sacá --retry-publication si lo que querés es una corrida '
            'nueva.',
      );
    }
    if (intent != null) {
      throw const UsoInvalido(
        '--retry-publication y --intent se contradicen',
        'La intención de un reintento ya está en el documento de la corrida '
            'que se quiere terminar: sacá --intent, o sacá '
            '--retry-publication si lo que querés es una corrida nueva.',
      );
    }
    // **`--yes` y `--allow-incomplete` no se aceptan, y no es la misma regla
    // de arriba.** No hay dos afirmaciones contradictorias sobre un mismo
    // hecho: la compuerta que las dos autorizan ya pasó en la corrida
    // original, y volver a ofrecerlas acá sugeriría que se puede volver a
    // decidir algo que ya se decidió una vez.
    if (yes) {
      throw const UsoInvalido(
        '--retry-publication y --yes no conviven',
        'La compuerta que --yes autoriza ya pasó en la corrida original: no '
            'hay nada que volver a autorizar. Sacá --yes.',
      );
    }
    if (allowIncomplete) {
      throw const UsoInvalido(
        '--retry-publication y --allow-incomplete no conviven',
        'La compuerta que --allow-incomplete autoriza ya pasó en la corrida '
            'original: no hay nada que volver a autorizar. Sacá '
            '--allow-incomplete.',
      );
    }
  }

  if (archivos.isNotEmpty && slice != null) {
    throw const UsoInvalido(
      '--file y --slice son excluyentes',
      'Elegí una forma: `--file` (con --intent) para archivos sueltos, o '
          '`--slice` para una rebanada ya declarada.',
    );
  }

  if (desconocidas.isNotEmpty) {
    throw UsoInvalido(
      'bandera desconocida: «${desconocidas.first}»',
      'Las banderas de `ship` son --intent, --file, --slice, --branch, '
          '--base, --retry-publication, --dry-run, --yes y '
          '--allow-incomplete.',
    );
  }

  if (archivos.isNotEmpty && intent == null) {
    throw const UsoInvalido(
      '--intent es obligatorio con --file',
      'Pasá --intent "descripción" junto con --file.',
    );
  }

  if (slice != null && intent != null) {
    throw const UsoInvalido(
      '--intent no se acepta con --slice',
      'La rebanada ya trae su intención declarada; sacá --intent.',
    );
  }

  // **Exceptuado cuando hay un reintento.** Un reintento no selecciona
  // archivos —los toma del documento de la corrida original—, así que no
  // declarar ninguno acá no es el default que barre el árbol de trabajo que
  // el resto de este archivo rechaza: es la forma correcta de esta otra
  // invocación.
  if (archivos.isEmpty && slice == null && reintentarPublicacion == null) {
    throw const UsoInvalido(
      'no se declaró ningún archivo',
      'Pasá --file (uno o más, junto con --intent) o --slice con la '
          'rebanada ya declarada. `ship` no infiere el árbol de trabajo.',
    );
  }

  _exigirSinRepetidos(archivos);

  return EntradaDeShip(
    intent: intent,
    archivos: archivos,
    rutaDeLaRebanada: slice,
    branch: branch,
    base: base,
    dryRun: dryRun,
    yes: yes,
    allowIncomplete: allowIncomplete,
    reintentarPublicacion: reintentarPublicacion,
  );
}

/// Las claves que el formato de un archivo de rebanada declara. Una clave que
/// no está acá se rechaza en vez de ignorarse: ignorarla en silencio dejaría
/// creer que configuró algo que el archivo nunca leyó.
const _clavesDeLaRebanada = {'intent', 'files', 'branch', 'base'};

/// Lo que hay adentro de un archivo de rebanada — lo que `--slice` señala.
///
/// **No es un `PullRequestSlice` serializado, y la omisión es a propósito.**
/// Ese tipo lleva el identificador de la rebanada; este archivo, no. El
/// identificador es `${runId}/1` y lo asigna la corrida, no el archivo: hoy
/// hay una sola rebanada por corrida, pero el modelo final admite varias, y
/// si el archivo trajera el identificador habría dos fuentes de la misma
/// identidad. Dos fuentes del mismo hecho divergen siempre.
class ArchivoDeRebanada {
  final String intent;

  /// Nunca vacía: [desdeJson] lo exige, por la misma razón que
  /// `interpretarShip` rechaza cero archivos de `--file`.
  final List<String> files;

  final String? branch;
  final String? base;

  ArchivoDeRebanada({
    required this.intent,
    required List<String> files,
    required this.branch,
    required this.base,
  }) : files = List.unmodifiable(files);

  /// Interpreta el objeto JSON de un archivo de rebanada.
  ///
  /// Lanza [FormatException] —la misma familia que `DocumentoDeCorrida.
  /// fromJson` y el resto de las lecturas de JSON de este repositorio— para
  /// «este archivo no se puede leer». Traducir eso a `UsoInvalido` es trabajo
  /// de quien resuelve la rebanada, no de esta lectura.
  static ArchivoDeRebanada desdeJson(Map<String, Object?> json) {
    final desconocidas = json.keys.toSet().difference(_clavesDeLaRebanada);
    if (desconocidas.isNotEmpty) {
      throw FormatException(
        'el archivo de rebanada trae una clave que el formato no declara: '
        '«${desconocidas.first}». Las claves válidas son: '
        '${_clavesDeLaRebanada.join(", ")}.',
      );
    }

    final intent = json['intent'];
    if (intent is! String || intent.trim().isEmpty) {
      throw const FormatException(
        'el archivo de rebanada no declara «intent» como una cadena no '
        'vacía.',
      );
    }

    final files = json['files'];
    if (files is! List || files.isEmpty || files.any((f) => f is! String)) {
      throw const FormatException(
        'el archivo de rebanada no declara «files» como una lista de texto '
        'con al menos uno.',
      );
    }

    final branch = json['branch'];
    if (branch != null && branch is! String) {
      throw const FormatException(
        'el archivo de rebanada declara «branch» con algo que no es texto.',
      );
    }

    final base = json['base'];
    if (base != null && base is! String) {
      throw const FormatException(
        'el archivo de rebanada declara «base» con algo que no es texto.',
      );
    }

    return ArchivoDeRebanada(
      intent: intent,
      files: List<String>.from(files),
      branch: branch as String?,
      base: base as String?,
    );
  }
}

/// Lee `rutaDeLaRebanada`, si hay una, y devuelve la [EntradaDeShip]
/// completa: la misma forma que produce `--file`.
///
/// **Función aparte, y no parte de `interpretarShip`, a propósito.** Esta sí
/// toca disco; `interpretarShip` no, y esa pureza es lo que hace baratas sus
/// siete pruebas —no montan nada—. Fundir las dos encarecería esas pruebas
/// para pagar un camino —leer el archivo— que la mayoría no ejercita.
///
/// Si `entrada.rutaDeLaRebanada` es nula no hay nada que resolver: la
/// selección ya vino completa por `--file`, y esta función devuelve la
/// entrada tal cual.
///
/// `leer` es la única forma en que esta función toca el sistema de archivos,
/// y por eso es lo que una prueba reemplaza para no montar nada real: el
/// mismo motivo que ya separa la interpretación de la lectura.
///
/// Lo que `leer` no puede resolver —no existe, no se puede leer— y lo que el
/// contenido no cumple —no es JSON, no es el formato declarado— salen los
/// dos por [UsoInvalido], que el despachador traduce al código `5`. Ninguno
/// de los dos escapa como excepción cruda.
Future<EntradaDeShip> resolverRebanada(
  EntradaDeShip entrada, {
  required Future<String> Function(String ruta) leer,
}) async {
  final ruta = entrada.rutaDeLaRebanada;
  if (ruta == null) return entrada;

  final String contenido;
  try {
    contenido = await leer(ruta);
  } on FileSystemException catch (e) {
    throw UsoInvalido(
      'no se pudo leer la rebanada «$ruta»: ${e.osError?.message ?? e.message}',
      'Comprobá que la ruta exista y que el proceso pueda leerla.',
    );
  }

  final ArchivoDeRebanada archivo;
  try {
    final decodificado = jsonDecode(contenido);
    if (decodificado is! Map) {
      throw const FormatException(
        'el archivo de rebanada no es un objeto JSON.',
      );
    }
    archivo = ArchivoDeRebanada.desdeJson(
      Map<String, Object?>.from(decodificado),
    );
  } on FormatException catch (e) {
    throw UsoInvalido(
      'la rebanada «$ruta» no cumple el formato: ${e.message}',
      'Corregí el archivo: tiene que declarar «intent» y «files», y puede '
          'declarar «branch» y «base».',
    );
  }

  // Misma regla que `--file`, y por el mismo motivo: `apply` compara con
  // igualdad literal. `desdeJson` ya comprobó la forma del archivo; esto
  // comprueba su contenido, que es justo lo que la validación de formato no
  // mira.
  _exigirSinRepetidos(archivo.files);

  return EntradaDeShip(
    intent: archivo.intent,
    archivos: archivo.files,
    rutaDeLaRebanada: ruta,
    branch: _resolverBranch(
      explicito: entrada.branch,
      deLaRebanada: archivo.branch,
    ),
    // **`--base` sí se fusiona: la explícita gana y la rebanada rellena.**
    // Es el ruling de la tarea 2, y lo decidió con este argumento: la cadena
    // del diseño da tres fuentes a `base` —explícito → configuración → rama
    // por defecto de la forja— y la rebanada entra como una más.
    //
    // **Residuo declarado: entra ocupando la ranura de la explícita, o sea
    // POR ENCIMA de la configurada.** La cadena pasó a tener cuatro fuentes y
    // la nueva quedó metida en la primera, que es una decisión que aquel
    // ruling no argumentó — la tomó el mecanismo, este `??`. Se declara en
    // vez de moverse porque quien la tomó fue esa tarea y cambiarla ahora
    // sería revisar su ruling desde una ronda de arreglos.
    //
    // **Qué la volvería observable:** que `baseConfigurada` deje de ser
    // siempre nula. Hoy la raíz de composición la pasa nula y lo declara —no
    // hay superficie de configuración—, así que una rebanada que declara
    // `base` y una configuración que declara otra no pueden coexistir. El día
    // que exista esa superficie, una rebanada con `base` va a ganarle a la
    // configuración del repositorio sin que nadie lo haya decidido, y ahí hay
    // que elegir: o la rebanada baja un escalón, o la cadena declara cuatro
    // fuentes con la rebanada primera y se dice por qué.
    base: entrada.base ?? archivo.base,
    dryRun: entrada.dryRun,
    yes: entrada.yes,
    allowIncomplete: entrada.allowIncomplete,
    // **Siempre nula acá, y no porque se la vuelva a decidir.** Un reintento
    // no trae `rutaDeLaRebanada`, así que esta función ya retornó más arriba
    // —`if (ruta == null) return entrada;`— antes de construir este segundo
    // valor: llegar hasta acá es la prueba de que `entrada.
    // reintentarPublicacion` es nula, la misma que exige `interpretarShip`.
    reintentarPublicacion: entrada.reintentarPublicacion,
  );
}

/// **`--branch` no es un valor: es una aserción.** El diseño dice que tiene
/// que coincidir con la rama actual —`ship` nunca cambia de rama—, y eso vale
/// igual venga la bandera de la línea de comandos o de la rebanada: las dos
/// declaraciones dicen «la corrida está en esta rama», sobre el mismo hecho.
///
/// Por eso esto NO es `??`. Fusionar con el operador —quedarse con la
/// explícita cuando las dos están— convertiría en silencio una contradicción
/// en una preferencia: si la línea de comandos dice `main` y la rebanada dice
/// `feature/x`, alguien se equivocó en una de las dos, y elegir una sin
/// avisar deja publicar sobre la rama que no era.
String? _resolverBranch({
  required String? explicito,
  required String? deLaRebanada,
}) {
  if (explicito == null) return deLaRebanada;
  if (deLaRebanada == null) return explicito;
  if (explicito == deLaRebanada) return explicito;
  throw UsoInvalido(
    '--branch («$explicito») y la rebanada («$deLaRebanada») declaran ramas '
        'distintas',
    'Las dos son la misma aserción dicha dos veces, y no coinciden. Sacá '
        '--branch, o corregí la rebanada para que declare la rama que '
        'corresponde.',
  );
}
