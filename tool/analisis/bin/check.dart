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

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

final List<String> fallos = [];

/// Lo que se pudo derivar de una clase. Cada campo que sea `null` significa
/// **no pude mirar**, que nunca es lo mismo que **no encontré nada**.
class Clase {
  final String nombre;
  final String archivo;
  final bool esAbstracta;

  /// `sealed class`. Dart no permite escribir `abstract` junto a `sealed`
  /// —la palabra sobra, el modificador ya lo implica— así que
  /// `abstractKeyword` queda `null` para estas clases y [esAbstracta] las
  /// cuenta igual. Esto se guarda aparte porque una jerarquía sellada SÍ
  /// tiene que elegir entre serializar o declararse opaca aunque no tenga
  /// campos propios: a diferencia de una interfaz de puerto, es una base de
  /// datos, no de comportamiento.
  final bool esSellada;
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
    this.esSellada,
    this.camposPublicos,
    this.coleccionesAliasadas,
    this.clavesToJson,
    this.clavesFromJson,
    this.literalDeToString,
    this.superTipos,
  );
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
    fallos.add(
      '$donde: no pude leer el mapa que devuelve. Escribilo como un '
      'literal de mapa devuelto directamente. No mirar no es lo mismo que '
      'no encontrar nada, así que esto falla en vez de pasar.',
    );
    return null;
  }
  final claves = <String>{};
  for (final e in lit.elements) {
    if (e is MapLiteralEntry && e.key is SimpleStringLiteral) {
      claves.add((e.key as SimpleStringLiteral).value);
    } else {
      fallos.add(
        '$donde: hay una entrada cuya clave no es una cadena literal '
        '(`${e.toSource()}`). No puedo derivar los campos: escribí las claves '
        'literales.',
      );
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
    fallos.add(
      '$rel:${d.offset}: no parsea, así que no pude derivar nada de '
      'este archivo. ${d.message}',
    );
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
      } else if (m is MethodDeclaration &&
          m.name.lexeme == 'toJson' &&
          m.body is! EmptyFunctionBody) {
        // Una firma sin cuerpo (`Map<String, Object?> toJson();`, en la base
        // de una jerarquía sellada) no tiene ningún mapa que leer todavía:
        // cada variante concreta trae el suyo, y ESE es el que este check
        // valida cuando le toque su turno. Tratarla como una promesa
        // incumplida sería fallar por una firma que a propósito no tiene
        // cuerpo, no por un campo perdido.
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
          fallos.add(
            '$rel · $nombre.fromJson: no pude leer el nombre de su '
            'parámetro, así que no puedo derivar qué claves lee.',
          );
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
        final copiada = m.initializers.any(
          (ini) =>
              ini is ConstructorFieldInitializer &&
              ini.fieldName.name == entrada.key &&
              ini.expression.toSource().contains('.unmodifiable('),
        );
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
    final esSellada = d.sealedKeyword != null;
    salida.add(
      Clase(
        nombre,
        rel,
        d.abstractKeyword != null || esSellada,
        esSellada,
        campos,
        aliasadas,
        tieneToJson ? toJson : null,
        tieneFromJson ? fromJson : null,
        literalToString,
        supers,
      ),
    );
  }
  return salida;
}

List<File> fuentes(Directory d) =>
    d
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) => f.path.endsWith('.dart') && !f.path.contains('.dart_tool'),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

// **LA DERIVACION DE CIFRAS DE LA CASCADA SE RETIRO.**
//
// Derivaba del arbol sintactico cuantos pasos y cuantos minutos declaraba
// `packages/cli/lib/src/verify.dart`, y comparaba contra lo que el README
// afirmaba en prosa. Funcionaba, y estaba bien hecho: contar corchetes sobre el
// texto ya habia producido un falso verde, y preguntarle al analizador fue la
// correccion correcta.
//
// Lo que estaba mal era la FLECHA. Un documento de gobierno derivando sus cifras
// de un archivo de PRODUCTO ata el verificador del gobierno al diseño de la
// cascada: mover, renombrar o rediseñar `verify.dart` rompe la documentacion, y
// vaciar el producto la deja sin fuente. Es el acople en su forma mas pura.
//
// En su lugar, `capas.py` PROHIBE que el documento de gobierno afirme una
// cardinalidad que nada derive —ver `_readme_numerales_sueltos`—. No se pierde
// verificacion: se elimina una TERCERA representacion de la misma cifra, que era
// la unica que habia que mantener a mano. Si algun dia hay que declarar la cifra,
// la prohibicion obliga a construir la derivacion primero, cuando ya tenga sujeto.

class _Lanzamiento {
  /// Relativo a la raíz del repositorio.
  final String archivo;

  /// A qué biblioteca pertenece: el archivo mismo, o el de su `part of`.
  ///
  /// **La excepción se cuenta por BIBLIOTECA y no por archivo.** Un `part`
  /// puede agregar un lanzamiento a la biblioteca exceptuada sin tocar el
  /// archivo declarado, y entonces la declaración lo taparía.
  final String biblioteca;

  final int offset;

  /// Los métodos y funciones que lo contienen, de afuera hacia adentro.
  ///
  /// **Es el ámbito completo y no solo el más interno**, porque una excepción
  /// declarada para un método vale también para un ayudante local suyo: la
  /// captura de identidad lanza desde una función anidada, y mirar solo el nivel
  /// de adentro leía `leer` donde la declaración dice `_capturarIdentidad`.
  final List<String> ambito;

  /// Nulo si cumple.
  final String? problema;

  const _Lanzamiento(
    this.archivo,
    this.biblioteca,
    this.offset,
    this.ambito,
    this.problema,
  );

  /// Lo más interno, para el mensaje.
  String get donde => ambito.isEmpty ? 'el tope del archivo' : ambito.last;
}

/// Busca `Process.run`, `Process.runSync` y `Process.start` y comprueba la
/// SEMÁNTICA de su entorno, no la forma.
///
/// La primera versión del diseño pedía que existieran `environment:` e
/// `includeParentEnvironment: false`. Esto los cumple al pie y no sanea nada:
///
///     Process.run(exe, args,
///         environment: Platform.environment,   // ← cumple la forma
///         includeParentEnvironment: false);    // ← y filtra CERO
///
/// Así que se exige que la expresión de `environment:` sea una llamada a
/// `entornoSaneado`. **Y a ESA, no a cualquiera que se llame igual.**
///
/// La primera versión de este control comparaba el NOMBRE sobre un árbol sin
/// resolver, y un review lo reprodujo: una función local homónima que devolvía
/// el entorno del padre intacto pasaba en verde, y el check anunciaba siete
/// lanzamientos saneados. Comparar nombres es comprobar sintaxis, que es
/// exactamente lo que este control existe para no hacer.
///
/// Ahora se resuelve el elemento y se comprueba **de qué biblioteca viene**:
/// la función tiene que ser la de `core`, y el lanzamiento, el de la biblioteca
/// de entrada y salida del SDK.
///
/// **Y el lanzamiento se identifica por su ELEMENTO, no por cómo se escribe.**
/// Una segunda revisión encontró dos formas ordinarias que se escapaban, las dos
/// con el formateador conforme: un comentario entre la clase y el punto —que el
/// prefiltro por texto no veía— y una importación con prefijo, donde el destino
/// escrito no es el nombre de la clase. Ninguna es código raro, y el invariante
/// afirma cubrir **todo** lanzamiento. Así que no se mira ni el texto del
/// archivo ni el del destino: se mira de qué clase y de qué biblioteca es el
/// método que se invoca.
class _Subprocesos extends RecursiveAstVisitor<void> {
  _Subprocesos(this.archivo, this.biblioteca);

  final String archivo;
  final String biblioteca;
  final List<_Lanzamiento> vistos = [];
  final List<String> _pila = [];

  /// Los tres métodos de lanzamiento, por nombre. **Es un filtro barato, no la
  /// identificación**: esa la hace el elemento resuelto.
  static const _lanzadores = {'run', 'runSync', 'start'};

  /// Cómo se llama la clase que lanza.
  static const _claseQueLanza = 'Process';

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _pila.add(node.name.lexeme);
    super.visitMethodDeclaration(node);
    _pila.removeLast();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _pila.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
    _pila.removeLast();
  }

  /// De dónde viene el símbolo, resuelto. Vacío si no se pudo resolver.
  static String _bibliotecaDe(Element? e) => e?.library?.uri.toString() ?? '';

  /// La biblioteca donde vive la función de saneamiento.
  static const _origenDelSaneador = 'package:core/src/entorno.dart';

  /// La biblioteca de `Process`.
  static const _origenDeProcess = 'dart:io';

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.target == null || !_lanzadores.contains(node.methodName.name)) {
      return;
    }
    // **De qué clase y de qué biblioteca es el método que se invoca.** No cómo
    // se escribe el destino: la clase escrita a secas, con un comentario en
    // medio, o a través del prefijo de una importación resuelven las tres a lo
    // mismo, y eso es lo que hay que preguntar.
    final metodo = node.methodName.element;
    final deDondeViene = _bibliotecaDe(metodo);
    final esLanzamientoDelSdk =
        metodo?.enclosingElement?.name == _claseQueLanza &&
        deDondeViene == _origenDeProcess;

    if (!esLanzamientoDelSdk) {
      // No es un lanzamiento del SDK. **Salvo que se le parezca demasiado**: un
      // `X.run(...)` donde `X` se llama igual que la clase que lanza y no es la
      // del SDK deja a este control sin poder decir qué corre. Es un falso
      // positivo deliberado, y su precio es renombrar una clase; el de la
      // alternativa es no ver un lanzamiento envuelto en un homónimo.
      final destino = node.target;
      final seLlamaIgual =
          destino is Identifier &&
          destino.name.split('.').last == _claseQueLanza;
      if (!seLlamaIgual) return;
      vistos.add(
        _Lanzamiento(
          archivo,
          biblioteca,
          node.offset,
          List<String>.unmodifiable(_pila),
          '`$_claseQueLanza` acá no es el de la biblioteca de entrada y salida '
          'del SDK, sino ${deDondeViene.isEmpty ? "un símbolo que no se "
                    "pudo resolver" : "«$deDondeViene»"}. Este control no puede '
          'decir qué lanza.',
        ),
      );
      return;
    }

    final nombrados = {
      for (final a in node.argumentList.arguments)
        if (a is NamedExpression) a.name.label.name: a.expression,
    };
    final entorno = nombrados['environment'];
    final hereda = nombrados['includeParentEnvironment'];
    String? problema;
    if (entorno is! MethodInvocation ||
        entorno.methodName.name != 'entornoSaneado') {
      problema =
          '`environment:` no es una llamada a `entornoSaneado`'
          '${entorno == null ? " (no está, así que hereda todo)" : ""}. '
          'Pasar `Platform.environment` cumple la forma y filtra cero.';
    } else if (_bibliotecaDe(entorno.methodName.element) !=
        _origenDelSaneador) {
      // El caso que un review reprodujo: una homónima que devuelve el entorno
      // del padre intacto. El nombre coincide; la función no es.
      final donde = _bibliotecaDe(entorno.methodName.element);
      problema =
          'llama a algo llamado `entornoSaneado` que NO es el de `core`: '
          '${donde.isEmpty ? "no se pudo resolver de dónde viene" : "viene de "
                    "«$donde»"}. Una homónima que devuelva el entorno del padre '
          'intacto cumpliría el nombre y filtraría cero.';
    } else if (hereda is! BooleanLiteral || hereda.value) {
      problema =
          'falta `includeParentEnvironment: false` literal: sin él, el '
          'entorno saneado se SUMA al del padre en vez de reemplazarlo.';
    }
    vistos.add(
      _Lanzamiento(
        archivo,
        biblioteca,
        node.offset,
        List<String>.unmodifiable(_pila),
        problema,
      ),
    );
  }
}

/// ¿Este archivo tiene alguna invocación con la FORMA de un lanzamiento?
///
/// **Estructural, no por texto.** El prefiltro buscaba la cadena `Process.` en
/// el archivo, y una revisión lo reprodujo: un comentario entre la clase y el
/// punto —sintaxis corriente, que el formateador deja intacta— rompía esa
/// cadena y el archivo no se resolvía siquiera. Un prefiltro que decide qué
/// mirar por coincidencia textual decide mal.
///
/// Acá se acepta de más a propósito: cualquier invocación de un método con uno
/// de los tres nombres, sobre cualquier destino. Quién lanza de verdad lo dice
/// el elemento resuelto; esto solo evita resolver archivos que no pueden
/// contener un lanzamiento.
class _PareceLanzamiento extends RecursiveAstVisitor<void> {
  bool encontrado = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.target != null &&
        _Subprocesos._lanzadores.contains(node.methodName.name)) {
      encontrado = true;
    }
  }
}

/// A qué biblioteca pertenece un archivo: él mismo, o el de su `part of`.
String _bibliotecaDe(CompilationUnit unidad, String rel) {
  for (final d in unidad.directives) {
    if (d is PartOfDirective && d.uri != null) {
      final uri = d.uri!.stringValue;
      if (uri == null) continue;
      final corte = rel.lastIndexOf('/');
      return corte < 0 ? uri : '${rel.substring(0, corte)}/$uri';
    }
  }
  return rel;
}

/// Un lugar donde el archivo nombra a la forja, o instancia su cliente.
class _MencionDeForja {
  final int offset;
  final List<String> ambito;
  final String criterio;

  const _MencionDeForja(this.offset, this.ambito, this.criterio);

  /// Lo más interno, para el mensaje. Mismo criterio que `_Lanzamiento.donde`.
  String get donde => ambito.isEmpty ? 'el tope del archivo' : ambito.last;
}

/// Busca `HttpClient`, **derivado del árbol sintáctico y sin resolverlo**.
///
/// A diferencia de `_Subprocesos`, que compara la IDENTIDAD resuelta de
/// `Process` contra `dart:io`, acá no se paga ese costo: el universo de esta
/// regla ya está acotado por RUTA —`lib/` y `bin/` de todo paquete menos
/// `forge`—, que es la exigencia dura de CLAUDE.md, y resolver una segunda
/// vez empujaría el job de arquitectura hacia el límite que ya casi toca
/// `subprocesos-con-entorno-saneado` (~11-12 min contra 20).
///
/// **Falso positivo deliberado**, la misma decisión y el mismo precio que ya
/// toma `_Subprocesos` con `Process`: una clase PROPIA que se llame
/// `HttpClient` se reporta igual, porque sin resolver no se puede saber cuál
/// es. El precio es renombrarla.
///
/// **La prosa no cuenta.** `visitComment` no desciende: un doc comment que
/// EXPLIQUE por qué este código no sabe quién es la forja —nombrando
/// proveedores como ejemplo, como hace `puertos.dart`— no es la fuga que
/// esta regla persigue, y castigarlo sería castigar la documentación que
/// sostiene el propio invariante.
///
/// De paso arma el mapa de ámbitos —`rangos`— que el segundo criterio
/// (textual) necesita para poder decir DÓNDE, no solo QUÉ: un identificador
/// se ve en el momento en que el visitante lo visita, pero una mención de
/// texto se encuentra por `String.indexOf`, fuera de cualquier recorrido, y
/// necesita este mapa para saber en qué método o función cayó.
class _Forja extends RecursiveAstVisitor<void> {
  final List<_MencionDeForja> vistos = [];
  final List<(int, int, String)> rangos = [];
  final List<String> _pila = [];

  @override
  void visitComment(Comment node) {
    // Intencionalmente no hace `node.visitChildren(this)`: ver el docstring
    // de esta clase.
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    rangos.add((node.offset, node.end, node.name.lexeme));
    _pila.add(node.name.lexeme);
    super.visitMethodDeclaration(node);
    _pila.removeLast();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    rangos.add((node.offset, node.end, node.name.lexeme));
    _pila.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
    _pila.removeLast();
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    if (node.name == 'HttpClient') {
      vistos.add(
        _MencionDeForja(
          node.offset,
          List<String>.unmodifiable(_pila),
          'HttpClient',
        ),
      );
    }
  }

  /// El ámbito más interno que CONTIENE a [offset]. Se elige el rango más
  /// angosto que lo cubre, no el primero que aparece: un método anidado
  /// adentro de otro tiene un rango más chico y es el que hay que nombrar.
  String ambitoEn(int offset) {
    String? mejor;
    var anchoDelMejor = 1 << 30;
    for (final r in rangos) {
      final ancho = r.$2 - r.$1;
      if (r.$1 <= offset && offset < r.$2 && ancho < anchoDelMejor) {
        mejor = r.$3;
        anchoDelMejor = ancho;
      }
    }
    return mejor ?? 'el tope del archivo';
  }
}

/// Los tramos de [contenido] que son comentario —`//`, `///` o `/* */`—,
/// derivados del stream de tokens que ya generó el parseo. **Texto, no
/// árbol**: se camina la cadena de `precedingComments` de cada token, que es
/// justo lo que necesita `todo_finder.dart` del propio analizador para lo
/// mismo. No se vuelve a tokenizar a mano ni con una expresión regular —una
/// que buscara `//` a ciegas cortaría una URL como `https://` a mitad de
/// camino, y es la misma clase de error que ya le costó dos revisiones a
/// `subprocesos-con-entorno-saneado` con un prefiltro de texto.
List<(int, int)> _rangosDeComentarios(CompilationUnit unidad) {
  final rangos = <(int, int)>[];
  Token? token = unidad.beginToken;
  while (token != null) {
    Token? comentario = token.precedingComments;
    while (comentario != null) {
      rangos.add((comentario.offset, comentario.end));
      comentario = comentario.next;
    }
    // El EOF también puede tener comentarios propios — un comentario que es
    // lo ÚLTIMO del archivo, sin ningún token real después, cuelga de él. Si
    // el recorrido cortara antes de mirarlo, esa prosa quedaría fuera de
    // `rangos` y el criterio textual la leería como código: exactamente la
    // fuga que este control existe para no tener. Por eso se lo procesa y
    // RECIÉN DESPUÉS se corta, en vez de cortar antes de llegar a él.
    if (token.type == TokenType.EOF) break;
    token = token.next;
  }
  return rangos;
}

/// Las posiciones donde [aguja] aparece en [contenido], **fuera de**
/// cualquiera de [comentarios]. Una aguja dentro de un comentario es prosa, y
/// la prosa no cuenta para este control — ver el docstring de `_Forja`.
List<int> _ocurrenciasFueraDeComentarios(
  String contenido,
  String aguja,
  List<(int, int)> comentarios,
) {
  final hallazgos = <int>[];
  var desde = 0;
  while (true) {
    final i = contenido.indexOf(aguja, desde);
    if (i < 0) break;
    desde = i + 1;
    if (comentarios.any((r) => i >= r.$1 && i < r.$2)) continue;
    hallazgos.add(i);
  }
  return hallazgos;
}

Future<void> main(List<String> args) async {
  final raiz = Directory(
    File.fromUri(Platform.script).parent.parent.parent.parent.path,
  );
  final registro = File('${raiz.path}/arquitectura.json');
  if (!registro.existsSync()) {
    stderr.writeln('no encuentro arquitectura.json desde ${raiz.path}');
    exit(2);
  }
  final reglas =
      (jsonDecode(registro.readAsStringSync())
              as Map<String, Object?>)['reglas']
          as Map<String, Object?>;

  // --- meta · las reglas que este verificador aplica siguen ahí ---------
  const esperadas = {
    'serializacion-sin-perdida': 'campos_derivados',
    'opacidad-declarada': 'opacidad_declarada',
    'puertos-sin-implementacion': 'huecos_declarados',
    'colecciones-inmutables': 'colecciones_copiadas',
    'subprocesos-con-entorno-saneado': 'entorno_saneado',
  };
  for (final e in esperadas.entries) {
    final r = reglas[e.key] as Map<String, Object?>?;
    if (r == null) {
      fallos.add(
        'arquitectura.json: falta la regla «${e.key}». Un control que '
        'desaparece sin ruido es F33.',
      );
      continue;
    }
    if (r['tipo'] != e.value) {
      fallos.add(
        'arquitectura.json: «${e.key}» tiene tipo «${r['tipo']}»; se '
        'esperaba «${e.value}». Cambiarlo la saltea sin borrarla.',
      );
    }
    if (r['violacion_canonica'] == null) {
      fallos.add(
        'arquitectura.json: «${e.key}» no declara violación canónica. '
        'Una regla que no puede ponerse roja no está probada.',
      );
    }
    if (r['caso_ciego'] == null) {
      fallos.add(
        'arquitectura.json: «${e.key}» no declara `caso_ciego`. Nadie '
        'probó nunca qué hace este control cuando NO PUEDE MIRAR, y su '
        'silencio es indistinguible de su aprobación (ADR-011 §5).',
      );
    }
    if (r['aplicada_por'] != 'tool/analisis') {
      fallos.add(
        'arquitectura.json: «${e.key}» ya no delega en este '
        'verificador. Quedaría registrada y sin ejecutar.',
      );
    }
  }

  final opacos =
      ((reglas['opacidad-declarada'] as Map<String, Object?>?)?['opacos']
                as Map<String, Object?>? ??
            {})
        ..remove('_');
  final sinImpl =
      ((reglas['puertos-sin-implementacion']
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
    fallos.add(
      'no encontré ninguna clase en packages/core/lib. O el paquete '
      'está vacío, o no supe leerlo: las dos cosas son rojas.',
    );
  }

  // --- 0 · identidad · dentro de core el nombre es una CLAVE -------------
  //
  // `arquitectura.json` direcciona las clases de core por su NOMBRE, y lo hace
  // en tres registros: cuáles son opacas, cuáles son puertos sin
  // implementación, y cuáles serializan. Dos clases que se llamen igual no se
  // pueden describir por separado en ninguno de los tres: la declaración de
  // una le da vía libre a la otra.
  //
  // **La herencia describe relaciones, no identidad.** Dos puertos pueden
  // tener exactamente los mismos ancestros —ninguno— y seguir siendo contratos
  // distintos. Por eso acá NO se usa el criterio estructural que sirve para
  // resolver herencia más abajo: acá cualquier duplicación es fatal.
  //
  // Medido en dos formas antes de instalarse: dos puertos homónimos con un
  // implementador dejaban huérfano al otro en verde, y dos clases homónimas
  // con una declarada opaca le daban a la otra un permiso que nadie escribió.
  final nombresDeCore = <String, List<Clase>>{};
  for (final c in clasesCore) {
    (nombresDeCore[c.nombre] ??= []).add(c);
  }
  for (final e in nombresDeCore.entries.where((e) => e.value.length > 1)) {
    fallos.add(
      '«${e.key}» está declarada ${e.value.length} veces dentro de '
      'core (${e.value.map((c) => c.archivo).join(", ")}). Los registros de '
      'arquitectura.json direccionan las clases por su nombre, así que no se '
      'pueden describir por separado y la declaración de una tapa a la otra. '
      'Renombrá una: acá el nombre no es una referencia, es una clave.',
    );
  }

  // --- 1 · serialización sin pérdida ------------------------------------
  for (final c in clasesCore) {
    if (c.esAbstracta || c.camposPublicos.isEmpty) continue;
    if (opacos.containsKey(c.nombre)) continue;
    if (c.clavesToJson == null || c.clavesFromJson == null) continue;
    final campos = c.camposPublicos.toSet();
    for (final falta in (campos.difference(c.clavesToJson!)).toList()..sort()) {
      fallos.add(
        '${c.archivo} · ${c.nombre}: el campo «$falta» no está en '
        'toJson. Se pierde en cada serialización y ningún test de ida y '
        'vuelta lo nota.',
      );
    }
    for (final sobra in (c.clavesToJson!.difference(campos)).toList()..sort()) {
      fallos.add(
        '${c.archivo} · ${c.nombre}: toJson escribe «$sobra», que no '
        'es un campo de la clase. fromJson no lo va a poder reconstruir.',
      );
    }
    for (final falta in (campos.difference(
      c.clavesFromJson!,
    )).toList()..sort()) {
      fallos.add(
        '${c.archivo} · ${c.nombre}: fromJson no lee «$falta». '
        'El campo viaja de ida y se pierde a la vuelta.',
      );
    }
    // La cuarta dirección, que faltaba. El enunciado dice EXACTAMENTE las
    // mismas claves, y se comprobaban tres de los cuatro sentidos: un
    // `fromJson` que leyera una clave inexistente pasaba en verde. Comparar
    // conjuntos en una sola dirección es media comparación.
    for (final sobra in (c.clavesFromJson!.difference(
      campos,
    )).toList()..sort()) {
      fallos.add(
        '${c.archivo} · ${c.nombre}: fromJson lee «$sobra», que no es '
        'un campo de la clase y que toJson nunca escribe. O sobra la '
        'lectura, o falta el campo.',
      );
    }
  }

  // --- 1b · y la prueba de ida y vuelta las cubre a todas ----------------
  //
  // El verificador de campos no mira VALORES, y la prueba de ida y vuelta sí,
  // pero solo sobre las clases que alguien se acordó de poner en ella. Una
  // entidad nueva sin su caso pasaba en verde por las dos: cada uno cubría lo
  // que el otro no, y el hueco quedaba entre los dos.
  final prueba = File(
    '${raiz.path}/packages/core/test/serializacion_test.dart',
  );
  if (!prueba.existsSync()) {
    fallos.add(
      'falta packages/core/test/serializacion_test.dart. Es lo único '
      'que verifica que los VALORES sobrevivan el viaje.',
    );
  } else {
    final texto = prueba.readAsStringSync();
    for (final c in clasesCore) {
      if (c.esAbstracta || c.clavesToJson == null) continue;
      if (!texto.contains("'${c.nombre}'")) {
        fallos.add(
          'packages/core/test/serializacion_test.dart: «${c.nombre}» '
          'serializa y no tiene caso canónico. Agregá una instancia con un '
          'valor distinguible en cada campo.',
        );
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
      fallos.add(
        '${c.archivo} · ${c.nombre}: el campo de colección «$campo» '
        'entra al constructor por referencia. Copialo con '
        '`List.unmodifiable(...)` o `Map.unmodifiable(...)` en la lista de '
        'inicializadores: sin eso, el invariante se puede romper DESPUÉS de '
        'construir el objeto, y entonces no es una propiedad del tipo.',
      );
    }
  }

  // --- 2 · opacidad declarada -------------------------------------------
  //
  // **Una clase sellada NO se exime por ser abstracta.** La exención existe
  // para las interfaces de puerto —comportamiento, sin datos propios que
  // perder—, pero la base de una jerarquía sellada es justo lo contrario: es
  // dato, aunque hoy no tenga un campo propio. Eximirla dejaba a
  // `StepOutcome`/`VerificationOutcome` sin serializar y sin declararse
  // opacas, la tercera opción silenciosa que esta regla existe para prohibir
  // — y sobrevivían solo porque `sealed` no admite escribir `abstract`, así
  // que el análisis nunca las contaba como clases con campos que perder.
  for (final c in clasesCore) {
    if (c.esAbstracta && !c.esSellada) continue;
    final declarada = opacos[c.nombre] as Map<String, Object?>?;
    final necesitaElegir = c.esSellada || c.camposPublicos.isNotEmpty;
    if (declarada == null) {
      if (necesitaElegir &&
          (c.clavesToJson == null || c.clavesFromJson == null)) {
        final que = c.esSellada
            ? 'es la base de una jerarquía sellada'
            : 'tiene campos';
        fallos.add(
          '${c.archivo} · ${c.nombre}: $que y no serializa, y '
          'no está declarada opaca. Escribile toJson y fromJson, o declarala '
          'en «opacidad-declarada.opacos» con su motivo.',
        );
      }
      continue;
    }
    if (c.clavesToJson != null || c.clavesFromJson != null) {
      fallos.add(
        '${c.archivo} · ${c.nombre}: está declarada opaca y sin '
        'embargo serializa. ${declarada['por_que']}',
      );
    }
    final mascara = declarada['mascara'] as String?;
    if (mascara != null && c.literalDeToString != mascara) {
      fallos.add(
        '${c.archivo} · ${c.nombre}: su toString no devuelve la '
        'máscara declarada «$mascara» como literal '
        '(leí: ${c.literalDeToString ?? 'algo que no es un literal'}). '
        'Es lo que aparece en una interpolación o en un log.',
      );
    }
  }
  for (final n in opacos.keys) {
    if (!clasesCore.any((c) => c.nombre == n)) {
      fallos.add(
        'arquitectura.json: «opacidad-declarada» declara opaca a '
        '«$n», que ya no existe en core. Una declaración vieja tapa la '
        'siguiente clase que se llame igual.',
      );
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
  // **Este mapa resuelve por NOMBRE SIMPLE, y eso solo es correcto mientras
  // no haya dos clases que se llamen igual.** Dart lo permite en bibliotecas
  // distintas, y ahí la última pisaría a la primera: una clase concreta
  // heredaría los ancestros de su homónima de otro paquete y un puerto
  // huérfano podría quedar tapado. No mirar bien no es lo mismo que no
  // encontrar nada, así que ante nombres repetidos esto FALLA en vez de
  // adivinar. Resolverlo de verdad pide identidad calificada —biblioteca más
  // símbolo— y elementos resueltos del analizador, no el árbol crudo.
  final porNombre = <String, List<Clase>>{};
  for (final c in todasLasClases) {
    (porNombre[c.nombre] ??= []).add(c);
  }

  /// Un nombre repetido solo es AMBIGUO si sus declaraciones no coinciden en
  /// lo que heredan. Si todas tienen los mismos supertipos, da igual cuál gane
  /// el mapa: la respuesta es la misma, y hacer fallar el check ahí le
  /// impondría a todo plugin futuro no repetir un nombre que ya usa otro.
  ///
  /// La primera versión de esto marcaba cualquier repetición; la segunda,
  /// ninguna que estuviera en el origen del recorrido. Ninguna de las dos era
  /// la condición: la condición es que el control NO PUEDA saber la respuesta.
  bool ambiguo(String n) {
    final decls = porNombre[n];
    if (decls == null || decls.length < 2) return false;
    final primero = decls.first.superTipos;
    return decls.any(
      (d) =>
          d.superTipos.length != primero.length ||
          !d.superTipos.every(primero.contains),
    );
  }

  final superDe = {for (final c in todasLasClases) c.nombre: c.superTipos};
  // Los nombres ambiguos de los que DEPENDE la respuesta. Se acota a esos a
  // propósito: fallar ante cualquier homónimo del repositorio le impondría a
  // todo plugin futuro no repetir un nombre que ya usa otro, y esa es una
  // restricción de diseño que este control no tiene por qué imponer.
  //
  // La respuesta depende de tres conjuntos de nombres, y son TODOS los que hay:
  // el nodo donde arranca cada búsqueda, cada nodo que la búsqueda visita, y
  // los puertos contra los que se compara al final. La primera versión de esto
  // solo marcaba el segundo, y con eso una clase concreta con homónima tomaba
  // los ancestros de la otra desde el primer paso — el mapa está indexado por
  // nombre simple y devuelve la última declaración. Un puerto huérfano quedaba
  // tapado y el check daba verde.
  final ambiguosUsados = <String>{};
  void anotarSiEsAmbiguo(String n) {
    if (ambiguo(n)) ambiguosUsados.add(n);
  }

  Set<String> ancestros(String nombre) {
    anotarSiEsAmbiguo(nombre); // el ORIGEN también decide la respuesta
    final vistos = <String>{};
    final pila = [...?superDe[nombre]];
    while (pila.isNotEmpty) {
      final n = pila.removeLast();
      if (!vistos.add(n)) continue; // corta ciclos y repeticiones
      anotarSiEsAmbiguo(n);
      pila.addAll(superDe[n] ?? const <String>{});
    }
    return vistos;
  }

  final implementados = <String>{
    for (final c in todasLasClases)
      if (!c.esAbstracta) ...ancestros(c.nombre),
  };
  // Un puerto duplicado también decide la respuesta, aunque nadie lo herede.
  puertos.forEach(anotarSiEsAmbiguo);
  for (final n in ambiguosUsados.toList()..sort()) {
    fallos.add(
      '«$n» está declarada ${porNombre[n]!.length} veces, con '
      'herencias DISTINTAS '
      '(${porNombre[n]!.map((c) => c.archivo).join(", ")}), y participa de '
      'una resolución que este control tiene que hacer. Resuelve por NOMBRE '
      'SIMPLE, así que no puede distinguirlas y no va a adivinar: renombrá '
      'una, o dale identidad calificada al control —biblioteca más símbolo— '
      'antes de creerle.',
    );
  }

  final huerfanos = puertos.where((p) => !implementados.contains(p)).toSet();
  for (final p in (huerfanos.difference(
    sinImpl.keys.toSet(),
  )).toList()..sort()) {
    fallos.add(
      'packages/core: el puerto «$p» no tiene ninguna implementación y '
      'no está declarado en «puertos-sin-implementacion». Una superficie de '
      'puertos completa se lee como un sistema que hace esas cosas.',
    );
  }
  for (final p in (sinImpl.keys.toSet().difference(
    huerfanos,
  )).toList()..sort()) {
    final motivo = puertos.contains(p)
        ? 'ya tiene implementación: sacalo de la lista.'
        : 'no es un puerto de core: la declaración quedó vieja.';
    fallos.add(
      'arquitectura.json: «puertos-sin-implementacion» declara «$p», '
      'que $motivo',
    );
  }

  // --- 4 · subprocesos con entorno saneado -------------------------------
  //
  // Se comprueba SEMÁNTICA, no forma: lo que se exige es la llamada a
  // `entornoSaneado`, no que el parámetro exista. Ver `_Subprocesos`.
  final reglaDeEntorno =
      reglas['subprocesos-con-entorno-saneado'] as Map<String, Object?>?;
  // biblioteca → el único método donde se admite un lanzamiento sin sanear.
  final exceptuadas = <String, String>{
    for (final e
        in (reglaDeEntorno?['excepciones'] as List<Object?>? ?? const []))
      (e as Map<String, Object?>)['archivo']! as String: e['metodo']! as String,
  };
  final lanzamientos = <_Lanzamiento>[];
  // **Producción es un conjunto cerrado: `lib/` y `bin/`.** Los `test/` no
  // entran: las pruebas lanzan `git` y `chmod` a mano, y esa es su forma de
  // medir qué recibe un hijo.
  final deProduccion = RegExp(r'^packages/[^/]+/(lib|bin)/');
  final candidatos = <File>[];
  for (final f in fuentes(dirPaquetes)) {
    if (!deProduccion.hasMatch(f.path.substring(raiz.path.length + 1))) {
      continue;
    }
    final parseado = parseFile(
      path: f.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    // Un archivo que no parsea ya lo reportó `clasesDe`: de un árbol parcial no
    // sale ninguna invocación, y cero se lee igual que «no tenía ninguna».
    if (parseado.errors.isNotEmpty) continue;
    final busqueda = _PareceLanzamiento();
    parseado.unit.accept(busqueda);
    if (busqueda.encontrado) candidatos.add(f);
  }
  if (candidatos.isNotEmpty) {
    // **Resuelto y no solo parseado**, porque la regla compara la IDENTIDAD de
    // lo que se invoca, no su nombre: sin resolución, una función local llamada
    // igual que la de saneamiento pasa en verde — reproducido por un review.
    //
    // Se resuelven solo los archivos que mencionan un lanzamiento, que son un
    // puñado: resolver todo el árbol costaría segundos por nada.
    final coleccion = AnalysisContextCollection(
      includedPaths: [dirPaquetes.path],
    );
    for (final f in candidatos) {
      final rel = f.path.substring(raiz.path.length + 1);
      final ctx = coleccion.contextFor(f.path);
      final r = await ctx.currentSession.getResolvedUnit(f.path);
      // **Falla cerrado.** No poder resolver no es no tener lanzamientos: es no
      // saber, y la regla entera depende de saber de dónde viene cada símbolo.
      if (r is! ResolvedUnitResult) {
        fallos.add(
          '$rel: no se pudo resolver, así que no puedo decir si sus '
          'lanzamientos de proceso usan el saneador de `core` o una homónima. '
          'Resolvé las dependencias del workspace antes de correr esto.',
        );
        continue;
      }
      final v = _Subprocesos(rel, _bibliotecaDe(r.unit, rel));
      r.unit.accept(v);
      lanzamientos.addAll(v.vistos);
    }
  }
  final sinSanear = lanzamientos.where((l) => l.problema != null).toList();
  final porBiblioteca = <String, List<_Lanzamiento>>{};
  for (final l in sinSanear) {
    (porBiblioteca[l.biblioteca] ??= []).add(l);
  }
  for (final e in porBiblioteca.entries) {
    final metodo = exceptuadas[e.key];
    if (metodo == null) {
      for (final l in e.value) {
        fallos.add(
          '${l.archivo}:${l.offset}: lanza un proceso y ${l.problema} '
          'Un hijo que hereda el entorno recibe el token de la forja y '
          'cualquier `GIT_*` del shell del usuario.',
        );
      }
      continue;
    }
    // La excepción admite EXACTAMENTE uno, y dentro del método declarado.
    for (final l in e.value.where((l) => !l.ambito.contains(metodo))) {
      fallos.add(
        '${l.archivo}:${l.offset}: la excepcion declarada para ${e.key} '
        'admite un solo lanzamiento sin sanear, dentro de `$metodo`, y este '
        'está en `${l.donde}`. ${l.problema}',
      );
    }
    final adentro = e.value.where((l) => l.ambito.contains(metodo)).length;
    if (adentro > 1) {
      fallos.add(
        '${e.key}: `$metodo` tiene $adentro lanzamientos sin sanear y la '
        'excepcion admite uno. Una excepcion que crece en silencio es una '
        'lista negra.',
      );
    }
  }
  for (final e in exceptuadas.entries) {
    if (!(porBiblioteca[e.key]?.any((l) => l.ambito.contains(e.value)) ??
        false)) {
      fallos.add(
        'arquitectura.json: «subprocesos-con-entorno-saneado» exceptua '
        '`${e.value}` en ${e.key}, y ahi no hay ningun lanzamiento sin '
        'sanear. La declaracion quedo vieja y taparia al proximo.',
      );
    }
  }

  // --- 5 · quién es la forja lo sabe packages/forge/, y nadie más -------
  //
  // Universo por RUTA, la exigencia dura de CLAUDE.md: `.dart` bajo `lib/` y
  // `bin/` de cada paquete MENOS `forge`. Ni un prefiltro de texto ni una
  // coincidencia de import deciden qué archivo entra — lo decide la ruta, acá
  // y no en ningún otro lado.
  //
  // Dos criterios, ninguno resuelve el árbol (ver `_Forja`):
  //   1. un identificador `HttpClient`, sintáctico;
  //   2. el nombre de marca de la forja o su host, como TEXTO —fuera de
  //      comentarios, ver `_ocurrenciasFueraDeComentarios`.
  const nombreDeLaForja = 'GitHub';
  const hostDeLaForja = 'github.com';
  final fueraDeForge = RegExp(r'^packages/([^/]+)/(lib|bin)/');
  final archivosDeLaForja = <File>[];
  for (final f in fuentes(dirPaquetes)) {
    final rel = f.path.substring(raiz.path.length + 1);
    final m = fueraDeForge.firstMatch(rel);
    if (m != null && m.group(1) != 'forge') archivosDeLaForja.add(f);
  }
  for (final f in archivosDeLaForja) {
    final rel = f.path.substring(raiz.path.length + 1);
    final resultado = parseFile(
      path: f.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    // Simétrico de la violación canónica: de un árbol parcial no sale ningún
    // `HttpClient`, y del texto que el parser no pudo tokenizar no se sabe
    // qué es comentario y qué es código. No mirar no es lo mismo que no
    // encontrar nada, así que esto es un fallo y no un salteo.
    if (resultado.errors.isNotEmpty) {
      fallos.add(
        '$rel: no parsea, así que no puedo decir si nombra a la forja o '
        'instancia un `HttpClient` por su cuenta. '
        '${resultado.errors.first.message}',
      );
      continue;
    }

    final buscador = _Forja();
    resultado.unit.accept(buscador);
    for (final m in buscador.vistos) {
      fallos.add(
        '$rel:${m.offset} · ${m.donde}: instancia `HttpClient` fuera de '
        '`packages/forge`. Quién es la forja lo sabe forge y ningún otro '
        'paquete: si esto necesita hablar por HTTP con el proveedor, ese '
        'código va en su adapter.',
      );
    }

    final comentarios = _rangosDeComentarios(resultado.unit);
    for (final offset in _ocurrenciasFueraDeComentarios(
      resultado.content,
      nombreDeLaForja,
      comentarios,
    )) {
      fallos.add(
        '$rel:$offset · ${buscador.ambitoEn(offset)}: nombra a la forja '
        '(«$nombreDeLaForja») fuera de `packages/forge`. Quién es la forja '
        'lo sabe forge y ningún otro paquete.',
      );
    }
    for (final offset in _ocurrenciasFueraDeComentarios(
      resultado.content,
      hostDeLaForja,
      comentarios,
    )) {
      fallos.add(
        '$rel:$offset · ${buscador.ambitoEn(offset)}: nombra el host de la '
        'forja («$hostDeLaForja») fuera de `packages/forge`. Quién es la '
        'forja lo sabe forge y ningún otro paquete.',
      );
    }
  }

  // --- salida -----------------------------------------------------------
  if (fallos.isNotEmpty) {
    stdout.writeln('serializacion: FALLA\n');
    for (final f in fallos) {
      stdout.writeln('  $f');
    }
    exit(1);
  }
  final serializables = clasesCore
      .where((c) => !c.esAbstracta && c.clavesToJson != null)
      .length;
  stdout.writeln(
    'serializacion: ok — $serializables clases serializables '
    'verificadas campo por campo, ${opacos.length} opacas declaradas, '
    '${huerfanos.length} puertos sin implementación declarados, '
    '${lanzamientos.length} lanzamientos de proceso con entorno saneado '
    '(${sinSanear.length} exceptuado). '
    'forja: ok — ${archivosDeLaForja.length} archivos revisados fuera de '
    '`forge`, sin `HttpClient` ni mención al proveedor.',
  );
}
