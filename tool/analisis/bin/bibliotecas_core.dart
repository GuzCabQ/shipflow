/// Las bibliotecas de `packages/core/lib` como grafo de directivas: sin
/// componentes cíclicos, sin `src/` apuntando al barril, y con las hojas de
/// valores de basis lejos del modelo que las contiene.
///
/// Lo invoca `check.dart`; no es un ejecutable propio. Vive en `bin/` junto a
/// los demás verificadores por coherencia, no porque el grafo lo exija.
///
/// POR QUÉ EL UNIVERSO ES EL DISCO Y NO UNA LISTA
///     La enumeración de `fuentes()` en check.dart y la del analizador
///     omiten LAS DOS una carpeta `.dart_tool` dentro de `lib/`: compararlas
///     entre sí da igual aunque un ciclo viva ahí. El universo es el
///     recorrido físico sin filtros; esas dos solo contrastan,
///     y cualquier diferencia es rojo. Un archivo que no se pudo mirar no es
///     un archivo sin ciclos.
library;

import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';

import 'directivas.dart';

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

/// [fuentesDeCheck] es la enumeración que check.dart ya hace de core/lib. Solo
/// se contrasta contra el universo: no decide qué se mira.
VerificacionDeBibliotecas verificarBibliotecasDeCore(
  Directory lib,
  List<File> fuentesDeCheck, {
  bool detalle = false,
}) {
  final fallos = <String>[];
  void falla(String mensaje) => fallos.add('$_prefijo$mensaje');
  final relativa = relativizador(lib);

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
      includedPaths: [normalizada(lib.absolute.path)],
    ).contexts)
      for (final f in contexto.contextRoot.analyzedFiles())
        if (f.endsWith('.dart')) relativa(f),
  };
  contrastar(
    'la enumeración de check.dart',
    'packages/core/lib',
    {for (final f in fuentesDeCheck) relativa(f.path)},
    universo,
    falla,
  );
  contrastar(
    'el analizador',
    'packages/core/lib',
    porAnalizador,
    universo,
    falla,
  );

  final aristas = <Arista>[];
  final externos = <String>[];
  var haciaSdk = 0;
  final parseados = <String>{};
  final raiz = normalizada(lib.absolute.path);
  for (final rel in universo) {
    parseados.add(rel);
    final directivas = directivasDe(lib, rel, falla);
    for (final (literal, clase) in directivas) {
      final uri = literal.stringValue;
      // Se clasifica la URI ya parseada, no el texto escrito: `DART:io` es
      // del SDK y `package:c%6Fre/...` es core.
      final escrita = uri == null ? null : Uri.tryParse(uri);
      if (uri == null) {
        falla('URI no literal: $rel tiene `${literal.toSource()}` ($clase).');
      } else if (escrita == null || paqueteIlegible(escrita)) {
        falla(
          'URI no válida: $rel tiene «$uri» ($clase). No se puede decir a qué '
          'archivo apunta.',
        );
      } else if (escrita.isScheme('dart')) {
        haciaSdk++;
      } else if (escrita.isScheme('package') &&
          escrita.pathSegments.first != 'core') {
        externos.add(uri);
      } else {
        final destino = resolverDentro(raiz, rel, escrita);
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
        aristas.add(Arista(rel, destino, clase));
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

  final ciclicos = componentesCiclicos(universo, aristas);
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
    final alcanzadas = alcanzables(hoja, aristas);
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
