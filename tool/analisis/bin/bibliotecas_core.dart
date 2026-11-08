/// Las bibliotecas de `packages/core/lib` como grafo de directivas: sin
/// componentes cíclicos, sin `src/` apuntando al barril, y con las hojas de
/// valores de basis lejos del modelo que las contiene.
///
/// Lo invoca `check.dart`; no es un ejecutable propio. Vive en `bin/` junto a
/// los demás verificadores por coherencia, no porque el grafo lo exija.
///
/// POR QUÉ EL UNIVERSO ES EL DISCO Y NO UNA LISTA
///     Las dos enumeraciones que ya existían —`fuentes()` de check.dart y la
///     del analizador— omiten LAS DOS una carpeta `.dart_tool` dentro de
///     `lib/`: compararlas entre sí da igual aunque un ciclo viva ahí. El
///     universo es el recorrido físico sin filtros; esas dos solo contrastan,
///     y cualquier diferencia es rojo. Un archivo que no se pudo mirar no es
///     un archivo sin ciclos.
library;

import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

typedef VerificacionDeBibliotecas = ({List<String> fallos, String resumen});

/// Los valores que payloads y registros comparten. Fijadas acá y no en
/// `arquitectura.json`: un campo del registro se podría vaciar sin que nada
/// lo notara, y cambiar esta lista es cambiar el verificador.
const hojasDeBasis = {
  'src/basis/basis_scope.dart',
  'src/basis/basis_actor.dart',
  'src/basis/basis_links.dart',
};

/// Lo que una hoja no puede alcanzar, ni directa ni transitivamente.
const altoNivelDeBasis = {
  'src/basis/basis_model.dart',
  'src/basis/basis_payload.dart',
  'src/basis/basis_history.dart',
  'core.dart',
};

const _prefijo = 'bibliotecas de core: ';
const _barril = 'core.dart';

final class _Arista {
  const _Arista(this.origen, this.destino, this.clase);

  final String origen;
  final String destino;

  /// `import`, `export`, `alternativa de import` o `alternativa de export`.
  final String clase;

  @override
  String toString() => '$origen → $destino ($clase)';
}

/// [fuentesDeCheck] es la enumeración que check.dart ya hace de core/lib. Solo
/// se contrasta contra el universo: no decide qué se mira.
VerificacionDeBibliotecas verificarBibliotecasDeCore(
  Directory lib,
  List<File> fuentesDeCheck, {
  bool detalle = false,
}) {
  final fallos = <String>[];
  void falla(String mensaje) => fallos.add('$_prefijo$mensaje');
  final relativa = _relativizador(lib);

  final universo = SplayTreeSet<String>();
  try {
    for (final entrada in lib.listSync(recursive: true, followLinks: false)) {
      if (entrada is Link) {
        falla(
          'cobertura insuficiente: ${relativa(entrada.path)} es un enlace '
          'simbólico. No se sigue ni se adivina su destino.',
        );
      } else if (entrada is File && entrada.path.endsWith('.dart')) {
        universo.add(relativa(entrada.path));
      }
    }
  } on FileSystemException catch (e) {
    falla('no pude enumerar packages/core/lib: ${e.message} (${e.path}).');
  }
  if (universo.isEmpty) {
    falla(
      'inventario vacío en packages/core/lib. Cero archivos mirados no es '
      '«sin ciclos»: es no haber mirado.',
    );
    return (fallos: fallos, resumen: '');
  }

  final porAnalizador = <String>{
    for (final contexto in AnalysisContextCollection(
      includedPaths: [_normal(lib.absolute.path)],
    ).contexts)
      for (final f in contexto.contextRoot.analyzedFiles())
        if (f.endsWith('.dart')) relativa(f),
  };
  _contrastar(
    'la enumeración de check.dart',
    {for (final f in fuentesDeCheck) relativa(f.path)},
    universo,
    falla,
  );
  _contrastar('el analizador', porAnalizador, universo, falla);

  final aristas = <_Arista>[];
  final externos = <String>[];
  var haciaSdk = 0;
  final parseados = <String>{};
  for (final rel in universo) {
    parseados.add(rel);
    final directivas = _directivas(lib, rel, falla);
    for (final (literal, clase) in directivas) {
      final uri = literal.stringValue;
      if (uri == null) {
        falla('URI no literal: $rel tiene `${literal.toSource()}` ($clase).');
      } else if (uri.startsWith('dart:')) {
        haciaSdk++;
      } else if (uri.startsWith('package:') &&
          !uri.startsWith('package:core/')) {
        externos.add(uri);
      } else {
        final destino = _resolver(rel, uri);
        if (destino == null || !universo.contains(destino)) {
          falla(
            'destino inexistente dentro de packages/core/lib: $rel → «$uri» '
            '($clase).',
          );
          continue;
        }
        if (rel.startsWith('src/') && destino == _barril) {
          falla('importa o exporta el barril: $rel («$uri», $clase).');
        }
        aristas.add(_Arista(rel, destino, clase));
      }
    }
  }
  final sinParsear = universo.difference(parseados).toList();
  if (sinParsear.isNotEmpty) {
    falla(
      'cobertura insuficiente: parseados ≠ universo. Quedaron sin parsear '
      '${sinParsear.join(', ')}.',
    );
  }

  final ciclicos = _componentesCiclicos(universo, aristas);
  for (final componente in ciclicos) {
    final internas = aristas.where(
      (a) => componente.contains(a.origen) && componente.contains(a.destino),
    );
    falla(
      'componente cíclico: ${componente.join(', ')} — aristas internas: '
      '${internas.join('; ')}.',
    );
  }

  for (final hoja in hojasDeBasis) {
    if (!universo.contains(hoja)) {
      falla(
        'falta la hoja $hoja. Una regla que salta lo que no encuentra no '
        'verifica nada.',
      );
      continue;
    }
    final alcanzadas = _alcanzables(hoja, aristas);
    for (final x in altoNivelDeBasis.where(alcanzadas.contains)) {
      falla('la hoja $hoja depende de $x.');
    }
  }

  final alternativas = aristas
      .where((a) => a.clase.startsWith('alternativa'))
      .length;
  final exports = aristas.where((a) => a.clase == 'export').length;
  final resumen = StringBuffer(
    '${_prefijo}ok — ${parseados.length} archivos parseados (recorrido '
    'físico, igual a la enumeración de check.dart y a la del analizador), '
    '${aristas.length} aristas locales '
    '(${aristas.length - exports - alternativas} import, $exports export, '
    '$alternativas alternativas), $haciaSdk hacia el SDK, '
    '${externos.length} hacia otros paquetes, 0 componentes cíclicos, '
    '${hojasDeBasis.length} hojas sin dependencias de alto nivel.',
  );
  if (detalle) {
    for (final rel in universo) {
      resumen.write('\n  archivo: $rel');
    }
    for (final a in aristas) {
      resumen.write('\n  arista: $a');
    }
  }
  return (fallos: fallos, resumen: resumen.toString());
}

/// Las directivas de un archivo, cada URI con su clase. Un archivo que no se
/// lee o no parsea falla con nombre: de un árbol parcial no sale ninguna
/// arista, y eso se leería igual que «no importa nada».
List<(StringLiteral, String)> _directivas(
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

/// Relativo a `lib/`, o null si el URI se sale de ahí.
String? _resolver(String rel, String uri) {
  if (uri.startsWith('package:core/')) {
    return uri.substring('package:core/'.length);
  }
  final ruta = Uri.parse('file:///lib/$rel').resolve(uri).path;
  return ruta.startsWith('/lib/') ? ruta.substring('/lib/'.length) : null;
}

void _contrastar(
  String quien,
  Set<String> vistos,
  Set<String> universo,
  void Function(String) falla,
) {
  final omite = universo.difference(vistos).toList()..sort();
  final agrega = vistos.difference(universo).toList()..sort();
  if (omite.isNotEmpty) {
    falla(
      'cobertura insuficiente: $quien omite ${omite.join(', ')}, que existen '
      'en packages/core/lib.',
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
String Function(String) _relativizador(Directory lib) {
  final bases = {
    _normal(lib.path),
    _normal(lib.absolute.path),
    if (lib.existsSync()) _normal(lib.resolveSymbolicLinksSync()),
  };
  return (ruta) {
    final normal = _normal(ruta);
    for (final base in bases) {
      if (normal.startsWith('$base/')) return normal.substring(base.length + 1);
    }
    return normal;
  };
}

String _normal(String ruta) =>
    Uri.file(ruta).normalizePath().toFilePath().replaceAll(r'\', '/');

/// Tarjan. Un componente de un solo nodo cuenta si tiene un lazo propio.
List<List<String>> _componentesCiclicos(
  Iterable<String> nodos,
  List<_Arista> aristas,
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

Set<String> _alcanzables(String desde, List<_Arista> aristas) {
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
