/// La dirección de la composición de `packages/cli/lib`: el despacho de
/// comandos sólo lo alcanzan el barril y la frontera del proceso, y la
/// frontera sólo el barril. Ningún adapter, helper ni archivo nuevo puede
/// llegar a ellos, ni directamente ni a través de otros archivos.
///
/// El contexto de init y refresh tiene la misma dirección: el servicio compone
/// la sesión y el publicador; la sesión no alcanza el servicio; el publicador
/// no alcanza sesión ni servicio; y el desenlace, que ambos consumen, no
/// alcanza a ninguno de los tres.
///
/// Lo invoca `check.dart`. No prohíbe los ciclos del CLI ni gobierna qué
/// importa cada archivo: sólo quién alcanza esos destinos. Las dependencias
/// hacia el SDK y otros paquetes se cuentan y no se recorren; las gobiernan
/// las reglas del workspace.
///
/// El universo es el disco de `lib`, como en `bibliotecas_core.dart`: un
/// archivo nuevo se mira aunque nadie lo importe, y la enumeración del
/// analizador sólo contrasta. Como el analizador no enumera las carpetas
/// ocultas, un `.dart` dentro de una siempre sale rojo.
library;

import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';

import 'directivas.dart';

typedef VerificacionDeComposicion = ({List<String> fallos, String resumen});

/// Fijados acá y no en `arquitectura.json`: un campo del registro se podría
/// vaciar sin que nada lo notara, y cambiar un rol es cambiar el verificador.
const barrilDeCli = 'cli.dart';
const despachoDeComandos = 'src/cli_runner.dart';
const fronteraDelProceso = 'src/cli_process_boundary.dart';
const reconocimientoDeRaiz = 'src/recognition_runner.dart';
const servicioDeContexto = 'src/context/context_service.dart';
const sesionDeContexto = 'src/context/context_init.dart';
const publicadorDeContexto = 'src/context/context_init_publication.dart';
const desenlaceDeContexto = 'src/context/context_publication_outcome.dart';
const rolesDeComposicion = {
  barrilDeCli,
  despachoDeComandos,
  fronteraDelProceso,
  reconocimientoDeRaiz,
  'src/context/context_cli.dart',
  'src/assessment/assessment_cli.dart',
  'src/basis/basis_cli.dart',
  servicioDeContexto,
  sesionDeContexto,
  publicadorDeContexto,
  desenlaceDeContexto,
};

/// Cada destino con los orígenes que no deben alcanzarlo, en uno o más saltos.
/// Son relaciones de dirección: la sesión y el publicador sí pueden alcanzar
/// el desenlace, y el servicio sí puede alcanzar a todos.
const prohibidosDeContexto = {
  servicioDeContexto: {
    sesionDeContexto,
    publicadorDeContexto,
    desenlaceDeContexto,
  },
  sesionDeContexto: {publicadorDeContexto, desenlaceDeContexto},
  publicadorDeContexto: {desenlaceDeContexto},
};

/// Cada destino con los únicos orígenes que pueden alcanzarlo. Un destino
/// no está entre sus propios orígenes: volver a él por un ciclo es rojo.
const origenesAdmitidos = {
  despachoDeComandos: {barrilDeCli, fronteraDelProceso},
  fronteraDelProceso: {barrilDeCli},
};

const _prefijo = 'composición de cli: ';
const _carpeta = 'packages/cli/lib';

/// [lib] es `packages/cli/lib`.
VerificacionDeComposicion verificarComposicionDeCli(
  Directory lib, {
  bool detalle = false,
}) {
  final fallos = <String>[];
  void falla(String mensaje) => fallos.add('$_prefijo$mensaje');
  final relativa = relativizador(lib);

  if (FileSystemEntity.typeSync(lib.path, followLinks: false) ==
      FileSystemEntityType.link) {
    falla(
      'cobertura insuficiente: $_carpeta es un enlace simbólico. No se sigue '
      'ni se adivina su destino.',
    );
    return (fallos: fallos, resumen: '');
  }
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
    falla('no pude enumerar $_carpeta: ${e.message} (${e.path}).');
  }
  if (universo.isEmpty) {
    falla(
      'inventario vacío en $_carpeta. Cero archivos mirados no es «nadie '
      'alcanza la composición»: es no haber mirado.',
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
  contrastar('el analizador', _carpeta, porAnalizador, universo, falla);

  final faltan = rolesDeComposicion.where((r) => !universo.contains(r));
  for (final rol in faltan) {
    falla(
      'falta el rol $rol. Una frontera que salta lo que no encuentra no '
      'verifica nada.',
    );
  }

  final raiz = normalizada(lib.absolute.path);
  final aristas = <Arista>[];
  var haciaSdk = 0;
  var haciaPaquetes = 0;
  for (final rel in universo) {
    for (final (literal, clase) in directivasDe(lib, rel, falla)) {
      final uri = literal.stringValue;
      // Se clasifica la URI ya parseada, no el texto escrito:
      // `package:c%6Ci/...` es cli y `DART:io` es del SDK.
      final escrita = uri == null ? null : Uri.tryParse(uri);
      if (uri == null) {
        falla('URI no literal: $rel tiene `${literal.toSource()}` ($clase).');
      } else if (escrita == null || paqueteIlegible(escrita)) {
        falla(
          'URI no válida: $rel tiene «$uri» ($clase). No se puede decir a '
          'qué archivo apunta.',
        );
      } else if (escrita.isScheme('dart')) {
        haciaSdk++;
      } else if (escrita.isScheme('package') &&
          escrita.pathSegments.first != 'cli') {
        haciaPaquetes++;
      } else if (escrita.hasScheme && !escrita.isScheme('package')) {
        falla(
          'URI no clasificable: $rel tiene «$uri» ($clase). Sólo se admiten '
          '`dart:`, `package:` y rutas relativas.',
        );
      } else {
        final destino = resolverDentro(raiz, rel, escrita);
        if (destino == null || !universo.contains(destino)) {
          falla(
            'destino inexistente dentro de $_carpeta: $rel → «$uri» '
            '($clase).',
          );
        } else {
          aristas.add(Arista(rel, destino, clase));
        }
      }
    }
  }

  final inversas = [
    for (final a in aristas) Arista(a.destino, a.origen, a.clase),
  ];
  var incumplidas = 0;
  for (final MapEntry(key: destino, value: prohibidos)
      in prohibidosDeContexto.entries) {
    final origenes = alcanzables(destino, inversas);
    for (final origen in prohibidos.toList()..sort()) {
      if (!origenes.contains(origen)) continue;
      incumplidas++;
      falla(
        '$origen alcanza $destino, que no debe alcanzarlo: '
        '${_camino(origen, destino, aristas)}.',
      );
    }
  }
  final prohibiciones = prohibidosDeContexto.values.fold(
    0,
    (total, origenes) => total + origenes.length,
  );
  final alcanzadoPor = <String, Set<String>>{};
  for (final MapEntry(key: destino, value: admitidos)
      in origenesAdmitidos.entries) {
    final origenes = alcanzables(destino, inversas).toList()..sort();
    alcanzadoPor[destino] = origenes.toSet();
    for (final origen in origenes.where((o) => !admitidos.contains(o))) {
      falla(
        '$origen alcanza $destino, que sólo '
        '${admitidos.length == 1 ? 'puede' : 'pueden'} alcanzar '
        '${admitidos.join(' y ')}: ${_camino(origen, destino, aristas)}.',
      );
    }
  }

  final alternativas = aristas
      .where((a) => a.clase.startsWith('alternativa'))
      .length;
  final exports = aristas.where((a) => a.clase == 'export').length;
  final alcances = [
    for (final MapEntry(key: destino, value: origenes) in alcanzadoPor.entries)
      '$destino lo alcanza ${origenes.isEmpty ? 'nadie' : origenes.join(' y ')}',
  ];
  final resumen = StringBuffer(
    '${_prefijo}ok — ${universo.length} archivos parseados (recorrido '
    'físico de $_carpeta, igual al del analizador), ${aristas.length} '
    'aristas locales (${aristas.length - exports - alternativas} import, '
    '$exports export, $alternativas alternativas), $haciaSdk hacia el SDK '
    'y $haciaPaquetes hacia otros paquetes sin recorrer, '
    '${rolesDeComposicion.length} roles presentes; $prohibiciones '
    'prohibiciones de contexto verificadas, $incumplidas incumplidas; '
    '${alcances.join('; ')}.',
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

/// El camino más corto de [origen] a [destino], con la clase de cada salto.
/// Entre caminos iguales gana el de las directivas que aparecen antes.
String _camino(String origen, String destino, List<Arista> aristas) {
  final llegada = <String, Arista>{};
  final cola = Queue.of([origen]);
  while (cola.isNotEmpty) {
    final v = cola.removeFirst();
    for (final a in aristas.where((a) => a.origen == v)) {
      if (llegada.containsKey(a.destino)) continue;
      llegada[a.destino] = a;
      if (a.destino == destino) {
        final saltos = [a];
        while (saltos.last.origen != origen) {
          saltos.add(llegada[saltos.last.origen]!);
        }
        return [
          origen,
          for (final s in saltos.reversed) '${s.destino} (${s.clase})',
        ].join(' → ');
      }
      cola.add(a.destino);
    }
  }
  return 'sin camino';
}
