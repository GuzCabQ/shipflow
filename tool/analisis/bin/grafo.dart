/// Genera el grafo interno del repositorio. **Se deriva, no se mantiene.**
///
///     cd tool/analisis
///     dart run bin/grafo.dart            # compara contra el commiteado
///     dart run bin/grafo.dart --escribir # lo regenera
///
/// Sale 1 si el commiteado no coincide con el derivado del árbol.
///
/// POR QUÉ SE COMPARA EN VEZ DE CONFIAR
///     Un mapa desactualizado es peor que no tenerlo: las reglas derivadas de
///     él pasan a ser mentira con aspecto de evidencia. Como el grafo se
///     regenera entero, no hay nada que actualizar a mano — y por lo tanto no
///     hay nada que saltarse.
///
/// CRITERIO DE ADMISIÓN (GRAFO §1)
///     Cada campo tiene que poder nombrar la pregunta de §2 que responde. Dos
///     campos del esquema propuesto NO entran todavía:
///
///       `hash` y `aristas[].hash_destino` responden Q4 —¿qué prosa describe
///       código que cambió después?— y Q4 necesita la arista `describe`, que
///       está congelada por el freno de §8 hasta que exista un caso real. Un
///       campo que hoy no responde nada es andamiaje inventado, así que no se
///       escribe «por si acaso».
///
///       `nivel` es el nivel de carga DECLARADO, que es un concepto del corpus
///       de diseño. Acá solo va `saltos`, que es el mismo dato MEDIDO.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// GRAFO §6: qué NO entra. Sale de la política de artefactos, no se inventa.
const excluidos = [
  '.dart_tool/',
  'build/',
  '.git/',
  '.g.dart',
  '.freezed.dart',
  '.mocks.dart',
];

/// Desde acá se mide `saltos`: los puntos de entrada REALES del repositorio.
///
/// La primera versión medía solo desde `README.md` y dejaba 20 de 21 nodos
/// huérfanos, porque un README no enlaza código. En un corpus de prosa el
/// índice es la puerta; en un repo de código las puertas son otras:
///
///   - el README, para la prosa;
///   - el barril público de cada paquete —`packages/x/lib/x.dart`—, que es lo
///     único que otro paquete puede importar;
///   - cada archivo de test, que es un punto de entrada por definición;
///   - cada `bin/*.dart`, que es un ejecutable por convención de Dart.
///
/// Los dos últimos NO son excepciones declaradas: son la regla bien escrita.
/// La primera versión los reportaba como código muerto, y declararlos habría
/// sido tapar un defecto del criterio con una lista.
///
/// Un nodo que sigue en `saltos: -1` después de eso no lo alcanza NADIE: es
/// código muerto, y eso es Q5 respondida sobre código en vez de sobre prosa.
bool esIndice(String rel) {
  if (rel == 'README.md') return true;
  if (rel.endsWith('_test.dart')) return true;
  if (rel.contains('/bin/') && rel.endsWith('.dart')) return true;
  final m = RegExp(r'^packages/([^/]+)/lib/([^/]+)\.dart$').firstMatch(rel);
  return m != null && m.group(1) == m.group(2);
}

class Arista {
  final String a;
  final String tipo;
  Arista(this.a, this.tipo);
  Map<String, Object?> toJson() => {'a': a, 'tipo': tipo, 'origen': 'derivado'};
}

class Nodo {
  final String id;
  final String tipo;
  final List<Arista> aristas;
  final Set<String> citadoPor = {};
  int saltos = -1;
  Nodo(this.id, this.tipo, this.aristas);

  Map<String, Object?> toJson() => {
        'id': id,
        'tipo': tipo,
        'saltos': saltos,
        'aristas': [for (final a in aristas) a.toJson()],
        'citado_por': (citadoPor.toList()..sort()),
      };
}

String _normalizar(String p) => p.replaceAll(r'\', '/');

/// Resuelve un URI de directiva a una ruta del repositorio, o lo deja crudo.
///
/// **Lo que no resuelve NO se descarta**: se registra con su URI tal cual. Un
/// import que desaparece del grafo porque el generador no supo resolverlo es
/// una arista que nadie vuelve a ver.
String resolverImport(String uri, String archivoRel, Set<String> internos) {
  if (uri.startsWith('package:')) {
    final resto = uri.substring('package:'.length);
    final corte = resto.indexOf('/');
    if (corte > 0) {
      final candidato =
          'packages/${resto.substring(0, corte)}/lib/${resto.substring(corte + 1)}';
      if (internos.contains(candidato)) return candidato;
    }
    return uri;
  }
  if (uri.startsWith('dart:')) return uri;
  final base = archivoRel.contains('/')
      ? archivoRel.substring(0, archivoRel.lastIndexOf('/'))
      : '';
  final partes = <String>[];
  for (final seg in '$base/$uri'.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (partes.isNotEmpty) partes.removeLast();
    } else {
      partes.add(seg);
    }
  }
  final candidato = partes.join('/');
  return internos.contains(candidato) ? candidato : uri;
}

void main(List<String> args) {
  final raiz =
      Directory(File.fromUri(Platform.script).parent.parent.parent.parent.path);
  final salida = File('${raiz.path}/grafo.jsonl');

  // --- meta · la regla que este generador aplica sigue en el registro ----
  //
  // Sin esto, borrar `grafo-derivado` de arquitectura.json dejaría el check
  // corriendo y la regla sin declarar: registrada en ningún lado y ejecutada
  // igual, que es la mitad simétrica de F33.
  final registro = File('${raiz.path}/arquitectura.json');
  if (!registro.existsSync()) {
    stderr.writeln('grafo: no encuentro arquitectura.json');
    exit(2);
  }
  final regla = ((jsonDecode(registro.readAsStringSync())
          as Map<String, Object?>)['reglas']
      as Map<String, Object?>)['grafo-derivado'] as Map<String, Object?>?;
  final malRegistro = <String>[
    if (regla == null)
      'arquitectura.json: falta la regla «grafo-derivado». Un control que '
          'desaparece del registro sin ruido es F33.'
    else ...[
      if (regla['tipo'] != 'grafo_derivado')
        'arquitectura.json: «grafo-derivado» tiene tipo «${regla['tipo']}»; se '
            'esperaba «grafo_derivado».',
      if (regla['aplicada_por'] != 'tool/analisis')
        'arquitectura.json: «grafo-derivado» ya no delega en este generador.',
      if (regla['violacion_canonica'] == null)
        'arquitectura.json: «grafo-derivado» no declara violación canónica.',
    ],
  ];
  if (malRegistro.isNotEmpty) {
    stderr.writeln('grafo: FALLA\n');
    for (final m in malRegistro) {
      stderr.writeln('  $m');
    }
    exit(1);
  }

  // --- qué archivos son nodos ------------------------------------------
  final todos = <String>[];
  var vistos = 0;
  for (final e in raiz.listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = _normalizar(e.path.substring(raiz.path.length + 1));
    if (!rel.endsWith('.dart') && !rel.endsWith('.md')) continue;
    vistos++;
    if (excluidos.any(rel.contains)) continue;
    todos.add(rel);
  }
  todos.sort();
  if (todos.isEmpty) {
    stderr.writeln('grafo: no encontré ningún archivo. Un grafo vacío se lee '
        'igual que un proyecto limpio, así que esto falla.');
    exit(1);
  }
  final internos = todos.toSet();

  // --- aristas ----------------------------------------------------------
  final nodos = <String, Nodo>{};
  final ilegibles = <String>[];
  for (final rel in todos) {
    final f = File('${raiz.path}/$rel');
    final aristas = <Arista>[];
    if (rel.endsWith('.dart')) {
      CompilationUnit unidad;
      try {
        unidad = parseFile(
          path: f.path,
          featureSet: FeatureSet.latestLanguageVersion(),
          throwIfDiagnostics: false,
        ).unit;
      } catch (e) {
        // NO se salta. Un archivo que el generador no pudo leer produce un
        // grafo más chico, y «regenerado == commiteado» sigue pasando porque
        // los dos son igual de ciegos. Por eso es rojo.
        ilegibles.add('$rel: $e');
        continue;
      }
      for (final d in unidad.directives) {
        String? uri;
        if (d is ImportDirective) uri = d.uri.stringValue;
        if (d is ExportDirective) uri = d.uri.stringValue;
        if (d is PartDirective) uri = d.uri.stringValue;
        if (uri != null) {
          aristas.add(Arista(resolverImport(uri, rel, internos), 'importa'));
        }
      }
    } else {
      final texto = f.readAsStringSync();
      for (final m in RegExp(r'\]\(([^)\s]+)\)').allMatches(texto)) {
        final destino = m.group(1)!.split('#').first;
        if (destino.isEmpty || destino.startsWith(RegExp(r'https?:|mailto:'))) {
          continue;
        }
        aristas.add(Arista(resolverImport(destino, rel, internos), 'cita'));
      }
    }
    aristas.sort((x, y) => '${x.a}${x.tipo}'.compareTo('${y.a}${y.tipo}'));
    nodos[rel] = Nodo(rel, rel.endsWith('.dart') ? 'codigo' : 'prosa', aristas);
  }

  if (ilegibles.isNotEmpty) {
    stderr.writeln(
        'grafo: FALLA — no pude leer ${ilegibles.length} archivo(s). '
        'Un nodo que falta hace el grafo más chico sin que nadie lo note:\n');
    for (final i in ilegibles) {
      stderr.writeln('  $i');
    }
    exit(1);
  }
  // Atestación: cuántos archivos se miraron, contra cuántos hay.
  if (nodos.length != todos.length) {
    stderr
        .writeln('grafo: ${todos.length} archivos candidatos y ${nodos.length} '
            'nodos. Alguno se perdió en silencio.');
    exit(1);
  }

  // --- índice inverso (Q2) y saltos desde el índice (Q5, Q6) ------------
  for (final n in nodos.values) {
    for (final a in n.aristas) {
      nodos[a.a]?.citadoPor.add(n.id);
    }
  }
  final cola = <String>[
    for (final i in todos)
      if (esIndice(i)) i
  ];
  for (final i in cola) {
    nodos[i]!.saltos = 0;
  }
  var frente = List<String>.from(cola);
  var d = 0;
  while (frente.isNotEmpty) {
    d++;
    final siguiente = <String>[];
    for (final id in frente) {
      for (final a in nodos[id]!.aristas) {
        final v = nodos[a.a];
        if (v != null && v.saltos < 0) {
          v.saltos = d;
          siguiente.add(v.id);
        }
      }
    }
    frente = siguiente;
  }

  // --- Q5 sobre código · lo que no alcanza nadie -------------------------
  //
  // Un archivo que ningún punto de entrada alcanza es código muerto. Se
  // declara igual que los puertos sin implementación: la lista se verifica en
  // los DOS sentidos, así que una declaración que quedó vieja también falla.
  final declarados = <String>{};
  final decl = File('${raiz.path}/grafo-huerfanos.txt');
  if (decl.existsSync()) {
    for (final l in decl.readAsLinesSync()) {
      final t = l.split('#').first.trim();
      if (t.isNotEmpty) declarados.add(t);
    }
  }
  final huerfanos = {
    for (final n in nodos.values)
      if (n.saltos < 0) n.id,
  };
  final problemas = <String>[
    for (final h in (huerfanos.difference(declarados)).toList()..sort())
      '$h: no lo alcanza ningún punto de entrada. Es código muerto, o le falta '
          'su punto de entrada. Si es a propósito, declaralo en '
          'grafo-huerfanos.txt con el motivo.',
    for (final d in (declarados.difference(huerfanos)).toList()..sort())
      'grafo-huerfanos.txt declara «$d», que ya no está huérfano o ya no '
          'existe. Una declaración vieja tapa al siguiente archivo muerto.',
  ];
  if (problemas.isNotEmpty) {
    stderr.writeln('grafo: FALLA — Q5, alcanzabilidad:\n');
    for (final p in problemas) {
      stderr.writeln('  $p');
    }
    exit(1);
  }

  // --- serializar -------------------------------------------------------
  final lineas = [
    for (final id in todos) jsonEncode(nodos[id]!.toJson()),
  ].join('\n');
  final texto = '$lineas\n';

  if (args.contains('--escribir')) {
    salida.writeAsStringSync(texto);
    stdout.writeln('grafo: escrito — ${nodos.length} nodos, '
        '${nodos.values.fold<int>(0, (s, n) => s + n.aristas.length)} aristas.');
    return;
  }

  if (!salida.existsSync()) {
    stderr.writeln('grafo: falta grafo.jsonl. Generalo con `--escribir`.');
    exit(1);
  }
  final commiteado = salida.readAsStringSync();
  if (commiteado != texto) {
    final a = commiteado.split('\n');
    final b = texto.split('\n');
    stderr.writeln('grafo: FALLA — el commiteado no coincide con el árbol.\n');
    var mostradas = 0;
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : '(no está)';
      final y = i < b.length ? b[i] : '(no está)';
      if (x != y && mostradas++ < 5) {
        stderr.writeln('  línea ${i + 1}\n    commiteado: '
            '${x.length > 140 ? '${x.substring(0, 140)}…' : x}\n'
            '    derivado:   ${y.length > 140 ? '${y.substring(0, 140)}…' : y}');
      }
    }
    stderr.writeln('\n  Regeneralo con `dart run bin/grafo.dart --escribir` '
        'desde tool/analisis. No lo edites a mano: se deriva, no se mantiene.');
    exit(1);
  }
  stdout.writeln('grafo: ok — ${nodos.length} nodos y '
      '${nodos.values.fold<int>(0, (s, n) => s + n.aristas.length)} aristas, '
      'derivados del árbol y coincidentes con lo commiteado '
      '($vistos archivos mirados).');
}
