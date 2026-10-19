import 'recognition_enums.dart';
import 'recognition_json.dart';

/// Una relación que una unidad declara hacia otra ruta de la raíz. Sólo
/// corroborada si se observó el manifiesto de su destino: eso prueba que la
/// declaración corresponde a una unidad, no que se use ni que compile.
final class RecognitionRelation {
  RecognitionRelation({
    required this.id,
    required this.kind,
    required this.fromPath,
    required this.declaredName,
    required this.targetPath,
    required this.targetUnitId,
    required this.status,
    required List<String> evidenceIds,
  }) : evidenceIds = List.unmodifiable(evidenceIds) {
    if (status == RelationStatus.corroborated &&
        (targetPath == null || targetUnitId == null)) {
      throw ArgumentError.value(
        id,
        'status',
        'una relación corroborada necesita su ruta y unidad de destino',
      );
    }
  }

  factory RecognitionRelation.fromJson(Map<String, Object?> json) =>
      RecognitionRelation(
        id: json['id']! as String,
        kind: RelationKind.fromWireName(json['kind']! as String),
        fromPath: json['fromPath']! as String,
        declaredName: json['declaredName'] as String?,
        targetPath: json['targetPath'] as String?,
        targetUnitId: json['targetUnitId'] as String?,
        status: RelationStatus.fromWireName(json['status']! as String),
        evidenceIds: readStrings(json['evidenceIds']),
      );

  final String id;
  final RelationKind kind;

  /// La raíz del paquete que declara, relativa a la raíz resuelta.
  final String fromPath;

  /// El nombre con que se declara, si la forma de la relación lo tiene.
  final String? declaredName;

  /// Interna y comprobada tramo a tramo, o null si no se pudo establecer.
  final String? targetPath;
  final String? targetUnitId;
  final RelationStatus status;
  final List<String> evidenceIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.toWireName(),
    'fromPath': fromPath,
    'declaredName': declaredName,
    'targetPath': targetPath,
    'targetUnitId': targetUnitId,
    'status': status.toWireName(),
    'evidenceIds': evidenceIds,
  };
}
