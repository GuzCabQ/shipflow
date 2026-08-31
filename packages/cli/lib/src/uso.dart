/// La interpretación de la línea de comandos. **Una sola, y antes de todo.**
///
/// La frontera detectaba algunas banderas con `contains` y resolvía la ayuda
/// sin haber interpretado el resto. Con eso, `--inventada --help` salía con
/// `0`, `--quiet --verbose --help` también —cuando SC-17 exige `5`— y
/// `--quiet --help` no mostraba la ayuda que se le había pedido.
///
/// Comprobar la presencia de una bandera no es interpretar la invocación.
library;

/// Se lanza cuando la invocación no se puede interpretar. Es el código `5`.
class UsoInvalido implements Exception {
  final String reason;
  final String queHacer;
  const UsoInvalido(this.reason, this.queHacer);

  @override
  String toString() => 'UsoInvalido: $reason';
}

/// Lo que la invocación dijo, ya interpretado.
class Globales {
  final bool json;
  final bool silencioso;
  final bool detallado;
  final bool ayuda;

  /// El primer argumento que no empieza con guion, si lo hay.
  final String? comando;

  /// Lo que le toca al subcomando: sus argumentos posicionales y las banderas
  /// que este intérprete no reconoce. **No se descartan**: un subcomando puede
  /// tener banderas propias, y el día que las tenga es él quien las acepta o
  /// las rechaza. Sin comando, no hay quien las acepte, y por eso ahí sí son
  /// un error.
  final List<String> restantes;

  Globales({
    required this.json,
    required this.silencioso,
    required this.detallado,
    required this.ayuda,
    required this.comando,
    required List<String> restantes,
  }) : restantes = List.unmodifiable(restantes);
}

/// Las banderas globales que hoy existen. Las del documento que todavía no se
/// implementan —`--no-color`, `--config`, `--version`— **no están acá a
/// propósito**: aceptarlas sin hacer nada sería prometer un comportamiento que
/// no hay.
const banderasGlobales = {
  '--json',
  '--quiet',
  '-q',
  '--verbose',
  '--help',
  '-h',
};

/// Interpreta la invocación entera.
///
/// El orden de las comprobaciones es deliberado: **una contradicción entre
/// banderas se rechaza antes que nada**, porque no hay forma de honrar las dos
/// y elegir una sería adivinar. Después las banderas que nadie puede aceptar.
/// Y recién ahí la ayuda, que **gana sobre `--quiet`**: si alguien la pidió,
/// callarla es no hacer lo que se pidió.
Globales interpretarGlobales(List<String> args) {
  var json = false, silencioso = false, detallado = false, ayuda = false;
  String? comando;
  final restantes = <String>[];
  final desconocidas = <String>[];

  for (final a in args) {
    if (!a.startsWith('-')) {
      if (comando == null) {
        comando = a;
      } else {
        restantes.add(a);
      }
      continue;
    }
    switch (a) {
      case '--json':
        json = true;
      case '--quiet' || '-q':
        silencioso = true;
      case '--verbose':
        detallado = true;
      case '--help' || '-h':
        ayuda = true;
      default:
        desconocidas.add(a);
        restantes.add(a);
    }
  }

  if (silencioso && detallado) {
    throw const UsoInvalido('`--quiet` y `--verbose` se contradicen',
        'Elegí una: `--quiet` para solo errores, `--verbose` para los testigos.');
  }

  if (comando == null && desconocidas.isNotEmpty) {
    throw UsoInvalido('bandera desconocida: «${desconocidas.first}»',
        'Corré `shipflow --help` para ver las que hay.');
  }

  return Globales(
    json: json,
    silencioso: silencioso,
    detallado: detallado,
    ayuda: ayuda,
    comando: comando,
    restantes: restantes,
  );
}
