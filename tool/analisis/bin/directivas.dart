/// El mecanismo que comparten los controles de dependencias entre
/// bibliotecas: leer las directivas del árbol sintáctico, resolver una URI
/// dentro de una raíz, contrastar enumeraciones y encontrar ciclos. No decide
/// qué se mira ni qué está permitido: eso es de cada control, y cada uno pone
/// el prefijo de sus mensajes.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart' as analizador;

/// Una dependencia local entre dos archivos del universo.
final class Arista {
  const Arista(this.origen, this.destino, this.clase);

  final String origen;
  final String destino;

  /// `import`, `export`, `alternativa de import` o `alternativa de export`.
  final String clase;

  @override
  String toString() => '$origen → $destino ($clase)';
}

/// Las directivas de un archivo, cada URI con su clase. Un archivo que no se
/// lee o no parsea falla con nombre: de un árbol parcial no sale ninguna
/// arista, y eso se leería igual que «no importa nada».
List<(StringLiteral, String)> directivasDe(
  Directory lib,
  String rel,
  void Function(String) falla,
) {
  final ParseStringResult resultado;
  try {
    resultado = parseFile(
      path: '${lib.path}/$rel',
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
  } on analizador.FileSystemException catch (e) {
    // `parseFile` lee con el sistema de archivos del analizador, que lanza su
    // propia `FileSystemException`; la de `dart:io` cubre el resto.
    falla('no pude leer sus directivas: $rel (${e.message}).');
    return const [];
  } on FileSystemException catch (e) {
    falla('no pude leer sus directivas: $rel (${e.message}).');
    return const [];
  }
  if (resultado.errors.isNotEmpty) {
    falla(
      'no pude leer sus directivas: $rel no parsea '
      '(${resultado.errors.first.message}).',
    );
    return const [];
  }
  final salida = <(StringLiteral, String)>[];
  for (final d in resultado.unit.directives) {
    if (d is LibraryDirective) continue;
    if (d is PartDirective || d is PartOfDirective) {
      falla(
        'part no admitido: $rel usa `${d.toSource()}`, que esconde una '
        'biblioteca dentro de otra.',
      );
    } else if (d is NamespaceDirective) {
      final clase = d is ExportDirective ? 'export' : 'import';
      salida.add((d.uri, clase));
      for (final alternativa in d.configurations) {
        salida.add((alternativa.uri, 'alternativa de $clase'));
      }
    } else {
      falla('directiva desconocida: $rel tiene `${d.toSource()}`.');
    }
  }
  return salida;
}

/// Relativo a [raiz], o null si la URI no cae dentro de ahí. Una URI
/// `package:` se resuelve como del paquete cuyo `lib/` es [raiz]: quien llama
/// ya decidió, por su nombre, que lo es.
///
/// Se resuelve como URI de archivo codificada a partir de la ruta real: un
/// `..` que sale de [raiz] queda afuera, un `#` es parte del nombre y no un
/// fragmento, y un nombre no ASCII encuentra su archivo. Un segmento que no
/// puede ser parte de una ruta hace fallar la conversión y cuenta como afuera.
String? resolverDentro(String raiz, String rel, Uri escrita) {
  try {
    final base = Uri.file(raiz);
    final destino = escrita.isScheme('package')
        ? base.replace(
            pathSegments: [
              ...base.pathSegments,
              ...escrita.pathSegments.skip(1),
            ],
          )
        : Uri.file('$raiz/$rel').resolveUri(escrita);
    final ruta = normalizada(destino.toFilePath());
    return ruta.startsWith('$raiz/') ? ruta.substring(raiz.length + 1) : null;
  } on UnsupportedError {
    return null;
  }
}

/// `package:` sin un nombre de paquete válido y una ruta: no se puede decir
/// de qué paquete es ni qué archivo nombra.
bool paqueteIlegible(Uri uri) =>
    uri.isScheme('package') &&
    (uri.pathSegments.length < 2 ||
        !_nombreDePaquete.hasMatch(uri.pathSegments.first));

final _nombreDePaquete = RegExp(r'^[a-z_][a-z0-9_]*$');

/// [carpeta] es la que nombra el mensaje: la raíz del universo de quien llama.
void contrastar(
  String quien,
  String carpeta,
  Set<String> vistos,
  Set<String> universo,
  void Function(String) falla,
) {
  final omite = universo.difference(vistos).toList()..sort();
  final agrega = vistos.difference(universo).toList()..sort();
  if (omite.isNotEmpty) {
    falla(
      'cobertura insuficiente: $quien omite ${omite.join(', ')}, que existen '
      'en $carpeta.',
    );
  }
  if (agrega.isNotEmpty) {
    falla(
      'cobertura insuficiente: $quien ve ${agrega.join(', ')}, que el '
      'recorrido físico no cuenta como archivo.',
    );
  }
}

/// La misma carpeta puede llegar escrita de dos formas —con o sin un enlace
/// del sistema en el camino, como `/var` y `/private/var` en macOS—, y el
/// analizador no promete cuál usa. Se acepta cualquiera de las dos.
String Function(String) relativizador(Directory lib) {
  final bases = {
    normalizada(lib.path),
    normalizada(lib.absolute.path),
    if (lib.existsSync()) normalizada(lib.resolveSymbolicLinksSync()),
  };
  return (ruta) {
    final normal = normalizada(ruta);
    for (final base in bases) {
      if (normal.startsWith('$base/')) return normal.substring(base.length + 1);
    }
    return normal;
  };
}

String normalizada(String ruta) =>
    Uri.file(ruta).normalizePath().toFilePath().replaceAll(r'\', '/');

/// Tarjan. Un componente de un solo nodo cuenta si tiene un lazo propio.
List<List<String>> componentesCiclicos(
  Iterable<String> nodos,
  List<Arista> aristas,
) {
  final sucesores = <String, List<String>>{};
  for (final a in aristas) {
    (sucesores[a.origen] ??= []).add(a.destino);
  }
  final indice = <String, int>{};
  final bajo = <String, int>{};
  final pila = <String>[];
  final enPila = <String>{};
  final componentes = <List<String>>[];
  void visitar(String v) {
    indice[v] = bajo[v] = indice.length;
    pila.add(v);
    enPila.add(v);
    for (final w in sucesores[v] ?? const <String>[]) {
      if (!indice.containsKey(w)) {
        visitar(w);
        bajo[v] = bajo[v]! < bajo[w]! ? bajo[v]! : bajo[w]!;
      } else if (enPila.contains(w)) {
        bajo[v] = bajo[v]! < indice[w]! ? bajo[v]! : indice[w]!;
      }
    }
    if (bajo[v] != indice[v]) return;
    final componente = <String>[];
    String w;
    do {
      w = pila.removeLast();
      enPila.remove(w);
      componente.add(w);
    } while (w != v);
    final lazo = sucesores[v]?.contains(v) ?? false;
    if (componente.length > 1 || lazo) componentes.add(componente..sort());
  }

  for (final v in nodos) {
    if (!indice.containsKey(v)) visitar(v);
  }
  return componentes;
}

Set<String> alcanzables(String desde, List<Arista> aristas) {
  final vistos = <String>{};
  final pendientes = [desde];
  while (pendientes.isNotEmpty) {
    final v = pendientes.removeLast();
    for (final a in aristas.where((a) => a.origen == v)) {
      if (vistos.add(a.destino)) pendientes.add(a.destino);
    }
  }
  return vistos;
}
