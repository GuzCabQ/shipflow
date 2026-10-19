import 'recognition_enums.dart';

/// El único estado de contenido de una fuente candidata: nunca se abre.
const contextNotInspected = 'not_inspected';

/// Una ruta del catálogo de fuentes candidatas, mirada sólo por sus
/// metadatos. No tiene huella ni contenido, y su ruta nunca autoriza leerla.
final class ContextSource {
  ContextSource({
    required this.scopePath,
    required this.path,
    required this.kind,
    required this.entityType,
    required this.reason,
  }) {
    if (!_consistent(entityType, reason)) {
      throw ArgumentError.value(
        reason,
        'reason',
        'no corresponde al tipo ${entityType.toWireName()}',
      );
    }
  }

  factory ContextSource.fromJson(Map<String, Object?> json) {
    if (json['contentStatus'] != contextNotInspected) {
      throw FormatException(
        'una fuente candidata sólo puede estar sin inspeccionar',
        json['contentStatus'],
      );
    }
    return ContextSource(
      scopePath: json['scopePath']! as String,
      path: json['path']! as String,
      kind: ContextSourceKind.fromWireName(json['kind']! as String),
      entityType: ContextEntityType.fromWireName(json['entityType']! as String),
      reason: ContextReason.fromWireName(json['reason']! as String),
    );
  }

  /// La raíz de unidad donde se buscó, relativa a la raíz resuelta.
  final String scopePath;

  /// Relativa a la raíz resuelta.
  final String path;
  final ContextSourceKind kind;
  final ContextEntityType entityType;
  final ContextReason reason;

  final String contentStatus = contextNotInspected;

  Map<String, Object?> toJson() => {
    'scopePath': scopePath,
    'path': path,
    'kind': kind.toWireName(),
    'entityType': entityType.toWireName(),
    'reason': reason.toWireName(),
    'contentStatus': contentStatus,
  };
}

/// Observada si se vio su tipo; ausente si no existe; no disponible por
/// cualquier otro motivo.
bool _consistent(ContextEntityType type, ContextReason reason) =>
    switch (reason) {
      ContextReason.observed => type.observed,
      ContextReason.notFound => type == ContextEntityType.missing,
      _ => type == ContextEntityType.unavailable,
    };
