/// La frontera del módulo de comandos, `packages/cli/lib/src/command`: el
/// modelo sólo depende del barril de core; el resto del módulo, del propio
/// módulo, de ese barril y de `src/terminal_text.dart`, que no tiene
/// dependencias; y nada de eso forma un ciclo.
///
/// Lo invoca `check.dart`. Mira sólo el módulo y su helper de texto; quién
/// consume el módulo y el resto del CLI quedan fuera. Los mapas de imports de
/// las pruebas del CLI fijan las directivas de los consumidores escritas con
/// comillas simples y sin alternativas; otras formas no las ve ninguno de los
/// dos.
///
/// El universo es el disco, como en `bibliotecas_core.dart`: un archivo nuevo
/// del módulo se mira aunque nadie lo importe, y la enumeración del analizador
/// sólo contrasta.
library;

import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';

import 'directivas.dart';

typedef VerificacionDeComandos = ({List<String> fallos, String resumen});

/// Fijados acá y no en `arquitectura.json`: un campo del registro se podría
/// vaciar sin que nada lo notara, y cambiar un rol es cambiar el verificador.
const modeloDeComandos = 'src/command/cli_command.dart';
const rolesDeComandos = {
  modeloDeComandos,
  'src/command/cli_parser.dart',
  'src/command/cli_grammar.dart',
  'src/command/assessment_grammar.dart',
  'src/command/basis_grammar.dart',
};
const textoDeTerminal = 'src/terminal_text.dart';
const barrilDeCore = 'package:core/core.dart';

const _prefijo = 'comandos de cli: ';
const _modulo = 'src/command';
const _carpeta = 'packages/cli/lib/src/command';

/// [lib] es `packages/cli/lib`.
VerificacionDeComandos verificarComandosDeCli(
  Directory lib, {
  bool detalle = false,
}) {
  final fallos = <String>[];
  void falla(String mensaje) => fallos.add('$_prefijo$mensaje');
  final relativa = relativizador(lib);
  final modulo = Directory('${lib.path}/$_modulo');

  final universo = SplayTreeSet<String>();
  final tipo = FileSystemEntity.typeSync(modulo.path, followLinks: false);
  if (tipo == FileSystemEntityType.link) {
    falla(
      'cobertura insuficiente: $_modulo es un enlace simbólico. No se sigue '
      'ni se adivina su destino.',
    );
    return (fallos: fallos, resumen: '');
  }
  if (tipo == FileSystemEntityType.directory) {
    try {
      for (final entrada in modulo.listSync(
        recursive: true,
        followLinks: false,
      )) {
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
      falla('no pude enumerar $_carpeta: ${e.message} (${e.path}).');
    }
  }
  if (universo.isEmpty) {
    falla(
      'inventario vacío en $_carpeta. Cero archivos mirados no es «sin '
      'dependencias»: es no haber mirado.',
    );
    return (fallos: fallos, resumen: '');
  }

  final porAnalizador = <String>{
    for (final contexto in AnalysisContextCollection(
      includedPaths: [normalizada(modulo.absolute.path)],
    ).contexts)
      for (final f in contexto.contextRoot.analyzedFiles())
        if (f.endsWith('.dart')) relativa(f),
  };
  contrastar('el analizador', _carpeta, porAnalizador, universo, falla);

  for (final rol in rolesDeComandos) {
    if (!universo.contains(rol)) {
      falla(
        'falta el rol $rol. Una frontera que salta lo que no encuentra no '
        'verifica nada.',
      );
    }
  }
  final nodos = SplayTreeSet<String>.of(universo);
  switch (FileSystemEntity.typeSync(
    '${lib.path}/$textoDeTerminal',
    followLinks: false,
  )) {
    case FileSystemEntityType.file:
      nodos.add(textoDeTerminal);
    case FileSystemEntityType.link:
      falla(
        'cobertura insuficiente: $textoDeTerminal es un enlace simbólico. '
        'No se sigue ni se adivina su destino.',
      );
    default:
      falla('falta $textoDeTerminal.');
  }

  final raiz = normalizada(lib.absolute.path);
  final aristas = <Arista>[];
  final parseados = <String>{};
  var haciaCore = 0;
  for (final rel in nodos) {
    parseados.add(rel);
    for (final (literal, clase) in directivasDe(lib, rel, falla)) {
      final uri = literal.stringValue;
      // Se clasifica la URI ya parseada, no el texto escrito:
      // `package:c%6Ci/...` es cli y `DART:io` es del SDK.
      final escrita = uri == null ? null : Uri.tryParse(uri);
      if (uri == null) {
        falla('URI no literal: $rel tiene `${literal.toSource()}` ($clase).');
        continue;
      }
      if (escrita == null || paqueteIlegible(escrita)) {
        falla(
          'URI no válida: $rel tiene «$uri» ($clase). No se puede decir a '
          'qué archivo apunta.',
        );
        continue;
      }
      if (rel == textoDeTerminal) {
        falla(
          '$textoDeTerminal no puede tener directivas de dependencia: tiene '
          '«$uri» ($clase).',
        );
        continue;
      }
      final String destino;
      final String? razon;
      var esCore = false;
      if (escrita.isScheme('dart')) {
        (destino, razon) = (uri, 'el SDK');
      } else if (escrita.isScheme('package') &&
          escrita.pathSegments.first != 'cli') {
        final paquete = escrita.pathSegments.first;
        esCore =
            paquete == 'core' &&
            escrita.pathSegments.length == 2 &&
            escrita.pathSegments.last == 'core.dart';
        destino = uri;
        razon = esCore
            ? null
            : paquete == 'core'
            ? 'core fuera de su barril'
            : 'otro paquete';
      } else {
        final local = resolverDentro(raiz, rel, escrita);
        if (local == null ||
            !(nodos.contains(local) || File('$raiz/$local').existsSync())) {
          falla(
            'destino inexistente dentro de packages/cli/lib: $rel → «$uri» '
            '($clase).',
          );
          continue;
        }
        if (nodos.contains(local)) aristas.add(Arista(rel, local, clase));
        destino = local;
        razon = universo.contains(local) || local == textoDeTerminal
            ? null
            : local == 'cli.dart'
            ? 'el barril de cli'
            : 'cli fuera del módulo';
      }
      if (esCore) haciaCore++;
      if (rel == modeloDeComandos && !esCore) {
        falla(
          'el modelo sólo depende de $barrilDeCore: $rel → $destino ($clase).',
        );
      } else if (rel != modeloDeComandos && razon != null) {
        falla('destino no admitido: $rel → $destino ($clase): $razon.');
      }
    }
  }
  final sinParsear = nodos.difference(parseados).toList();
  if (sinParsear.isNotEmpty) {
    falla(
      'cobertura insuficiente: parseados ≠ universo. Quedaron sin parsear '
      '${sinParsear.join(', ')}.',
    );
  }

  for (final componente in componentesCiclicos(nodos, aristas)) {
    final internas = aristas.where(
      (a) => componente.contains(a.origen) && componente.contains(a.destino),
    );
    falla(
      'componente cíclico: ${componente.join(', ')} — aristas internas: '
      '${internas.join('; ')}.',
    );
  }
  if (universo.contains(modeloDeComandos)) {
    final alcanzados = alcanzables(modeloDeComandos, aristas);
    for (final x in universo.where(alcanzados.contains)) {
      if (x != modeloDeComandos) falla('el modelo alcanza $x.');
    }
  }

  final alternativas = aristas
      .where((a) => a.clase.startsWith('alternativa'))
      .length;
  final exports = aristas.where((a) => a.clase == 'export').length;
  final resumen = StringBuffer(
    '${_prefijo}ok — ${parseados.length} archivos parseados '
    '(${universo.length} en $_modulo por recorrido físico, igual al del '
    'analizador, y $textoDeTerminal), ${aristas.length} aristas locales '
    '(${aristas.length - exports - alternativas} import, $exports export, '
    '$alternativas alternativas), $haciaCore hacia $barrilDeCore, 0 '
    'componentes cíclicos, ${rolesDeComandos.length} roles presentes.',
  );
  if (detalle) {
    for (final rel in nodos) {
      resumen.write('\n  archivo: $rel');
    }
    for (final a in aristas) {
      resumen.write('\n  arista: $a');
    }
  }
  return (fallos: fallos, resumen: resumen.toString());
}
