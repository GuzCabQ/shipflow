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

  const AcceptanceCriterion({
    required this.id,
    required this.statement,
    this.assertionForm,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'statement': statement.toJson(),
        'assertionForm': assertionForm,
      };

  factory AcceptanceCriterion.fromJson(Map<String, Object?> json) =>
      AcceptanceCriterion(
        id: json['id']! as String,
        statement: QuotedText.fromJson(
            Map<String, Object?>.from(json['statement']! as Map)),
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

  const WorkItem({
    required this.id,
    required this.title,
    required this.description,
    required this.criteria,
    this.sourceMetadata = const {},
  });

  /// INV-1: no entra si algún criterio no se mapeó a una forma del catálogo.
  ///
  /// `core` verifica que la forma **esté**; que exista en el catálogo lo
  /// verifica quien tenga el catálogo. La división es deliberada: `core` no
  /// conoce ningún stack.
  bool get allCriteriaMapped =>
      criteria.isNotEmpty && criteria.every((c) => c.assertionForm != null);

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
            Map<String, Object?>.from(json['title']! as Map)),
        description: QuotedText.fromJson(
            Map<String, Object?>.from(json['description']! as Map)),
        criteria: [
          for (final c in json['criteria']! as List<Object?>)
            AcceptanceCriterion.fromJson(Map<String, Object?>.from(c! as Map)),
        ],
        sourceMetadata:
            Map<String, Object?>.from(json['sourceMetadata']! as Map),
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

  const Diagnostic({
    required this.file,
    required this.severity,
    required this.ruleId,
    required this.message,
    this.line,
    this.sourceMetadata = const {},
  });

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
            Map<String, Object?>.from(json['message']! as Map)),
        sourceMetadata:
            Map<String, Object?>.from(json['sourceMetadata']! as Map),
      );
}

/// Unidad de topología del proyecto que se está trabajando.
///
/// La reporta el puerto de topología, que implementa el plugin del stack.
class Package {
  final String name;
  final String path;
  final List<String> dependsOn;

  const Package({
    required this.name,
    required this.path,
    required this.dependsOn,
  });

  Map<String, Object?> toJson() =>
      {'name': name, 'path': path, 'dependsOn': dependsOn};

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

  const PullRequestSlice({
    required this.id,
    required this.intent,
    required this.files,
  });

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

  const Plan({
    required this.workItemId,
    required this.files,
    required this.tests,
    required this.slices,
  });

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
