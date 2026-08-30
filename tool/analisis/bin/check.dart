/// Aplica las reglas de `arquitectura.json` que necesitan el árbol sintáctico
/// de `core`, y que por eso no puede aplicar `capas.py`.
///
///     cd tool/analisis && dart run bin/check.dart
///
/// Sale 1 si algo falla. No modifica archivos.
///
/// POR QUÉ EL ÁRBOL Y NO UNA EXPRESIÓN REGULAR
///     Es la misma lección que ya pagó `capas.py` con el grafo de
///     dependencias: parsear a mano devuelve cero resultados ante una sintaxis
///     que el parser no reconoce, y cero se lee igual que «está todo bien».
///     Los campos de una clase se los pide al analizador, que es quien los
///     resuelve.
///
/// POR QUÉ ESTE PAQUETE ESTÁ FUERA DEL WORKSPACE
///     Depende del analizador, y ninguna regla de capas debería tener que
///     hacerle una excepción a su propio verificador. Al no ser miembro, no
///     aparece en el grafo que gobierna `packages/` y no puede importarlo
///     nadie de ahí adentro.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

final List<String> fallos = [];

/// Lo que se pudo derivar de una clase. Cada campo que sea `null` significa
/// **no pude mirar**, que nunca es lo mismo que **no encontré nada**.
class Clase {
  final String nombre;
  final String archivo;
  final bool esAbstracta;
  final List<String> camposPublicos;

  /// Campos cuyo tipo es una colección y que el constructor recibe por
  /// referencia en vez de copiar. Alias vivos hacia afuera del objeto.
  final List<String> coleccionesAliasadas;
  final Set<String>? clavesToJson;
  final Set<String>? clavesFromJson;
  final String? literalDeToString;
  final Set<String> superTipos;

  Clase(
      this.nombre,
      this.archivo,
      this.esAbstracta,
      this.camposPublicos,
      this.coleccionesAliasadas,
      this.clavesToJson,
      this.clavesFromJson,
      this.literalDeToString,
      this.superTipos);
}

/// Junta las claves que un `fromJson` lee del mapa que recibe.
///
/// El nombre del parámetro se toma de la firma, no se supone. Suponerlo era un
/// falso ROJO —un `fromJson(Map j)` reportaba todos los campos como perdidos—
/// y un falso rojo también erosiona el check: el que lo mira aprende a
/// ignorarlo.
class _Indices extends RecursiveAstVisitor<void> {
  final String parametro;
  final Set<String> claves = {};

  _Indices(this.parametro);

  @override
  void visitIndexExpression(IndexExpression node) {
    final t = node.target;
    final i = node.index;
    if (t is SimpleIdentifier &&
        t.name == parametro &&
        i is SimpleStringLiteral) {
      claves.add(i.value);
    }
    super.visitIndexExpression(node);
  }
}

String _nombreDeTipo(NamedType t) => t.toSource().split('<').first.trim();

Set<String>? _clavesDeMapa(FunctionBody cuerpo, String donde) {
  SetOrMapLiteral? lit;
  if (cuerpo is ExpressionFunctionBody) {
    final e = cuerpo.expression;
    if (e is SetOrMapLiteral) lit = e;
  } else if (cuerpo is BlockFunctionBody) {
    for (final s in cuerpo.block.statements) {
      if (s is ReturnStatement && s.expression is SetOrMapLiteral) {
        lit = s.expression as SetOrMapLiteral;
      }
    }
  }
  if (lit == null) {
    fallos.add('$donde: no pude leer el mapa que devuelve. Escribilo como un '
        'literal de mapa devuelto directamente. No mirar no es lo mismo que '
        'no encontrar nada, así que esto falla en vez de pasar.');
    return null;
  }
  final claves = <String>{};
  for (final e in lit.elements) {
    if (e is MapLiteralEntry && e.key is SimpleStringLiteral) {
      claves.add((e.key as SimpleStringLiteral).value);
    } else {
      fallos.add('$donde: hay una entrada cuya clave no es una cadena literal '
          '(`${e.toSource()}`). No puedo derivar los campos: escribí las claves '
          'literales.');
      return null;
    }
  }
  return claves;
}

List<Clase> clasesDe(File archivo, String rel) {
  final resultado = parseFile(
    path: archivo.path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  // Un archivo que no parsea devuelve un árbol PARCIAL, y de un árbol parcial
  // salen cero clases — que se lee exactamente igual que «este archivo no
  // tenía nada que verificar». Es la falla silenciosa de siempre, así que se
  // reporta acá y no se espera a que `dart analyze` la encuentre después.
  for (final d in resultado.errors) {
    fallos.add('$rel:${d.offset}: no parsea, así que no pude derivar nada de '
        'este archivo. ${d.message}');
  }
  final unidad = resultado.unit;
  final salida = <Clase>[];
  for (final d in unidad.declarations) {
    if (d is! ClassDeclaration) continue;
    final nombre = d.name.lexeme;
    final campos = <String>[];
    final tiposDeCampo = <String, String>{};
    Set<String>? toJson;
    Set<String>? fromJson;
    String? literalToString;
    var tieneToJson = false;
    var tieneFromJson = false;

    for (final m in d.members) {
      if (m is FieldDeclaration && !m.isStatic) {
        final tipo = m.fields.type?.toSource() ?? '';
        for (final v in m.fields.variables) {
          final n = v.name.lexeme;
          if (!n.startsWith('_')) {
            campos.add(n);
            tiposDeCampo[n] = tipo;
          }
        }
      } else if (m is MethodDeclaration && m.name.lexeme == 'toJson') {
        tieneToJson = true;
        toJson = _clavesDeMapa(m.body, '$rel · $nombre.toJson');
      } else if (m is MethodDeclaration && m.name.lexeme == 'toString') {
        final b = m.body;
        if (b is ExpressionFunctionBody &&
            b.expression is SimpleStringLiteral) {
          literalToString = (b.expression as SimpleStringLiteral).value;
        }
      } else if (m is ConstructorDeclaration && m.name?.lexeme == 'fromJson') {
        tieneFromJson = true;
        final params = m.parameters.parameters;
        if (params.isEmpty || params.first.name == null) {
          fallos.add('$rel · $nombre.fromJson: no pude leer el nombre de su '
              'parámetro, así que no puedo derivar qué claves lee.');
        } else {
          final v = _Indices(params.first.name!.lexeme);
          m.visitChildren(v);
          fromJson = v.claves;
        }
      }
    }
    // Un campo de colección que el constructor recibe con `this.x` queda
    // ALIASADO: quien conserve la lista original puede mutarla después, y
    // cualquier invariante que dependa de ella deja de ser del tipo. Se exige
    // que se copie a una vista inmodificable en la lista de inicializadores.
    final aliasadas = <String>[];
    for (final entrada in tiposDeCampo.entries) {
      final t = entrada.value;
      if (!(t.startsWith('List<') ||
          t.startsWith('Map<') ||
          t.startsWith('Set<'))) {
        continue;
      }
      for (final m in d.members) {
        // Todos los constructores GENERATIVOS, tengan nombre o no. Antes
        // se miraba solo el anónimo, así que `Clase.desde(this.items)`
        // conservaba el alias y el check no lo inspeccionaba: la regla
        // cubría una forma de escribir el constructor, no el invariante.
        //
        // Se saltean los `factory` —no pueden inicializar campos— y los
        // redirigentes, que delegan en otro constructor ya inspeccionado.
        if (m is! ConstructorDeclaration) continue;
        if (m.factoryKeyword != null) continue;
        if (m.redirectedConstructor != null) continue;
        if (m.initializers.any((i) => i is RedirectingConstructorInvocation)) {
          continue;
        }
        final porReferencia = m.parameters.parameters.any((param) {
          final p = param is DefaultFormalParameter ? param.parameter : param;
          return p is FieldFormalParameter && p.name.lexeme == entrada.key;
        });
        final copiada = m.initializers.any((ini) =>
            ini is ConstructorFieldInitializer &&
            ini.fieldName.name == entrada.key &&
            ini.expression.toSource().contains('.unmodifiable('));
        if (porReferencia || !copiada) aliasadas.add(entrada.key);
      }
    }

    final supers = <String>{
      if (d.extendsClause != null) _nombreDeTipo(d.extendsClause!.superclass),
      for (final t in d.implementsClause?.interfaces ?? const <NamedType>[])
        _nombreDeTipo(t),
      for (final t in d.withClause?.mixinTypes ?? const <NamedType>[])
        _nombreDeTipo(t),
    };
    salida.add(Clase(
        nombre,
        rel,
        d.abstractKeyword != null,
        campos,
        aliasadas,
        tieneToJson ? toJson : null,
        tieneFromJson ? fromJson : null,
        literalToString,
        supers));
  }
  return salida;
}

List<File> fuentes(Directory d) => d
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.contains('.dart_tool'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

void main(List<String> args) {
  final raiz =
      Directory(File.fromUri(Platform.script).parent.parent.parent.parent.path);
  final registro = File('${raiz.path}/arquitectura.json');
  if (!registro.existsSync()) {
    stderr.writeln('no encuentro arquitectura.json desde ${raiz.path}');
    exit(2);
  }
  final reglas = (jsonDecode(registro.readAsStringSync())
      as Map<String, Object?>)['reglas'] as Map<String, Object?>;

  // --- meta · las reglas que este verificador aplica siguen ahí ---------
  const esperadas = {
    'serializacion-sin-perdida': 'campos_derivados',
    'opacidad-declarada': 'opacidad_declarada',
    'puertos-sin-implementacion': 'huecos_declarados',
    'colecciones-inmutables': 'colecciones_copiadas',
  };
  for (final e in esperadas.entries) {
    final r = reglas[e.key] as Map<String, Object?>?;
    if (r == null) {
      fallos.add('arquitectura.json: falta la regla «${e.key}». Un control que '
          'desaparece sin ruido es F33.');
      continue;
    }
    if (r['tipo'] != e.value) {
      fallos.add('arquitectura.json: «${e.key}» tiene tipo «${r['tipo']}»; se '
          'esperaba «${e.value}». Cambiarlo la saltea sin borrarla.');
    }
    if (r['violacion_canonica'] == null) {
      fallos.add('arquitectura.json: «${e.key}» no declara violación canónica. '
          'Una regla que no puede ponerse roja no está probada.');
    }
    if (r['caso_ciego'] == null) {
      fallos.add('arquitectura.json: «${e.key}» no declara `caso_ciego`. Nadie '
          'probó nunca qué hace este control cuando NO PUEDE MIRAR, y su '
          'silencio es indistinguible de su aprobación (ADR-011 §5).');
    }
    if (r['aplicada_por'] != 'tool/analisis') {
      fallos.add('arquitectura.json: «${e.key}» ya no delega en este '
          'verificador. Quedaría registrada y sin ejecutar.');
    }
  }

  final opacos = ((reglas['opacidad-declarada']
          as Map<String, Object?>?)?['opacos'] as Map<String, Object?>? ??
      {})
    ..remove('_');
  final sinImpl = ((reglas['puertos-sin-implementacion']
              as Map<String, Object?>?)?['sin_implementacion']
          as Map<String, Object?>? ??
      {})
    ..remove('_');

  // --- lo que hay de verdad --------------------------------------------
  final dirCore = Directory('${raiz.path}/packages/core/lib');
  final dirPaquetes = Directory('${raiz.path}/packages');
  if (!dirCore.existsSync()) {
    stderr.writeln('no encuentro packages/core/lib');
    exit(2);
  }
  final clasesCore = <Clase>[];
  for (final f in fuentes(dirCore)) {
    clasesCore.addAll(clasesDe(f, f.path.substring(raiz.path.length + 1)));
  }
  final todasLasClases = <Clase>[];
  for (final f in fuentes(dirPaquetes)) {
    todasLasClases.addAll(clasesDe(f, f.path.substring(raiz.path.length + 1)));
  }
  if (clasesCore.isEmpty) {
    fallos.add('no encontré ninguna clase en packages/core/lib. O el paquete '
        'está vacío, o no supe leerlo: las dos cosas son rojas.');
  }

  // --- 1 · serialización sin pérdida ------------------------------------
  for (final c in clasesCore) {
    if (c.esAbstracta || c.camposPublicos.isEmpty) continue;
    if (opacos.containsKey(c.nombre)) continue;
    if (c.clavesToJson == null || c.clavesFromJson == null) continue;
    final campos = c.camposPublicos.toSet();
    for (final falta in (campos.difference(c.clavesToJson!)).toList()..sort()) {
      fallos.add('${c.archivo} · ${c.nombre}: el campo «$falta» no está en '
          'toJson. Se pierde en cada serialización y ningún test de ida y '
          'vuelta lo nota.');
    }
    for (final sobra in (c.clavesToJson!.difference(campos)).toList()..sort()) {
      fallos.add('${c.archivo} · ${c.nombre}: toJson escribe «$sobra», que no '
          'es un campo de la clase. fromJson no lo va a poder reconstruir.');
    }
    for (final falta in (campos.difference(c.clavesFromJson!)).toList()
      ..sort()) {
      fallos.add('${c.archivo} · ${c.nombre}: fromJson no lee «$falta». '
          'El campo viaja de ida y se pierde a la vuelta.');
    }
    // La cuarta dirección, que faltaba. El enunciado dice EXACTAMENTE las
    // mismas claves, y se comprobaban tres de los cuatro sentidos: un
    // `fromJson` que leyera una clave inexistente pasaba en verde. Comparar
    // conjuntos en una sola dirección es media comparación.
    for (final sobra in (c.clavesFromJson!.difference(campos)).toList()
      ..sort()) {
      fallos.add('${c.archivo} · ${c.nombre}: fromJson lee «$sobra», que no es '
          'un campo de la clase y que toJson nunca escribe. O sobra la '
          'lectura, o falta el campo.');
    }
  }

  // --- 1b · y la prueba de ida y vuelta las cubre a todas ----------------
  //
  // El verificador de campos no mira VALORES, y la prueba de ida y vuelta sí,
  // pero solo sobre las clases que alguien se acordó de poner en ella. Una
  // entidad nueva sin su caso pasaba en verde por las dos: cada uno cubría lo
  // que el otro no, y el hueco quedaba entre los dos.
  final prueba =
      File('${raiz.path}/packages/core/test/serializacion_test.dart');
  if (!prueba.existsSync()) {
    fallos.add('falta packages/core/test/serializacion_test.dart. Es lo único '
        'que verifica que los VALORES sobrevivan el viaje.');
  } else {
    final texto = prueba.readAsStringSync();
    for (final c in clasesCore) {
      if (c.esAbstracta || c.clavesToJson == null) continue;
      if (!texto.contains("'${c.nombre}'")) {
        fallos.add('packages/core/test/serializacion_test.dart: «${c.nombre}» '
            'serializa y no tiene caso canónico. Agregá una instancia con un '
            'valor distinguible en cada campo.');
      }
    }
  }

  // --- 1c · las colecciones se copian, no se aceptan por referencia ------
  //
  // `final List<X> campo` NO hace inmutable la lista: solo impide reasignar
  // el campo. Quien conserve la lista que le pasó al constructor puede
  // vaciarla después, y con ella cualquier invariante que dependa de su
  // contenido. Lo encontró un review: una `Rule` construida con evasiones
  // válidas se quedaba sin ninguna cuando el llamador vaciaba su lista, y un
  // `VerificationOutcome` pasaba de verde a no concluyente igual.
  for (final c in clasesCore) {
    if (c.esAbstracta || opacos.containsKey(c.nombre)) continue;
    for (final campo in c.coleccionesAliasadas) {
      fallos.add('${c.archivo} · ${c.nombre}: el campo de colección «$campo» '
          'entra al constructor por referencia. Copialo con '
          '`List.unmodifiable(...)` o `Map.unmodifiable(...)` en la lista de '
          'inicializadores: sin eso, el invariante se puede romper DESPUÉS de '
          'construir el objeto, y entonces no es una propiedad del tipo.');
    }
  }

  // --- 2 · opacidad declarada -------------------------------------------
  for (final c in clasesCore) {
    if (c.esAbstracta) continue;
    final declarada = opacos[c.nombre] as Map<String, Object?>?;
    if (declarada == null) {
      if (c.camposPublicos.isNotEmpty &&
          (c.clavesToJson == null || c.clavesFromJson == null)) {
        fallos.add('${c.archivo} · ${c.nombre}: tiene campos y no serializa, y '
            'no está declarada opaca. Escribile toJson y fromJson, o declarala '
            'en «opacidad-declarada.opacos» con su motivo.');
      }
      continue;
    }
    if (c.clavesToJson != null || c.clavesFromJson != null) {
      fallos.add('${c.archivo} · ${c.nombre}: está declarada opaca y sin '
          'embargo serializa. ${declarada['por_que']}');
    }
    final mascara = declarada['mascara'] as String?;
    if (mascara != null && c.literalDeToString != mascara) {
      fallos.add('${c.archivo} · ${c.nombre}: su toString no devuelve la '
          'máscara declarada «$mascara» como literal '
          '(leí: ${c.literalDeToString ?? 'algo que no es un literal'}). '
          'Es lo que aparece en una interpolación o en un log.');
    }
  }
  for (final n in opacos.keys) {
    if (!clasesCore.any((c) => c.nombre == n)) {
      fallos.add('arquitectura.json: «opacidad-declarada» declara opaca a '
          '«$n», que ya no existe en core. Una declaración vieja tapa la '
          'siguiente clase que se llame igual.');
    }
  }

  // --- 3 · puertos sin implementación, declarados ------------------------
  final puertos = clasesCore.where((c) => c.esAbstracta).map((c) => c.nombre);
  // **La herencia se sigue hasta arriba, no un nivel.** Miraba solo los
  // supertipos DIRECTOS de las clases concretas, y con eso un puerto
  // implementado a traves de una base abstracta quedaba invisible: la base
  // implementa el puerto pero es abstracta —no cuenta—, y la concreta solo
  // nombra a la base. Paso de verdad con `Verifier`: dos implementaciones
  // vivas y el registro seguia diciendo que no tenia ninguna, en VERDE.
  //
  // Es la forma exacta que este control existe para cazar, aplicada al propio
  // control: mirar donde es comodo y llamar a eso el invariante.
  final superDe = {for (final c in todasLasClases) c.nombre: c.superTipos};
  Set<String> ancestros(String nombre) {
    final vistos = <String>{};
    final pila = [...?superDe[nombre]];
    while (pila.isNotEmpty) {
      final n = pila.removeLast();
      if (!vistos.add(n)) continue; // corta ciclos y repeticiones
      pila.addAll(superDe[n] ?? const <String>{});
    }
    return vistos;
  }

  final implementados = <String>{
    for (final c in todasLasClases)
      if (!c.esAbstracta) ...ancestros(c.nombre),
  };
  final huerfanos = puertos.where((p) => !implementados.contains(p)).toSet();
  for (final p in (huerfanos.difference(sinImpl.keys.toSet())).toList()
    ..sort()) {
    fallos.add(
        'packages/core: el puerto «$p» no tiene ninguna implementación y '
        'no está declarado en «puertos-sin-implementacion». Una superficie de '
        'puertos completa se lee como un sistema que hace esas cosas.');
  }
  for (final p in (sinImpl.keys.toSet().difference(huerfanos)).toList()
    ..sort()) {
    final motivo = puertos.contains(p)
        ? 'ya tiene implementación: sacalo de la lista.'
        : 'no es un puerto de core: la declaración quedó vieja.';
    fallos.add('arquitectura.json: «puertos-sin-implementacion» declara «$p», '
        'que $motivo');
  }

  // --- salida -----------------------------------------------------------
  if (fallos.isNotEmpty) {
    stdout.writeln('serializacion: FALLA\n');
    for (final f in fallos) {
      stdout.writeln('  $f');
    }
    exit(1);
  }
  final serializables =
      clasesCore.where((c) => !c.esAbstracta && c.clavesToJson != null).length;
  stdout.writeln('serializacion: ok — $serializables clases serializables '
      'verificadas campo por campo, ${opacos.length} opacas declaradas, '
      '${huerfanos.length} puertos sin implementación declarados.');
}
