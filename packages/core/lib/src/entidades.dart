/// Las entidades del dominio. Dato plano y serializable (ADR-002).
library;

import 'valores.dart';

/// Un criterio de aceptación, con su traducción a aserción ejecutable.
///
/// [assertionForm] es un **identificador opaco**: el catálogo de formas lo
/// declara el plugin del stack, no `core` (ADR-016). Que sea `null` es un
/// estado legítimo y visible — significa que el criterio todavía no se mapeó—,
/// y es lo que INV-1 mira para decidir si el [WorkItem] entra.
class AcceptanceCriterion {
  final String id;

  /// El criterio como lo escribió quien lo pidió. Texto externo (INV-6).
  final QuotedText statement;

  /// Id de la forma de aserción del catálogo del plugin, o `null`.
  final String? assertionForm;

  AcceptanceCriterion({
    required this.id,
    required this.statement,
    this.assertionForm,
  }) {
    // `''` no es el identificador de ninguna forma del catálogo. Permitirlo
    // dejaba pasar un criterio «mapeado» a nada, y INV-1 miraba solo si el
    // campo era nulo. Se rechaza en el constructor para que el estado sea
    // irrepresentable, no para que el getter lo compense.
    if (assertionForm != null && assertionForm!.trim().isEmpty) {
      throw ArgumentError.value(
        assertionForm,
        'assertionForm',
        'Una forma de aserción vacía no es una forma. Dejalo en `null` si el '
            'criterio todavía no se mapeó: `null` es un estado legítimo y visible.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'statement': statement.toJson(),
    'assertionForm': assertionForm,
  };

  factory AcceptanceCriterion.fromJson(Map<String, Object?> json) =>
      AcceptanceCriterion(
        id: json['id']! as String,
        statement: QuotedText.fromJson(
          Map<String, Object?>.from(json['statement']! as Map),
        ),
        assertionForm: json['assertionForm'] as String?,
      );
}

/// La unidad de trabajo, canónica y agnóstica de su fuente.
///
/// Todo lo específico del sistema de origen va en [sourceMetadata] (`D-015`):
/// el cubículo opaco que le da lugar legal a lo del adapter. **Sin esa
/// escotilla lo específico se filtra al contrato**, y ahí es donde aparecen
/// los campos que nombran un sistema externo (`D-014`).
class WorkItem {
  final String id;

  /// Título tal como llegó (INV-6).
  final QuotedText title;

  /// Descripción tal como llegó (INV-6).
  final QuotedText description;

  final List<AcceptanceCriterion> criteria;

  /// Escotilla `D-015`. `core` no lo interpreta: lo transporta.
  final Map<String, Object?> sourceMetadata;

  /// Las colecciones se copian a vistas inmodificables: sin eso, quien
  /// conservara la lista original podía vaciarla y cambiar `allCriteriaMapped`
  /// después de construir el ítem. Un invariante que se puede alterar tras el
  /// constructor no es una propiedad del tipo.
  WorkItem({
    required this.id,
    required this.title,
    required this.description,
    required List<AcceptanceCriterion> criteria,
    Map<String, Object?> sourceMetadata = const {},
  }) : criteria = List.unmodifiable(criteria),
       sourceMetadata = Map.unmodifiable(sourceMetadata);

  /// INV-1: no entra si algún criterio no se mapeó a una forma del catálogo.
  ///
  /// `core` verifica que la forma **esté**; que exista en el catálogo lo
  /// verifica quien tenga el catálogo. La división es deliberada: `core` no
  /// conoce ningún stack.
  bool get allCriteriaMapped =>
      criteria.isNotEmpty &&
      criteria.every((c) => (c.assertionForm ?? '').trim().isNotEmpty);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title.toJson(),
    'description': description.toJson(),
    'criteria': [for (final c in criteria) c.toJson()],
    'sourceMetadata': sourceMetadata,
  };

  factory WorkItem.fromJson(Map<String, Object?> json) => WorkItem(
    id: json['id']! as String,
    title: QuotedText.fromJson(
      Map<String, Object?>.from(json['title']! as Map),
    ),
    description: QuotedText.fromJson(
      Map<String, Object?>.from(json['description']! as Map),
    ),
    criteria: [
      for (final c in json['criteria']! as List<Object?>)
        AcceptanceCriterion.fromJson(Map<String, Object?>.from(c! as Map)),
    ],
    sourceMetadata: Map<String, Object?>.from(json['sourceMetadata']! as Map),
  );
}

/// Clase de cambio. **Identificador opaco** (docs/03 §4).
///
/// El catálogo lo declara el plugin. `core` sabe que existe una clasificación
/// y que selecciona estrategia; no sabe cuáles son las clases ni qué
/// significan. Si `core` empezara a nombrarlas, la dependencia se invirtió.
class ChangeClass {
  final String id;

  const ChangeClass(this.id);

  Map<String, Object?> toJson() => {'id': id};

  factory ChangeClass.fromJson(Map<String, Object?> json) =>
      ChangeClass(json['id']! as String);

  @override
  bool operator ==(Object other) => other is ChangeClass && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Un hallazgo **determinista**, normalizado desde la salida de una herramienta.
///
/// Distinto de [Finding], que es inferencial. Este puede bloquear según su
/// [severity]; aquel no puede, y no puede **por construcción** (ADR-006).
///
/// El id de la regla es una cadena genérica a propósito: si este tipo ganara un
/// campo con el nombre de un analizador concreto, la dependencia se invirtió
/// (docs/03 §3).
class Diagnostic {
  final String file;

  /// `null` cuando la herramienta no reporta línea. Es un dato, no un cero.
  final int? line;

  final Severity severity;
  final String ruleId;

  /// El mensaje de la herramienta, sin reescribir (INV-6).
  final QuotedText message;

  /// Escotilla `D-015` para lo que solo entiende el normalizador.
  final Map<String, Object?> sourceMetadata;

  Diagnostic({
    required this.file,
    required this.severity,
    required this.ruleId,
    required this.message,
    this.line,
    Map<String, Object?> sourceMetadata = const {},
  }) : sourceMetadata = Map.unmodifiable(sourceMetadata);

  Map<String, Object?> toJson() => {
    'file': file,
    'line': line,
    'severity': severity.name,
    'ruleId': ruleId,
    'message': message.toJson(),
    'sourceMetadata': sourceMetadata,
  };

  factory Diagnostic.fromJson(Map<String, Object?> json) => Diagnostic(
    file: json['file']! as String,
    line: json['line'] as int?,
    severity: Severity.values.byName(json['severity']! as String),
    ruleId: json['ruleId']! as String,
    message: QuotedText.fromJson(
      Map<String, Object?>.from(json['message']! as Map),
    ),
    sourceMetadata: Map<String, Object?>.from(json['sourceMetadata']! as Map),
  );
}

/// Unidad de topología del proyecto que se está trabajando.
///
/// La reporta el puerto de topología, que implementa el plugin del stack.
class Package {
  final String name;
  final String path;
  final List<String> dependsOn;

  Package({
    required this.name,
    required this.path,
    required List<String> dependsOn,
  }) : dependsOn = List.unmodifiable(dependsOn);

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'dependsOn': dependsOn,
  };

  factory Package.fromJson(Map<String, Object?> json) => Package(
    name: json['name']! as String,
    path: json['path']! as String,
    dependsOn: List<String>.from(json['dependsOn']! as List<Object?>),
  );
}

/// Una rebanada del trabajo que se propone como un PR.
class PullRequestSlice {
  final String id;

  /// Por qué existe esta rebanada. Es lo que ADR-014 llama intención.
  final String intent;

  final List<String> files;

  PullRequestSlice({
    required this.id,
    required this.intent,
    required List<String> files,
  }) : files = List.unmodifiable(files);

  Map<String, Object?> toJson() => {'id': id, 'intent': intent, 'files': files};

  factory PullRequestSlice.fromJson(Map<String, Object?> json) =>
      PullRequestSlice(
        id: json['id']! as String,
        intent: json['intent']! as String,
        files: List<String>.from(json['files']! as List<Object?>),
      );
}

/// El plan de un cambio: qué archivos, qué pruebas, y en cuántos PRs.
class Plan {
  final String workItemId;
  final List<String> files;
  final List<String> tests;
  final List<PullRequestSlice> slices;

  Plan({
    required this.workItemId,
    required List<String> files,
    required List<String> tests,
    required List<PullRequestSlice> slices,
  }) : files = List.unmodifiable(files),
       tests = List.unmodifiable(tests),
       slices = List.unmodifiable(slices);

  Map<String, Object?> toJson() => {
    'workItemId': workItemId,
    'files': files,
    'tests': tests,
    'slices': [for (final s in slices) s.toJson()],
  };

  factory Plan.fromJson(Map<String, Object?> json) => Plan(
    workItemId: json['workItemId']! as String,
    files: List<String>.from(json['files']! as List<Object?>),
    tests: List<String>.from(json['tests']! as List<Object?>),
    slices: [
      for (final s in json['slices']! as List<Object?>)
        PullRequestSlice.fromJson(Map<String, Object?>.from(s! as Map)),
    ],
  );
}

// **El OID vive acá, con la identidad del candidato, y no con el desenlace de
// publicar.** Lo que sigue define qué ES un identificador de objeto de git y
// cómo se escribe; lo usan las dos fronteras que reciben uno —[CandidateIdentity],
// unas líneas más abajo, y `PullRequestRequest`, en el módulo de la
// publicación— y una de ellas es este mismo archivo, así que tenerlo allá
// obligaba a que este archivo, que está más abajo, importara al que está más
// arriba.

/// Los DOS largos que puede tener un OID completo de git, **medidos, no
/// supuestos**, con `git rev-parse HEAD` sobre dos repositorios recién
/// creados con git 2.50.1:
///
/// - `--object-format=sha1` → 40 caracteres hexadecimales (160 bits).
/// - `--object-format=sha256` → 64 caracteres hexadecimales (256 bits).
///
/// Las dos familias entran porque el repositorio que se empuja puede ser de
/// cualquiera de las dos y `core` no elige por el usuario: aceptar solo
/// SHA-1 rechazaría revisiones perfectamente válidas de un repositorio
/// SHA-256, que es el mismo tipo de falso rechazo que esta validación existe
/// para no cometer.
///
/// **Mayúsculas incluidas, y también está medido**: `git rev-parse` y
/// `git cat-file -t` resuelven sin chistar un OID escrito en mayúsculas y
/// devuelven el objeto. O sea que un OID en mayúsculas ES un OID completo
/// válido; rechazarlo sería afirmar «esto no identifica ningún objeto» sobre
/// algo que sí lo identifica. Lo que producen nuestros propios adapters es
/// minúscula —es lo que git imprime—, así que esta tolerancia no relaja
/// ninguna ruta de este repositorio: solo evita mentir sobre una entrada
/// legítima.
///
/// **Y tolerar dos escrituras no es dejarlas circular:** quien acepta un OID
/// en mayúsculas lo canonicaliza a minúsculas en la frontera —ver
/// [PullRequestRequest.revision]—, porque río abajo hay comparaciones
/// literales contra lo que devuelve la forja, y dos formas del mismo objeto
/// ahí adentro se leen como dos objetos distintos.
final RegExp _patronDeOidCompleto = RegExp(
  r'^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$',
);

/// ¿[revision] es un OID completo de git?
///
/// **Es una función del dominio y no un detalle del adapter** porque el
/// dominio es donde nace la revisión que después se interpola en un refspec:
/// [PullRequestRequest] la exige al construirse, y `EmpujeAislado` la vuelve
/// a exigir justo antes de lanzar el proceso. Son dos fronteras distintas —un
/// invariante de construcción y una precondición de ejecución—, y ninguna de
/// las dos puede delegar en la otra: la primera no sabe si alguien llegará
/// por otro camino, y la segunda no puede confiar en que su llamador validó.
///
/// **Lo que NO dice**: que el objeto exista en el repositorio. Eso solo lo
/// sabe git, y averiguarlo desde acá sería lanzar un proceso adentro de una
/// validación sincrónica del dominio. Un OID bien formado que no existe lo
/// rechaza `git push` con su propio mensaje, y ESE rechazo no borra nada;
/// el que borra es el refspec sin revisión, que es justamente lo que esta
/// función impide construir.
bool esOidCompleto(String revision) => _patronDeOidCompleto.hasMatch(revision);

/// La forma canónica de un OID: **minúsculas**, que es lo que imprime git y lo
/// que devuelven las forjas.
///
/// **Y solo toca lo que ES un OID completo.** Cualquier otra cadena vuelve
/// intacta, y eso no es prudencia: `CandidateIdentity` declara su
/// representación OPACA para el dominio —un doble puede identificar el
/// contenido como se le ocurra, con mayúsculas que signifiquen algo—, así que
/// bajar de caso a ciegas podría fundir dos identidades distintas en una. Lo
/// que esta función sabe es una sola cosa, y la sabe el dominio desde que
/// existe [esOidCompleto]: dos escrituras de un mismo OID nombran el mismo
/// objeto de git.
///
/// **Residuo declarado:** una identidad opaca que por casualidad tenga la
/// forma de un OID —40 o 64 caracteres hexadecimales— y además distinga
/// mayúsculas caería en esta canonicalización. Es una representación que
/// nadie usa hoy; distinguirla pediría un tipo que diga si la identidad es un
/// OID o no, que es un cambio de dominio y no de esta ronda.
String canonicalizarOid(String revision) =>
    esOidCompleto(revision) ? revision.toLowerCase() : revision;

/// Qué contenido exacto se expuso a la cascada, y sobre qué base.
///
/// **Es una identidad opaca para el dominio.** En el adapter de git
/// [contentRevision] es el OID de un `tree` y [baseRevision] el de un commit,
/// pero `core` no lo sabe ni puede saberlo: un doble puede usar cualquier otra
/// representación mientras sostenga la única cláusula que importa —dos
/// preparaciones del mismo contenido dan la misma [contentRevision], y una
/// distinta da otra—.
///
/// **Por qué el contenido es un árbol y no un digest por ruta.** Está medido:
/// con `text eol=lf`, con un filtro `clean` o con `core.autocrlf`, los bytes
/// que git guarda **no** son los del archivo de trabajo; con un filtro no
/// determinista el mismo archivo sin tocar da dos objetos distintos en dos
/// stagings; un cambio de bit ejecutable **conserva** el objeto del archivo y
/// cambia el commit; y un borrado no tiene ningún objeto resultante, así que
/// un digest obligatorio por ruta es un tipo mal formado. Un árbol cubre
/// contenido, modo, altas, modificaciones y bajas con un solo identificador.
///
/// Lo que esto garantiza es **identidad del objeto**, nunca cobertura: que el
/// contenido expuesto a los controles sea el mismo que se commitea no dice que
/// ningún control lo haya mirado entero. Eso lo acota cada afirmación, y solo
/// hasta los sujetos de su propio testigo.
class CandidateIdentity {
  /// Qué contenido se expuso a la cascada. **Canónico si es un OID completo**
  /// —ver el constructor—; cualquier otra representación queda tal cual.
  final String contentRevision;

  /// Sobre qué base se construyó. Es la condición del commit: si la rama se
  /// movió, el cambio no se aplica. Con la misma canonicalización que
  /// [contentRevision].
  final String baseRevision;

  /// **Lo único que este constructor le hace al valor: llevarlo a la forma
  /// canónica CUANDO es un OID completo.**
  ///
  /// La opacidad de arriba sigue en pie: `canonicalizarOid` deja intacta toda
  /// cadena que no sea un OID, así que un doble que identifique el contenido
  /// con cualquier otra representación —mayúsculas incluidas— conserva sus
  /// identidades exactamente como las escribió.
  ///
  /// Hace falta porque esta identidad se COMPARA contra un árbol que llega por
  /// otra frontera: `PullRequestRequest` exige que el árbol del commit sea
  /// este mismo valor, y con las dos escrituras de un mismo OID circulando, esa
  /// comparación afirmaba que el commit llevaba un árbol que los controles no
  /// vieron. Canonicalizar en las dos fronteras deja la comparación literal,
  /// que es lo que tiene que ser.
  CandidateIdentity({
    required String contentRevision,
    required String baseRevision,
  }) : contentRevision = canonicalizarOid(contentRevision),
       baseRevision = canonicalizarOid(baseRevision) {
    if (contentRevision.trim().isEmpty || baseRevision.trim().isEmpty) {
      throw ArgumentError(
        'Una identidad de candidato en blanco no identifica nada.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'contentRevision': contentRevision,
    'baseRevision': baseRevision,
  };

  factory CandidateIdentity.fromJson(Map<String, Object?> json) =>
      CandidateIdentity(
        contentRevision: json['contentRevision']! as String,
        baseRevision: json['baseRevision']! as String,
      );
}

/// Por qué una ruta del candidato no se pudo materializar.
///
/// **Es vocabulario del dominio, no del sistema de versiones.** Antes esto era
/// el modo del árbol —`120000`, `160000`— y contradecía a [CandidateIdentity],
/// que declara opaca la representación del VCS. Un motivo cerrado dice lo que
/// el llamador necesita decidir sin obligarlo a saber cómo lo codifica `git`.
enum MotivoDeNoMaterializacion {
  /// Un enlace que no se puede reproducir dentro del candidato. Recrearlo
  /// dejaría que una herramienta lo siguiera y leyera algo que ningún testigo
  /// cubre.
  enlaceQueNoQuedaAdentro,

  /// Una referencia a otro repositorio. No es contenido de este árbol.
  referenciaAOtroRepositorio,
}

/// Una ruta que el candidato **contiene y no materializó**, con su motivo.
///
/// **No se recorta en silencio.** Quitarla de la lista convertiría una fuga o
/// un hueco en un dato con aspecto correcto.
class RutaNoMaterializada {
  final String ruta;
  final MotivoDeNoMaterializacion motivo;

  /// Qué se encontró, en concreto. Nunca en blanco: el motivo dice la
  /// categoría, y esto dice el caso.
  final String detalle;

  RutaNoMaterializada({
    required this.ruta,
    required this.motivo,
    required this.detalle,
  }) {
    if (ruta.trim().isEmpty) {
      throw ArgumentError.value(
        ruta,
        'ruta',
        'Una ruta en blanco no nombra nada.',
      );
    }
    if (detalle.trim().isEmpty) {
      throw ArgumentError.value(
        detalle,
        'detalle',
        'Una ruta declarada sin detalle no declara nada.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'ruta': ruta,
    'motivo': motivo.name,
    'detalle': detalle,
  };

  factory RutaNoMaterializada.fromJson(Map<String, Object?> json) =>
      RutaNoMaterializada(
        ruta: json['ruta']! as String,
        motivo: MotivoDeNoMaterializacion.values.byName(
          json['motivo']! as String,
        ),
        detalle: json['detalle']! as String,
      );
}

/// Con qué toolchain se derivó el entorno del candidato.
///
/// La identidad del contenido nombra el lockfile commiteado, **no todos los
/// bytes que se ejecutan**: la versión de la herramienta queda afuera, y por
/// eso se atestigua.
///
/// **No se parsea la versión. Se cita.** Un número extraído de una frase es un
/// parser más, y lo que hace falta es que el testigo diga con qué se midió, no
/// que alguien compare versiones.
class IdentidadDeToolchain {
  final QuotedText version;

  IdentidadDeToolchain({required this.version}) {
    if (version.content.trim().isEmpty) {
      throw ArgumentError.value(
        version,
        'version',
        'Una toolchain que no dice qué versión es no identifica nada.',
      );
    }
  }

  Map<String, Object?> toJson() => {'version': version.toJson()};

  factory IdentidadDeToolchain.fromJson(Map<String, Object?> json) =>
      IdentidadDeToolchain(
        version: QuotedText.fromJson(json['version']! as Map<String, Object?>),
      );
}

/// Qué le pasó a una entrada versionada del candidato.
enum TipoDeAlteracion {
  modificada,
  borrada,

  /// El modo cambió —el bit ejecutable, típicamente—.
  ///
  /// **Residuo declarado:** la comparación no hashea el árbol de trabajo, así
  /// que si el contenido cambió A LA VEZ que el modo, se reporta esto y no
  /// [modificada]. Es una alteración igual, y la corrida es no concluyente
  /// igual; lo que no se puede es leer el tipo como «solo cambió el modo».
  cambioDeModo,

  /// Un archivo regular donde el árbol tiene un enlace, o al revés.
  cambioDeTipo,

  /// Una ruta que **no está en el árbol fijado** y apareció en el candidato.
  ///
  /// **No toda ruta nueva cuenta**, pero tampoco ninguna: cuenta la que la
  /// política de artefactos del stack **no** declara artefacto. Derivar el
  /// entorno genera archivos, y generarlos es su trabajo; un archivo de fuente
  /// nuevo, un manifiesto nuevo o un efecto lateral de un verificador **no** son
  /// eso, y
  /// la cascada los lee igual que a los demás.
  agregada,
}

/// El candidato **dejó de ser el árbol que dice representar**.
///
/// Vacío significa intacto. Cubre dos cosas distintas: una entrada versionada
/// que cambió, y una ruta nueva que la política de artefactos no declara
/// artefacto — [TipoDeAlteracion.agregada].
///
/// **La primera versión decía que ningún archivo nuevo contaba**, porque todos
/// serían generados por la derivación. Es falso y está reproducido: un archivo
/// de fuente creado entre la derivación y el segundo control dejaba la corrida en
/// rojo, concluyendo sobre bytes que el candidato no fijó. Quién decide qué es
/// artefacto no se sabe acá: es `ArtifactPolicy`.
class AlteracionDelCandidato {
  final String ruta;
  final TipoDeAlteracion tipo;

  AlteracionDelCandidato({required this.ruta, required this.tipo}) {
    if (ruta.trim().isEmpty) {
      throw ArgumentError.value(
        ruta,
        'ruta',
        'Una alteración sin ruta no nombra nada.',
      );
    }
  }

  Map<String, Object?> toJson() => {'ruta': ruta, 'tipo': tipo.name};

  factory AlteracionDelCandidato.fromJson(Map<String, Object?> json) =>
      AlteracionDelCandidato(
        ruta: json['ruta']! as String,
        tipo: TipoDeAlteracion.values.byName(json['tipo']! as String),
      );
}
