import 'dart:io';

import 'package:core/core.dart';
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
///     La lección de `capas.py` igual se aplica, y es la que importa: el
///     manifiesto se le pide a un PARSER de YAML, no a una expresión regular.
class TopologiaDart implements ProjectTopology {
  /// Raíz del proyecto que se analiza. **No es el nuestro**: es el del usuario.
  final Directory raiz;

  /// `N1-03`: artefactos de build. No son fuente y no contienen paquetes.
  static const _ignorados = {'.dart_tool', 'build', '.git'};

  TopologiaDart(this.raiz);

  @override
  Future<List<Package>> packages() async {
    final encontrados = <Package>[];
    await for (final manifiesto in _manifiestos(raiz)) {
      final texto = await manifiesto.readAsString();
      final YamlMap doc;
      try {
        final cargado = loadYaml(texto);
        if (cargado is! YamlMap) {
          throw const FormatException('el manifiesto no es un mapa');
        }
        doc = cargado;
      } on Exception catch (e) {
        // Un manifiesto ilegible NO se saltea. Saltarlo haría la topología más
        // chica, y una topología más chica se lee igual que un proyecto con
        // menos paquetes: es la clase 1 exacta.
        throw TopologiaIlegible(manifiesto.path, e);
      }
      final nombre = doc['name'];
      if (nombre is! String || nombre.isEmpty) {
        throw TopologiaIlegible(
            manifiesto.path, const FormatException('sin `name`'));
      }
      encontrados.add(Package(
        name: nombre,
        path: _relativo(manifiesto.parent.path),
        dependsOn: _dependenciasLocales(doc),
      ));
    }
    encontrados.sort((a, b) => a.name.compareTo(b.name));
    return encontrados;
  }

  /// Solo las dependencias hacia OTRO paquete del mismo proyecto. Las externas
  /// no son topología: son resolución, y eso es `DependencyResolver`.
  List<String> _dependenciasLocales(YamlMap doc) {
    final salida = <String>[];
    for (final clave in const ['dependencies', 'dev_dependencies']) {
      final seccion = doc[clave];
      if (seccion is! YamlMap) continue;
      for (final entrada in seccion.entries) {
        final valor = entrada.value;
        if (valor is YamlMap && valor.containsKey('path')) {
          salida.add(entrada.key as String);
        }
      }
    }
    salida.sort();
    return salida;
  }

  Stream<File> _manifiestos(Directory d) async* {
    await for (final e in d.list(followLinks: false)) {
      final nombre = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (_ignorados.contains(nombre)) continue;
      if (e is Directory) {
        yield* _manifiestos(e);
      } else if (e is File && nombre == 'pubspec.yaml') {
        yield e;
      }
    }
  }

  String _relativo(String absoluto) {
    final base = raiz.absolute.path;
    if (!absoluto.startsWith(base)) return absoluto;
    final r = absoluto.substring(base.length).replaceAll(r'\', '/');
    return r.startsWith('/') ? r.substring(1) : (r.isEmpty ? '.' : r);
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
