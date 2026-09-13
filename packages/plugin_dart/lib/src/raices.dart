/// Qué raíces de resolución toca una rebanada.
///
/// **Se deriva una vez por cada raíz que la rebanada toca, y ninguna más.** Un
/// manifiesto que la rebanada no toca no existe para ella: los fixtures de este
/// repositorio no bloquean un cambio en `packages/`.
///
/// «Derivar todas las raíces» parece la salida obvia y se midió: resolver el
/// fixture de Flutter **funciona en esta máquina**, porque acá la herramienta
/// vive dentro del SDK de Flutter y `sdk: flutter` resuelve. En el runner, con
/// un SDK puro, fallaría. Es exactamente la premisa que pasa en una máquina y
/// rompe en otra, y derivar raíces que nadie necesita es pagar ese riesgo por
/// nada.
///
/// **Función pura sobre rutas y manifiestos**: no corre ninguna herramienta. Es
/// lo que permite que la prueba fije la forma exacta de este repositorio sin
/// depender de dónde vive la toolchain en la máquina que la corre.
library;

import 'dart:io';

import 'package:path/path.dart' as rutas;
import 'package:yaml/yaml.dart';

/// Las raíces de resolución de [archivos], relativas a [candidateRoot] —`'.'`
/// para la raíz—, ordenadas y sin repetir.
///
/// La regla: cada archivo va a su manifiesto más cercano hacia arriba; si ese
/// paquete se declara miembro de un workspace, la raíz es el ancestro más
/// cercano que lo liste; si no, el paquete mismo. Un archivo **sin ningún
/// manifiesto hacia arriba no aporta raíz**, y si ninguno lo tiene el resultado
/// es vacío: no hay nada que derivar, y el observador de alcance ya va a decir
/// que nada es de este stack.
List<String> raicesDeResolucion(String candidateRoot, List<String> archivos) {
  final raiz = rutas.canonicalize(candidateRoot);
  final salida = <String>{};
  for (final archivo in archivos) {
    final absoluto = rutas.canonicalize(rutas.join(raiz, archivo));
    if (!rutas.isWithin(raiz, absoluto)) {
      throw ArgumentError.value(
        archivo,
        'archivos',
        'Está fuera del candidato. La rebanada solo puede tocar lo que el '
            'candidato contiene.',
      );
    }
    final paquete = _manifiestoMasCercano(rutas.dirname(absoluto), raiz);
    if (paquete == null) continue;
    salida.add(_relativa(_raizDe(paquete, raiz), raiz));
  }
  return salida.toList()..sort();
}

/// El directorio del manifiesto más cercano, subiendo hasta [raiz] inclusive;
/// nulo si no hay ninguno.
String? _manifiestoMasCercano(String desde, String raiz) {
  var dir = desde;
  while (true) {
    if (File(rutas.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    if (rutas.equals(dir, raiz)) return null;
    dir = rutas.dirname(dir);
  }
}

/// La raíz de resolución de un paquete.
///
/// **Cuando no se puede saber, el paquete mismo.** Un manifiesto ilegible o un
/// miembro que nadie lista caen acá, y eso no es adivinar: es dejar que la
/// herramienta que resuelve produzca la evidencia del defecto con su propio
/// mensaje, en vez de que este archivo decida por ella.
String _raizDe(String paquete, String raiz) {
  if (!_esMiembroDeUnWorkspace(paquete)) return paquete;
  var dir = paquete;
  while (!rutas.equals(dir, raiz)) {
    dir = rutas.dirname(dir);
    final miembros = _miembrosDe(dir);
    if (miembros == null) continue;
    final buscado = rutas.canonicalize(paquete);
    if (miembros.any(
      (m) => rutas.equals(rutas.canonicalize(rutas.join(dir, m)), buscado),
    )) {
      return dir;
    }
  }
  return paquete;
}

/// El manifiesto de un directorio, o nulo si no está o no se puede leer.
Map<Object?, Object?>? _manifiesto(String dir) {
  try {
    final doc = loadYaml(
      File(rutas.join(dir, 'pubspec.yaml')).readAsStringSync(),
    );
    return doc is Map ? doc : null;
  } on Object {
    return null;
  }
}

bool _esMiembroDeUnWorkspace(String paquete) =>
    _manifiesto(paquete)?['resolution'] == 'workspace';

/// La lista de miembros de un manifiesto, o nulo si no declara ninguna.
List<String>? _miembrosDe(String dir) {
  final declarados = _manifiesto(dir)?['workspace'];
  if (declarados is! List) return null;
  return [
    for (final m in declarados)
      if (m is String) m,
  ];
}

String _relativa(String absoluto, String raiz) {
  final r = rutas.relative(absoluto, from: raiz);
  return r == '.' ? '.' : r.replaceAll(r'\', '/');
}
