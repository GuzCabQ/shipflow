import '../context/context_validation.dart';
import 'assessment_enums.dart';

/// Una ruta relativa del levantamiento: tramos no vacíos separados por `/`,
/// sin absolutos, `.`, `..` ni NUL. `.` sólo vale donde se admite la raíz.
bool isAssessmentPath(String path, {bool allowRoot = false}) {
  if (path == '.') return allowRoot;
  if (path.isEmpty || path.startsWith('/') || path.contains('\u0000')) {
    return false;
  }
  return isWellFormedText(path) &&
      path.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
}

/// Una unidad del contexto citado, identificada por su ubicación: no es un
/// límite de negocio ni una arquitectura aprobada.
final class AssessmentUnit {
  AssessmentUnit({required this.id, required this.path, required this.label}) {
    requireSemantic(isAssessmentPath(path, allowRoot: true), 'path', '/units');
  }

  factory AssessmentUnit.fromJson(Map<String, Object?> json) => AssessmentUnit(
    id: json['id']! as String,
    path: json['path']! as String,
    label: json['label']! as String,
  );

  final String id;
  final String path;
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'path': path, 'label': label};
}

/// Una entrada del inventario sellado. Leída o listada lleva la huella de
/// sus bytes o de su listado; excluida, ilegible o fuera de presupuesto,
/// el motivo y ninguna huella.
final class AssessmentInput {
  AssessmentInput({
    required this.path,
    required this.kind,
    required this.state,
    required this.sha256,
    required this.reason,
  }) {
    requireSemantic(isAssessmentPath(path, allowRoot: true), 'path', '/inputs');
    final sealed =
        state == AssessmentInputState.read ||
        state == AssessmentInputState.listed;
    requireSemantic(
      sealed
          ? sha256 != null && isSha256Hex(sha256!) && reason == null
          : sha256 == null && reason != null,
      'input_state',
      '/inputs',
    );
    requireSemantic(_fits(kind, state), 'input_state', '/inputs');
  }

  factory AssessmentInput.fromJson(Map<String, Object?> json) =>
      AssessmentInput(
        path: json['path']! as String,
        kind: AssessmentInputKind.fromWireName(json['kind']! as String),
        state: AssessmentInputState.fromWireName(json['state']! as String),
        sha256: json['sha256'] as String?,
        reason: json['reason'] as String?,
      );

  final String path;
  final AssessmentInputKind kind;
  final AssessmentInputState state;
  final String? sha256;
  final String? reason;

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind.toWireName(),
    'state': state.toWireName(),
    'sha256': sha256,
    'reason': reason,
  };
}

/// Un directorio se lista; un árbol excluido sólo se excluye; un archivo se
/// lee, o queda ilegible o fuera de presupuesto.
bool _fits(AssessmentInputKind kind, AssessmentInputState state) =>
    switch (kind) {
      AssessmentInputKind.excluded => state == AssessmentInputState.excluded,
      AssessmentInputKind.directory =>
        state != AssessmentInputState.read &&
            state != AssessmentInputState.excluded,
      _ =>
        state != AssessmentInputState.listed &&
            state != AssessmentInputState.excluded,
    };

/// Un archivo fuente elegible y quién es su dueño. Nunca se declara
/// editable en este corte.
final class AssessmentFile {
  AssessmentFile({
    required this.id,
    required this.path,
    required this.unitId,
    required this.inputPath,
    required this.role,
    required this.parseState,
    required this.witnessId,
  }) {
    requireSemantic(isAssessmentPath(path), 'path', '/files');
  }

  factory AssessmentFile.fromJson(Map<String, Object?> json) {
    requireSemantic(json['editable'] == editableUnknown, 'editable', '/files');
    return AssessmentFile(
      id: json['id']! as String,
      path: json['path']! as String,
      unitId: json['unitId']! as String,
      inputPath: json['inputPath']! as String,
      role: AssessmentFileRole.fromWireName(json['role']! as String),
      parseState: AssessmentParseState.fromWireName(
        json['parseState']! as String,
      ),
      witnessId: json['witnessId']! as String,
    );
  }

  final String id;
  final String path;
  final String unitId;
  final String inputPath;
  final AssessmentFileRole role;
  final AssessmentParseState parseState;
  final String witnessId;

  /// No se descubre la herramienta ni la propiedad de generación.
  final String editable = editableUnknown;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'unitId': unitId,
    'inputPath': inputPath,
    'role': role.toWireName(),
    'parseState': parseState.toWireName(),
    'witnessId': witnessId,
    'editable': editable,
  };
}

const editableUnknown = 'unknown';

/// Quién observó: la distribución, el contrato del detector, el plugin y la
/// versión del parser. Un cambio de semántica exige otro contrato.
final class AssessmentProducer {
  const AssessmentProducer({
    required this.version,
    required this.contract,
    required this.pluginId,
    required this.parserVersion,
  });

  factory AssessmentProducer.fromJson(Map<String, Object?> json) =>
      AssessmentProducer(
        version: json['version']! as String,
        contract: json['contract']! as String,
        pluginId: json['pluginId']! as String,
        parserVersion: json['parserVersion']! as String,
      );

  final String version;
  final String contract;
  final String pluginId;
  final String parserVersion;

  Map<String, Object?> toJson() => {
    'version': version,
    'contract': contract,
    'pluginId': pluginId,
    'parserVersion': parserVersion,
  };
}
