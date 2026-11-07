import 'package:core/core.dart';

/// Qué hay en `shipflow/` respecto del contrato V2.
enum StateOwnershipKind {
  /// No existe: puede inicializarse.
  absent,

  /// Un directorio vacío: puede inicializarse.
  empty,

  /// Sólo el andamiaje que crea init: puede reintentarse.
  bootstrap,

  /// Un contexto o una transacción propia que cumple el formato.
  owned,

  /// Con la forma de Shipflow, pero un documento no valida o hay restos que
  /// no se pueden acreditar: se conserva y se diagnostica.
  invalid,

  /// Contenido de otra herramienta o entidades que el contrato no admite.
  foreign,
}

/// La clasificación y las rutas, relativas a la raíz, que la justifican.
final class StateOwnership {
  StateOwnership(
    this.kind, [
    List<String> findings = const [],
    this.assessmentJournal = false,
    this.basis = BasisIntegrity.absent,
    this.basisTransaction = BasisIntegrity.absent,
  ]) : findings = List.unmodifiable(findings);

  final StateOwnershipKind kind;
  final List<String> findings;

  /// Si hay un journal de assess válido: sólo `assess --recover` lo
  /// termina; init no lo recupera ni adivina un orden con el suyo.
  final bool assessmentJournal;

  /// Lo demostrado de la base guiada y de su journal: doctor lo informa;
  /// una base dañada no invalida un contexto válido.
  final BasisIntegrity basis;
  final BasisIntegrity basisTransaction;

  /// Si hay un journal de bootstrap válido: sólo `bootstrap --recover` lo
  /// termina.
  bool get basisJournal => basisTransaction == BasisIntegrity.valid;

  /// Sólo un estado propio comprobado, o su ausencia, se omite del
  /// reconocimiento: el nombre por sí solo no prueba propiedad.
  bool get authorizesOmission => const {
    StateOwnershipKind.absent,
    StateOwnershipKind.empty,
    StateOwnershipKind.bootstrap,
    StateOwnershipKind.owned,
  }.contains(kind);
}
