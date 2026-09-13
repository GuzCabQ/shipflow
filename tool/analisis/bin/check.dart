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

/// Las cifras que el README afirma de la cascada, **derivadas del árbol
/// sintáctico**.
///
/// **Vivía en `capas.py` y contaba corchetes sobre el texto.** Una revisión lo
/// reprodujo: un `]` dentro de un comentario —`// ]`— hacía que el recorte
/// cerrara ahí, y con el recorte incluyendo UN paso ningún guardia disparaba.
/// El README podía afirmar un paso donde había dos y el check quedaba verde.
/// El propio comentario de aquel parser decía que el llamador lo cazaría; era
/// falso.
///
/// Contar caracteres no se arregla contando mejor: se arregla preguntándole al
/// analizador, que es quien sabe qué es un comentario y qué es un corchete. Es
/// el mismo criterio con el que el grafo se le pide a pub y el workflow a un
/// parser de YAML.
void _cifrasDeLaCascada(Directory raiz, String readme) {
  final fuente = File('${raiz.path}/packages/cli/lib/src/verify.dart');
  if (!fuente.existsSync()) {
    fallos.add(
      'no encontré packages/cli/lib/src/verify.dart, así que no puedo '
      'derivar el presupuesto por paso. No mirar no es lo mismo que no '
      'encontrar nada.',
    );
    return;
  }
  final r = parseString(
    content: fuente.readAsStringSync(),
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  // Mismo criterio que `clasesDe`: un archivo que no parsea devuelve un árbol
  // PARCIAL, y de un árbol parcial no sale nada — que se lee igual que «no
  // había nada que verificar».
  for (final d in r.errors) {
    fallos.add(
      'packages/cli/lib/src/verify.dart:${d.offset}: no parsea, así '
      'que no pude derivar la cascada. ${d.message}',
    );
  }
  if (r.errors.isNotEmpty) return;

  final buscador = _CascadaPorDefecto();
  r.unit.accept(buscador);
  if (buscador.ambiguedad != null) {
    fallos.add(
      'no pude derivar la cascada de `cascadaPorDefecto`: '
      '${buscador.ambiguedad}. Esta derivación falla cerrada a propósito — '
      'una forma que no sabe leer no se saltea, porque saltearla deja la '
      'cifra del README sin nadie que la contradiga.',
    );
    return;
  }
  if (buscador.lista == null) {
    fallos.add(
      'no encontré la lista de pasos de `cascadaPorDefecto` en '
      'verify.dart. Si cambió de forma hay que reapuntar esta derivación, no '
      'borrarla: un patrón que no encuentra nada no comprueba nada.',
    );
    return;
  }

  // **Todo elemento tiene que tener una forma que esta derivación sepa leer.**
  //
  // Antes se filtraba con `whereType<Expression>()`, y eso descartaba en
  // silencio los `CollectionElement` que no son expresiones: `...spread`, `if`
  // y `for`. Una revisión lo reprodujo metiendo los pasos por un spread — la
  // cascada corría dos, el README declaraba uno, y el verificador salía con
  // cero. Interpretar el árbol a medias y omitir lo no reconocido es
  // exactamente lo que ADR-011 llama no poder medir y llamarlo aprobación.
  final pasos = <Expression>[];
  for (final elemento in buscador.lista!.elements) {
    if (elemento is InstanceCreationExpression) {
      pasos.add(elemento);
      continue;
    }
    if (elemento is MethodInvocation) {
      pasos.add(elemento);
      continue;
    }
    fallos.add(
      'la lista de pasos de `cascadaPorDefecto` tiene un elemento de '
      'forma `${elemento.runtimeType}`, que esta derivación no sabe contar. '
      'Un `...spread`, un `if` o un `for` pueden aportar cualquier cantidad '
      'de pasos, y saltearlos deja la cifra del README sin quien la '
      'contradiga. Escribilos como elementos literales, o enseñale a leer esa '
      'forma — no la omitas.',
    );
  }
  if (fallos.isNotEmpty) return;
  if (pasos.isEmpty) {
    fallos.add(
      'conté cero pasos en `cascadaPorDefecto`. Cero se lee igual que '
      '«no miré».',
    );
    return;
  }
  if (buscador.minutos == null) {
    fallos.add(
      'no encontré el presupuesto por defecto en verify.dart. Si '
      'cambió de forma, esta derivación dejó de mirar algo y hay que '
      'arreglarla, no borrarla.',
    );
    return;
  }
  final minutos = buscador.minutos!;

  // **Y que cada paso reciba EXACTAMENTE ese presupuesto.** Contar
  // constructores sin leer sus argumentos dejaba pasar un paso con
  // `presupuesto * 2`: la cifra del README multiplica UN valor por la cantidad
  // de pasos, así que con presupuestos distintos deja de significar lo que dice.
  for (final paso in pasos) {
    final args = paso is InstanceCreationExpression
        ? paso.argumentList.arguments
        : paso is MethodInvocation
        ? paso.argumentList.arguments
        : const <Expression>[];
    final dado = args
        .whereType<NamedExpression>()
        .where((a) => a.name.label.name == 'presupuesto')
        .map((a) => a.expression)
        .firstOrNull;
    if (dado == null) {
      fallos.add(
        'un paso de `cascadaPorDefecto` no recibe presupuesto '
        'explícito, así que no está cubierto por esta cuenta.',
      );
      continue;
    }
    if (!(dado is SimpleIdentifier && dado.name == 'presupuesto')) {
      fallos.add(
        'un paso de `cascadaPorDefecto` recibe «$dado» como '
        'presupuesto y no el parámetro. La cifra del README multiplica UN '
        'valor por la cantidad de pasos: con presupuestos distintos deja de '
        'significar lo que dice.',
      );
    }
  }

  for (final (patron, esperado, que) in [
    (
      RegExp(r'un default de \*\*(\d+) minutos\*\*'),
      minutos,
      'el presupuesto por paso',
    ),
    (
      RegExp(r'Con los (\d+) pasos de hoy'),
      pasos.length,
      'los pasos de la cascada',
    ),
    (
      RegExp(r'una corrida puede tardar\s+(\d+) minutos'),
      minutos * pasos.length,
      'el peor caso de una corrida',
    ),
  ]) {
    final m = patron.firstMatch(readme);
    if (m == null) {
      fallos.add(
        'README.md ya no afirma $que en la forma que esta derivación '
        'reconoce. Un patrón que no encuentra nada no comprueba nada, y se '
        'lee igual que uno que sí.',
      );
    } else if (int.parse(m.group(1)!) != esperado) {
      fallos.add('README.md dice «${m.group(0)}»; $que da $esperado.');
    }
  }
}

/// Encuentra la lista de pasos **de la cascada que `cascadaPorDefecto`
/// retorna**, y su presupuesto por defecto.
///
/// **La primera `Cascada(` que aparezca no sirve.** Una versión anterior
/// recorría el cuerpo y se quedaba con la primera: una revisión lo reprodujo
/// agregando, antes del `return`, una rama condicional que construye una
/// cascada de un paso. La retornada seguía teniendo dos, el README declaraba
/// uno, y todo quedaba verde. Una llamada auxiliar, una rama futura o un
/// closure pueden volverse la fuente documental por accidente.
///
/// Así que se busca el `return` —uno solo— y se deriva **su** expresión. Más de
/// uno es ambiguo, y ambiguo falla: elegir cuál mirar sería adivinar.
class _CascadaPorDefecto extends RecursiveAstVisitor<void> {
  ListLiteral? lista;
  int? minutos;
  String? ambiguedad;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.name.lexeme != 'cascadaPorDefecto') return;

    for (final p
        in node.functionExpression.parameters?.parameters ??
            const <FormalParameter>[]) {
      if (p.name?.lexeme != 'presupuesto') continue;
      final d = p is DefaultFormalParameter ? p.defaultValue : null;
      final args = d is InstanceCreationExpression
          ? d.argumentList.arguments
          : const <Expression>[];
      for (final a in args.whereType<NamedExpression>()) {
        if (a.name.label.name != 'minutes') continue;
        final v = a.expression;
        if (v is IntegerLiteral) minutos = v.value;
      }
    }

    final cuerpo = node.functionExpression.body;
    Expression? retornada;
    if (cuerpo is ExpressionFunctionBody) {
      retornada = cuerpo.expression;
    } else {
      final retornos = <ReturnStatement>[];
      cuerpo.accept(_Retornos(retornos));
      if (retornos.length != 1) {
        ambiguedad =
            'tiene ${retornos.length} `return`, y hace falta uno solo '
            'para saber cuál cascada es la que se usa';
        return;
      }
      retornada = retornos.single.expression;
    }
    if (retornada == null) {
      ambiguedad = 'su `return` no lleva expresión';
      return;
    }

    final args = _argumentosDe(retornada, 'Cascada');
    if (args == null) {
      ambiguedad =
          'lo que retorna no es una llamada a `Cascada`, sino '
          '`${retornada.runtimeType}`';
      return;
    }
    final primero = args.arguments.firstOrNull;
    if (primero is! ListLiteral) {
      ambiguedad = 'el primer argumento de `Cascada` no es una lista literal';
      return;
    }
    lista = primero;
  }
}

/// Todos los `return` del cuerpo, **incluidos los de closures anidados**.
///
/// Contarlos de más es deliberado: con un closure que retorna adentro, esta
/// derivación no puede saber cuál es el de la función, y prefiere declararse
/// ambigua a elegir.
class _Retornos extends RecursiveAstVisitor<void> {
  _Retornos(this.encontrados);
  final List<ReturnStatement> encontrados;

  @override
  void visitReturnStatement(ReturnStatement node) {
    encontrados.add(node);
    super.visitReturnStatement(node);
  }
}

/// Los argumentos de una llamada a [nombre], venga como constructor o como
/// invocación.
///
/// **Sin resolución, `Cascada([...])` es un `MethodInvocation`.** El analizador
/// sin resolver no distingue un constructor de una función: solo `new` o
/// `const` llegan como `InstanceCreationExpression`. Buscar solo esa forma era
/// buscar una que el código no tiene, y la primera versión de esta derivación
/// reportó «no encontré la lista» sobre un árbol sano.
ArgumentList? _argumentosDe(Expression e, String nombre) {
  if (e is MethodInvocation && e.methodName.name == nombre) {
    return e.argumentList;
  }
  if (e is InstanceCreationExpression &&
      e.constructorName.type.name.lexeme == nombre) {
    return e.argumentList;
  }
  return null;
}

/// Un lanzamiento de proceso, y si cumple la regla del entorno saneado.
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
/// la función tiene que ser la de `core`, y `Process` tiene que ser la de la
/// biblioteca de entrada y salida del SDK. Una clase local homónima abriría el
/// mismo agujero por el otro lado.
class _Subprocesos extends RecursiveAstVisitor<void> {
  _Subprocesos(this.archivo, this.biblioteca);

  final String archivo;
  final String biblioteca;
  final List<_Lanzamiento> vistos = [];
  final List<String> _pila = [];

  static const _lanzadores = {'run', 'runSync', 'start'};

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
    final destino = node.target;
    if (destino?.toSource() != 'Process' ||
        !_lanzadores.contains(node.methodName.name)) {
      return;
    }
    final nombrados = {
      for (final a in node.argumentList.arguments)
        if (a is NamedExpression) a.name.label.name: a.expression,
    };
    final entorno = nombrados['environment'];
    final hereda = nombrados['includeParentEnvironment'];
    String? problema;
    // **Que `Process` sea el del SDK también se comprueba.** Una clase local
    // con ese nombre abriría el mismo agujero por el otro lado: el control
    // creería estar mirando un lanzamiento y estaría mirando otra cosa.
    final origenDeProcess = destino is Identifier
        ? _bibliotecaDe(destino.element)
        : '';
    if (origenDeProcess != _origenDeProcess) {
      problema =
          '`Process` acá no es el de la biblioteca de entrada y salida del '
          'SDK, sino ${origenDeProcess.isEmpty ? "un símbolo que no se pudo "
                    "resolver" : "«$origenDeProcess»"}. Este control no puede decir '
          'qué lanza.';
    } else if (entorno is! MethodInvocation ||
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

  _cifrasDeLaCascada(raiz, File('${raiz.path}/README.md').readAsStringSync());

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
  final candidatos = [
    for (final f in fuentes(dirPaquetes))
      if (deProduccion.hasMatch(f.path.substring(raiz.path.length + 1)) &&
          f.readAsStringSync().contains('Process.'))
        f,
  ];
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
    '(${sinSanear.length} exceptuado).',
  );
}
