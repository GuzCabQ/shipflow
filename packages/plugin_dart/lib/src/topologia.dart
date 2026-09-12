import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;
import 'package:yaml/yaml.dart';

/// Descubre los paquetes de un proyecto Dart o Flutter.
///
/// **`N1-01` del registro semilla: `pubspec.yaml` define el límite de paquete.**
/// Ese es el único hecho del ecosistema que este puerto necesita, y por eso
/// `ProjectTopology` puede tener tres campos y servir para cualquier stack.
///
/// POR QUÉ NO SE LE PIDE A `pub`
///     Sería lo natural viniendo de `capas.py`, que le pide el grafo resuelto a
///     pub en vez de parsear. Pero eso responde otra pregunta: pub da el grafo
///     RESUELTO —transitivo, con versiones, y exige que la resolución haya
///     corrido—. Acá la pregunta es dónde están los límites, que es lo
///     DECLARADO. Resolver es otro puerto: `DependencyResolver`.
///
///     La lección de `capas.py` igual se aplica: el manifiesto se le pide a un
///     PARSER de YAML, y las rutas a la biblioteca de rutas. Nada a mano.
///
/// DOS PASADAS, Y NO ES UNA OPTIMIZACIÓN
///     Primero se descubren TODOS los paquetes, después se resuelven las
///     flechas. Con una sola pasada no hay contra qué contrastar un destino, y
///     la primera versión de esto agregaba cualquier dependencia con `path:`
///     sin comprobar que apuntara adentro del proyecto: una dependencia hacia
///     un paquete de afuera aparecía como si fuera topología interna. Un
///     review lo reprodujo.
class TopologiaDart implements ProjectTopology {
  /// Raíz del proyecto que se analiza. **No es el nuestro**: es el del usuario.
  final Directory raiz;

  /// `N1-03`: artefactos de build. No son fuente y no contienen paquetes.
  static const _ignorados = {'.dart_tool', 'build', '.git'};

  TopologiaDart(this.raiz);

  @override
  Future<List<Package>> packages() async {
    // --- pasada 1 · qué paquetes existen y dónde ------------------------
    final manifiestos = <String, YamlMap>{};
    await for (final archivo in _manifiestos(raiz)) {
      manifiestos[rutas.canonicalize(archivo.parent.path)] = _leer(archivo);
    }
    final nombrePorDirectorio = {
      for (final e in manifiestos.entries) e.key: e.value['name'] as String,
    };

    // --- pasada 2 · las flechas, resueltas contra lo descubierto ---------
    final encontrados = [
      for (final e in manifiestos.entries)
        Package(
          name: nombrePorDirectorio[e.key]!,
          path: _relativo(e.key),
          dependsOn: _flechasInternas(e.key, e.value, nombrePorDirectorio),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));

    // Inmodificable: es una cláusula del contrato, no una precaución. Ver
    // `ProjectTopology` en core.
    return List.unmodifiable(encontrados);
  }

  YamlMap _leer(File archivo) {
    // La lectura y el parseo van juntos a propósito. Antes
    // `readAsString` quedaba fuera del try, así que un error de E/S escapaba
    // como `FileSystemException` en vez del diagnóstico contextual.
    try {
      final cargado = loadYaml(archivo.readAsStringSync());
      if (cargado is! YamlMap) {
        throw const FormatException('el manifiesto no es un mapa');
      }
      final nombre = cargado['name'];
      if (nombre is! String || nombre.isEmpty) {
        throw const FormatException('el manifiesto no declara `name`');
      }
      return cargado;
    } on Object catch (e) {
      // Un manifiesto ilegible NO se saltea. Saltarlo haría la topología más
      // chica, y eso se lee igual que un proyecto con menos paquetes: es la
      // clase 1 exacta, y el corolario 1 de ADR-011.
      throw TopologiaIlegible(archivo.path, e);
    }
  }

  /// Solo las flechas hacia otro paquete **descubierto dentro de la raíz**.
  ///
  /// Una dependencia por ruta hacia afuera del proyecto es una dependencia
  /// real, pero no es topología de ESTE proyecto: reportarla dejaría una
  /// arista colgante hacia un paquete que `packages()` nunca devuelve.
  /// Las externas por versión tampoco entran — eso es `DependencyResolver`.
  List<String> _flechasInternas(
    String directorio,
    YamlMap doc,
    Map<String, String> nombrePorDirectorio,
  ) {
    final salida = <String>{};
    final manifiesto = rutas.join(directorio, 'pubspec.yaml');

    // CADA RAMA CONCLUYE O RECHAZA. Ninguna se saltea porque no entendió.
    //
    // La primera versión validaba entrada por entrada y descartaba la SECCIÓN
    // entera con un `is! YamlMap`, así que `dependencies: 42` producía una
    // topología vacía en silencio. Se había arreglado el caso que un review
    // mostró, un nivel más adentro, y no la clase — que es lo que este
    // comentario existe para que no vuelva a pasar.
    for (final clave in const ['dependencies', 'dev_dependencies']) {
      if (!doc.containsKey(clave)) continue; // ausente: legítimamente vacía
      final seccion = doc[clave];
      if (seccion == null) continue; // `dependencies:` sin nada: idem
      if (seccion is! YamlMap) {
        throw TopologiaIlegible(
            manifiesto,
            FormatException('`$clave` no es un mapa sino '
                '${seccion.runtimeType}. No se puede saber qué dependencias '
                'declara, y suponer que ninguna sería inventar.'));
      }
      for (final entrada in seccion.entries) {
        final nombreDep = entrada.key;
        if (nombreDep is! String || nombreDep.isEmpty) {
          throw TopologiaIlegible(
              manifiesto,
              FormatException('`$clave` tiene una dependencia cuyo nombre no '
                  'es una cadena: ${nombreDep.runtimeType}.'));
        }
        final valor = entrada.value;
        // Formas LEGÍTIMAS de declarar algo que no es una dependencia local:
        //   `paquete: ^1.0.0`    una restricción de versión
        //   `paquete:`           sin restricción, valor nulo
        //   `paquete: {sdk: …}`  un mapa sin `path`
        // Las tres se saltean porque no son topología, y eso es una CONCLUSIÓN.
        if (valor == null || valor is String) continue;
        if (valor is! YamlMap) {
          throw TopologiaIlegible(
              manifiesto,
              FormatException('la dependencia «$nombreDep» no es ni una '
                  'restricción de versión ni un mapa: ${valor.runtimeType}'));
        }
        if (!valor.containsKey('path')) continue;
        final destino = valor['path'];
        if (destino is! String || destino.isEmpty) {
          // No poder INTERPRETAR una arista es distinto de que no HAYA arista.
          throw TopologiaIlegible(
              manifiesto,
              FormatException('la dependencia «$nombreDep» declara `path` con '
                  'algo que no es una ruta: '
                  '${destino == null ? "vacío" : destino.runtimeType}'));
        }
        final absoluto = rutas.canonicalize(rutas.join(directorio, destino));
        // El nombre lo da el manifiesto del DESTINO, no la clave de la
        // dependencia: las dos pueden diferir, y la que manda es la del
        // paquete real.
        final nombre = nombrePorDirectorio[absoluto];
        if (nombre != null) salida.add(nombre);
      }
    }
    return salida.toList()..sort();
  }

  Stream<File> _manifiestos(Directory d) async* {
    await for (final e in d.list(followLinks: false)) {
      final nombre = rutas.basename(e.path);
      if (_ignorados.contains(nombre)) continue;
      if (e is Directory) {
        yield* _manifiestos(e);
      } else if (e is File && nombre == 'pubspec.yaml') {
        yield e;
      }
    }
  }

  String _relativo(String absoluto) {
    final r = rutas.relative(absoluto, from: rutas.canonicalize(raiz.path));
    return r == '.' ? '.' : r.replaceAll(r'\', '/');
  }
}

/// Un manifiesto que no se pudo leer detiene la topología.
///
/// ADR-011, corolario 1: **un archivo ilegible es un diagnóstico, nunca un
/// salto silencioso.**
class TopologiaIlegible implements Exception {
  final String ruta;
  final Object causa;

  const TopologiaIlegible(this.ruta, this.causa);

  @override
  String toString() =>
      'TopologiaIlegible($ruta): $causa. Un manifiesto ilegible haría la '
      'topología más chica, y eso se lee igual que un proyecto con menos '
      'paquetes.';
}
