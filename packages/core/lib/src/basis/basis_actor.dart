import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'basis_scope.dart';

/// Quién declara una aceptación en esta copia. La autoridad es local y
/// declarada: no se autentica que [label] represente a una persona.
final class BasisActor {
  BasisActor({required this.label, required this.role, required this.scope});

  factory BasisActor.fromJson(Map<String, Object?> json) {
    requireSemantic(json['authority'] == 'local_declared', 'invalid_schema');
    return BasisActor(
      label: json['label']! as String,
      role: json['role']! as String,
      scope: readObject(json['scope'], BasisScope.fromJson),
    );
  }

  final String label;
  final String role;
  final String authority = 'local_declared';
  final BasisScope scope;

  Map<String, Object?> toJson() => {
    'label': label,
    'role': role,
    'authority': authority,
    'scope': scope.toJson(),
  };
}
