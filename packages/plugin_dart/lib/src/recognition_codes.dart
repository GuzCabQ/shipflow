import 'package:core/core.dart';

/// Los códigos de las limitaciones que el reconocimiento puede informar.
abstract final class LimitationCode {
  static const symlinkNotFollowed = 'symlink_not_followed';
  static const subtreeUnreadable = 'subtree_unreadable';
  static const scanLimitReached = 'scan_limit_reached';
  static const sourceTooLarge = 'source_too_large';
  static const sourceUnreadable = 'source_unreadable';
  static const sourceChanged = 'source_changed_during_scan';
  static const invalidManifest = 'invalid_manifest';
  static const invalidToolchainMarker = 'invalid_toolchain_marker';
  static const invalidConstraint = 'invalid_constraint';
  static const pathDependencyOutsideRoot = 'path_dependency_outside_root';
  static const pathDependencyUnresolved = 'path_dependency_unresolved';
  static const observedValueTruncated = 'observed_value_truncated';
  static const optionalDescriptionUnavailable =
      'optional_description_unavailable';
  static const unsupportedResourceDeclaration =
      'unsupported_resource_declaration';
}

/// Los códigos de los conflictos que el reconocimiento no resuelve.
abstract final class ConflictCode {
  static const toolchainVersionsDisagree = 'toolchain_versions_disagree';
  static const toolchainOutsideConstraint = 'toolchain_outside_constraint';
  static const flutterConstraintsDisjoint = 'flutter_constraints_disjoint';
  static const sdkConstraintsDisjoint = 'sdk_constraints_disjoint';
  static const duplicatePackageName = 'duplicate_package_name';
}

/// Los tipos de evidencia que el reconocimiento produce.
abstract final class EvidenceKind {
  static const packageName = 'manifest.package_name';
  static const sdkConstraint = 'manifest.sdk_constraint';
  static const flutterConstraint = 'manifest.flutter_constraint';
  static const flutterDependency = 'manifest.flutter_dependency';
  static const pathDependency = 'manifest.path_dependency';
  static const workspaceMember = 'manifest.workspace_member';
  static const description = 'manifest.description';
  static const resourceDirectory = 'manifest.resource_directory';
  static const fvm = 'toolchain.fvm';
  static const flutterVersionFile = 'toolchain.flutter_version_file';
}

/// Qué sostiene cada tipo de evidencia y cómo nombrarlo ante una persona.
/// La CLI agrupa por rol y muestra la etiqueta, sin interpretar el tipo.
const _presentation = {
  EvidenceKind.packageName: (EvidenceRole.identity, 'Nombre del paquete'),
  EvidenceKind.flutterDependency: (
    EvidenceRole.identity,
    'Dependencia del SDK de Flutter',
  ),
  EvidenceKind.sdkConstraint: (
    EvidenceRole.environment,
    'Restricción declarada del SDK de Dart',
  ),
  EvidenceKind.flutterConstraint: (
    EvidenceRole.environment,
    'Restricción declarada de Flutter',
  ),
  EvidenceKind.fvm: (EvidenceRole.environment, 'Versión de Flutter en .fvmrc'),
  EvidenceKind.flutterVersionFile: (
    EvidenceRole.environment,
    'Versión de Flutter en flutter-version.txt',
  ),
  EvidenceKind.pathDependency: (EvidenceRole.relation, 'Dependencia local'),
  EvidenceKind.workspaceMember: (
    EvidenceRole.relation,
    'Miembro del workspace',
  ),
  EvidenceKind.description: (EvidenceRole.description, 'Descripción declarada'),
  EvidenceKind.resourceDirectory: (
    EvidenceRole.resource,
    'Directorio de recursos declarado',
  ),
};

/// El rol de [kind]; un tipo sin rol es un defecto de este plugin.
EvidenceRole evidenceRoleOf(String kind) => _presentationOf(kind).$1;

/// La etiqueta de [kind] para la vista humana.
String evidenceLabelOf(String kind) => _presentationOf(kind).$2;

(EvidenceRole, String) _presentationOf(String kind) =>
    _presentation[kind] ??
    (throw ArgumentError.value(kind, 'kind', 'tipo de evidencia sin rol'));
