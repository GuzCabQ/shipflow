import 'recognition_enums.dart';
import 'recognition_omissions.dart';

/// Un árbol que la raíz de composición autoriza a omitir antes de reconocer,
/// tras comprobar por su cuenta que le pertenece. Es un dato puro: el plugin
/// no sabe de configuración, transacciones ni Git, y la omisión existe
/// aunque el árbol todavía no esté.
final class AuthorizedOmission {
  AuthorizedOmission({required this.relativePath, required this.rule}) {
    if (rule != OmissionRule.toolState || relativePath != toolStatePath) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'sólo se autoriza omitir el estado propio en «$toolStatePath»',
      );
    }
  }

  factory AuthorizedOmission.fromJson(Map<String, Object?> json) =>
      AuthorizedOmission(
        relativePath: json['relativePath']! as String,
        rule: OmissionRule.fromWireName(json['rule']! as String),
      );

  /// Relativa a la raíz.
  final String relativePath;
  final OmissionRule rule;

  Map<String, Object?> toJson() => {
    'relativePath': relativePath,
    'rule': rule.toWireName(),
  };
}
