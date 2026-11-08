import '../context/context_enums.dart' show wireValue;
import '../recognition/recognition_json.dart';
import 'basis_scope.dart';

/// Qué operación de bootstrap respondió.
enum BasisOperation {
  guide('guide'),
  prepare('prepare'),
  show('show'),
  accept('accept'),
  discard('discard'),
  recover('recover');

  const BasisOperation(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisOperation fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Cómo terminó una operación. `published` es un efecto sobre la base, no
/// el guardado de un borrador.
enum BasisOutcome {
  published('published'),
  shown('shown'),
  discarded('discarded'),
  alreadyApplied('already_applied'),
  recovered('recovered'),
  noChanges('no_changes'),
  abortedBeforePublication('aborted_before_publication'),
  draftPrepared('draft_prepared'),
  choiceRequired('choice_required'),
  blocked('blocked'),
  failed('failed'),
  cancelled('cancelled');

  const BasisOutcome(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisOutcome fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Qué se demostró de un archivo propio: ausencia comprobada, validez
/// comprobada, versión no soportada, invalidez demostrada o nada.
enum BasisIntegrity {
  absent('absent'),
  valid('valid'),
  invalid('invalid'),
  incompatible('incompatible'),
  unverified('unverified');

  const BasisIntegrity(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisIntegrity fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Cuánto de las normas del proyecto declara la base: nunca «completa».
enum BasisCoverage {
  notEstablished('not_established'),
  declaredPartial('declared_partial');

  const BasisCoverage(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisCoverage fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// La correspondencia de una versión de fuente con su contenido actual.
enum BasisSourceState {
  current('current'),
  stale('stale'),
  unverified('unverified'),
  excluded('excluded');

  const BasisSourceState(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisSourceState fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Qué haría una acción propuesta si alguien la ejecutara.
enum BasisActionEffect {
  readOnly('read_only'),
  writeOwnState('write_own_state'),
  userDecision('user_decision');

  const BasisActionEffect(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisActionEffect fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// La integridad de cada archivo propio, informada por separado.
final class BasisStorageIntegrity {
  BasisStorageIntegrity({
    required this.basis,
    required this.draft,
    required this.transaction,
  });

  factory BasisStorageIntegrity.fromJson(Map<String, Object?> json) =>
      BasisStorageIntegrity(
        basis: BasisIntegrity.fromWireName(json['basis']! as String),
        draft: BasisIntegrity.fromWireName(json['draft']! as String),
        transaction: BasisIntegrity.fromWireName(
          json['transaction']! as String,
        ),
      );

  final BasisIntegrity basis;
  final BasisIntegrity draft;
  final BasisIntegrity transaction;

  Map<String, Object?> toJson() => {
    'basis': basis.toWireName(),
    'draft': draft.toWireName(),
    'transaction': transaction.toWireName(),
  };
}

/// El ámbito pedido, si se entregó el conjunto exigido y cuántos registros
/// quedaron fuera sólo por ámbito.
final class BasisSelectionSummary {
  BasisSelectionSummary({
    required this.scope,
    required this.complete,
    required this.excludedCount,
  });

  factory BasisSelectionSummary.fromJson(Map<String, Object?> json) =>
      BasisSelectionSummary(
        scope: json['scope'] == null
            ? null
            : readObject(json['scope'], BasisScope.fromJson),
        complete: json['complete']! as bool,
        excludedCount: json['excludedCount']! as int,
      );

  /// Null: sin filtro, la consulta global.
  final BasisScope? scope;
  final bool complete;
  final int excludedCount;

  Map<String, Object?> toJson() => {
    'scope': scope?.toJson(),
    'complete': complete,
    'excludedCount': excludedCount,
  };
}

/// Un diagnóstico con código estable y, si aplica, la ruta afectada.
final class BasisDiagnostic {
  BasisDiagnostic({
    required this.code,
    required this.message,
    required this.path,
  });

  factory BasisDiagnostic.fromJson(Map<String, Object?> json) =>
      BasisDiagnostic(
        code: json['code']! as String,
        message: json['message']! as String,
        path: json['path'] as String?,
      );

  final String code;
  final String message;
  final String? path;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'path': path,
  };
}

/// El estado de una versión de fuente citada, sin su contenido.
final class BasisSourceStatus {
  BasisSourceStatus({
    required this.sourceId,
    required this.sourceVersion,
    required this.status,
    required List<BasisDiagnostic> diagnostics,
  }) : diagnostics = List.unmodifiable(diagnostics);

  factory BasisSourceStatus.fromJson(Map<String, Object?> json) =>
      BasisSourceStatus(
        sourceId: json['sourceId']! as String,
        sourceVersion: json['sourceVersion']! as int,
        status: BasisSourceState.fromWireName(json['status']! as String),
        diagnostics: readObjects(json['diagnostics'], BasisDiagnostic.fromJson),
      );

  final String sourceId;
  final int sourceVersion;
  final BasisSourceState status;
  final List<BasisDiagnostic> diagnostics;

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'sourceVersion': sourceVersion,
    'status': status.toWireName(),
    'diagnostics': [for (final d in diagnostics) d.toJson()],
  };
}

/// Una acción siguiente: [command] sin el ejecutable y [arguments] como
/// lista literal, sin shell. Mostrarla nunca la ejecuta.
final class BasisAction {
  BasisAction({
    required this.command,
    required List<String> arguments,
    required this.purpose,
    required this.effect,
  }) : arguments = List.unmodifiable(arguments);

  factory BasisAction.fromJson(Map<String, Object?> json) => BasisAction(
    command: json['command']! as String,
    arguments: readStrings(json['arguments']),
    purpose: json['purpose']! as String,
    effect: BasisActionEffect.fromWireName(json['effect']! as String),
  );

  final String command;
  final List<String> arguments;
  final String purpose;
  final BasisActionEffect effect;

  Map<String, Object?> toJson() => {
    'command': command,
    'arguments': arguments,
    'purpose': purpose,
    'effect': effect.toWireName(),
  };
}
