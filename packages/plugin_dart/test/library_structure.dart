import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Las carpetas de `lib/src`, cada una con lo que puede importar del paquete.
/// `observation` sólo tiene elementos de observación compartidos; el
/// reconocimiento y assess dependen de ella y nunca entre sí.
const allowedAreas = {
  'observation': {'observation'},
  'recognition': {'recognition', 'observation'},
  'assessment': {'assessment', 'observation'},
};

/// Lo que se comprobó y lo que está mal. Sin archivos o sin aristas no hay
/// verde: no haber mirado nada no es una estructura sana.
final class StructureReport {
  StructureReport(this.files, this.edges, this.faults);

  final int files;
  final int edges;
  final List<String> faults;
}

/// Las directivas de cada biblioteca de [lib], leídas con su árbol sintáctico,
/// contra las reglas de estructura del paquete [package].
StructureReport checkLibraryStructure(
  Directory lib, {
  String package = 'plugin_dart',
}) {
  final sources = _sources(lib);
  final faults = <String>[];
  if (sources.isEmpty) {
    faults.add('inventario vacío: no hay bibliotecas bajo ${lib.path}');
  }
  final graph = <String, Set<String>>{};
  for (final MapEntry(key: path, value: text) in sources.entries) {
    graph[path] = _targets(path, text, package, sources.keys.toSet(), faults);
  }
  _checkAreas(graph, faults);
  _checkCycles(graph, faults);
  final edges = graph.values.fold(0, (n, t) => n + t.length);
  if (sources.isNotEmpty && edges == 0) {
    faults.add('ninguna arista: no se miró nada');
  }
  return StructureReport(sources.length, edges, faults);
}

Map<String, String> _sources(Directory lib) => {
  if (lib.existsSync())
    for (final f in lib.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart'))
        f.path.substring(lib.path.length + 1): f.readAsStringSync(),
};

/// Los destinos locales de [path]: imports, exports y cada alternativa
/// condicional. Un `part`, un error de parseo o un destino que no existe son
/// fallos: ocultan una frontera o impiden comprobarla.
Set<String> _targets(
  String path,
  String text,
  String package,
  Set<String> known,
  List<String> faults,
) {
  final parsed = parseString(
    content: text,
    path: path,
    throwIfDiagnostics: false,
  );
  for (final e in parsed.errors) {
    faults.add('$path: no se pudo parsear (${e.message})');
  }
  final found = <String>{};
  for (final d in parsed.unit.directives) {
    if (d is PartDirective || d is PartOfDirective) {
      faults.add(
        '$path: usa part/part of, que oculta la frontera entre bibliotecas',
      );
    }
    if (d is! NamespaceDirective) continue;
    final uris = [
      d.uri.stringValue,
      for (final c in d.configurations) c.uri.stringValue,
    ];
    for (final uri in uris) {
      _addTarget(found, path, uri, package, known, faults);
    }
  }
  return found;
}

void _addTarget(
  Set<String> found,
  String path,
  String? uri,
  String package,
  Set<String> known,
  List<String> faults,
) {
  final target = _resolve(path, uri, package, faults);
  if (target == null) return;
  if (known.contains(target)) {
    found.add(target);
  } else {
    faults.add('$path: el destino «$uri» no existe en lib');
  }
}

/// La ruta relativa a lib de [uri], o null si no es de este paquete.
String? _resolve(
  String from,
  String? uri,
  String package,
  List<String> faults,
) {
  if (uri == null) {
    faults.add('$from: una directiva sin URI literal no se puede comprobar');
    return null;
  }
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final prefix = 'package:$package/';
    return uri.startsWith(prefix) ? uri.substring(prefix.length) : null;
  }
  final parts = [...from.split('/')..removeLast(), ...uri.split('/')];
  final out = <String>[];
  for (final p in parts) {
    if (p == '..') {
      if (out.isEmpty) return '../$uri';
      out.removeLast();
    } else if (p != '.') {
      out.add(p);
    }
  }
  return out.join('/');
}

/// La carpeta de [path] bajo `src/`, '' para lo que está fuera de `src/` (el
/// barrel), o null si está en `src/` pero fuera de las carpetas permitidas.
String? _areaOf(String path) {
  if (!path.startsWith('src/')) return '';
  final segments = path.split('/');
  if (segments.length < 3) return null;
  return allowedAreas.containsKey(segments[1]) ? segments[1] : null;
}

void _checkAreas(Map<String, Set<String>> graph, List<String> faults) {
  for (final MapEntry(key: from, value: targets) in graph.entries) {
    final area = _areaOf(from);
    if (area == null) {
      faults.add('$from: fuera de recognition/, assessment/ y observation/');
      continue;
    }
    if (area.isEmpty) continue;
    for (final to in targets) {
      final target = _areaOf(to);
      if (target == '') {
        faults.add('$from: importa el barrel público $to');
      } else if (target != null && !allowedAreas[area]!.contains(target)) {
        faults.add('dirección prohibida: $area → $target ($from importa $to)');
      }
    }
  }
}

/// Cada componente fuertemente conexo de más de un archivo, o un archivo que
/// se importa a sí mismo, es un ciclo.
void _checkCycles(Map<String, Set<String>> graph, List<String> faults) {
  for (final component in _Components(graph).cyclic()) {
    faults.add('componente cíclico: ${component.join(', ')}');
  }
}

/// Los componentes fuertemente conexos de un grafo (Tarjan).
final class _Components {
  _Components(this.graph);

  final Map<String, Set<String>> graph;
  final _index = <String, int>{};
  final _low = <String, int>{};
  final _stack = <String>[];
  final _onStack = <String>{};
  final _cyclic = <List<String>>[];

  List<List<String>> cyclic() {
    for (final v in graph.keys.toList()..sort()) {
      if (!_index.containsKey(v)) _visit(v);
    }
    return _cyclic;
  }

  void _visit(String v) {
    _index[v] = _low[v] = _index.length;
    _stack.add(v);
    _onStack.add(v);
    for (final w in graph[v] ?? const <String>{}) {
      if (!_index.containsKey(w)) {
        _visit(w);
        _low[v] = _min(_low[v]!, _low[w]!);
      } else if (_onStack.contains(w)) {
        _low[v] = _min(_low[v]!, _index[w]!);
      }
    }
    if (_low[v] == _index[v]) _close(v);
  }

  void _close(String v) {
    final component = <String>[];
    String w;
    do {
      w = _stack.removeLast();
      _onStack.remove(w);
      component.add(w);
    } while (w != v);
    if (component.length > 1 || (graph[v]?.contains(v) ?? false)) {
      _cyclic.add(component..sort());
    }
  }

  static int _min(int a, int b) => a < b ? a : b;
}
