import '../context/context_enums.dart' show wireValue;
import '../recognition/recognition_json.dart';
import 'basis_enums.dart';
import 'basis_model.dart';
import 'basis_payload.dart';

/// El efecto que tendrá aceptar una versión del borrador sobre su registro.
enum BasisChangeKind {
  create('create'),
  revise('revise'),
  retire('retire'),
  replace('replace'),
  resolve('resolve');

  const BasisChangeKind(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisChangeKind fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// El efecto de [v]: sale de su cadena de versiones y de su estado, nunca
/// de lo que declare quien la propone. Una versión 1 siempre crea.
BasisChangeKind changeKindOf(BasisRecordVersion v) => switch (v.payload) {
  _ when v.previousVersion == null => BasisChangeKind.create,
  BasisRule(lifecycle: BasisRuleLifecycle.retired) ||
  BasisSource(
    lifecycle: BasisSourceLifecycle.retired,
  ) => BasisChangeKind.retire,
  BasisRule(lifecycle: BasisRuleLifecycle.replaced) => BasisChangeKind.replace,
  BasisPending(status: BasisPendingStatus.resolved) => BasisChangeKind.resolve,
  _ => BasisChangeKind.revise,
};

/// Un cambio exacto del borrador que se ofrece aceptar: la versión con su
/// ID y su número, y el efecto que tendrá. Sólo viaja en la respuesta de
/// un borrador sin aceptar.
final class BasisProposedChange {
  BasisProposedChange({required this.change, required this.version});

  factory BasisProposedChange.of(BasisRecordVersion version) =>
      BasisProposedChange(change: changeKindOf(version), version: version);

  factory BasisProposedChange.fromJson(Map<String, Object?> json) =>
      BasisProposedChange(
        change: BasisChangeKind.fromWireName(json['change']! as String),
        version: readObject(json['version'], BasisRecordVersion.fromJson),
      );

  final BasisChangeKind change;
  final BasisRecordVersion version;

  Map<String, Object?> toJson() => {
    'change': change.toWireName(),
    'version': version.toJson(),
  };
}
