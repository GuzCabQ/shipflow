import '../recognition/recognition_json.dart';
import 'context_enums.dart';
import 'context_validation.dart';

/// La elección de conservación, lo observado de Git y si está aplicada.
final class ContextSharing {
  const ContextSharing({
    required this.choice,
    required this.gitState,
    required this.effective,
  });

  factory ContextSharing.fromJson(Map<String, Object?> json) => ContextSharing(
    choice: SharingChoice.fromWireName(json['choice']! as String),
    gitState: GitState.fromWireName(json['gitState']! as String),
    effective: SharingEffective.fromWireName(json['effective']! as String),
  );

  final SharingChoice choice;
  final GitState gitState;
  final SharingEffective effective;

  Map<String, Object?> toJson() => {
    'choice': choice.toWireName(),
    'gitState': gitState.toWireName(),
    'effective': effective.toWireName(),
  };
}

/// Una comprobación del catálogo cerrado, con su alcance y motivo.
final class ContextCheck {
  const ContextCheck({
    required this.id,
    required this.status,
    required this.code,
    required this.scope,
    required this.message,
  });

  factory ContextCheck.fromJson(Map<String, Object?> json) => ContextCheck(
    id: ContextCheckId.fromWireName(json['id']! as String),
    status: ContextCheckStatus.fromWireName(json['status']! as String),
    code: json['code']! as String,
    scope: json['scope']! as String,
    message: json['message']! as String,
  );

  final ContextCheckId id;
  final ContextCheckStatus status;
  final String code;
  final String scope;
  final String message;

  Map<String, Object?> toJson() => {
    'id': id.toWireName(),
    'status': status.toWireName(),
    'code': code,
    'scope': scope,
    'message': message,
  };
}

/// Un hallazgo accionable; su ruta se sanea al mostrarla.
final class ContextDiagnostic {
  const ContextDiagnostic({
    required this.code,
    required this.message,
    required this.path,
  });

  factory ContextDiagnostic.fromJson(Map<String, Object?> json) =>
      ContextDiagnostic(
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

/// Lo que la operación hizo de verdad, incluso si falló después. La red
/// es siempre cero.
final class ContextEffects {
  ContextEffects({
    List<String> filesCreated = const [],
    List<String> filesReplaced = const [],
    List<String> filesRemoved = const [],
    List<String> directoriesCreated = const [],
    this.processesStarted = 0,
    this.excludeModified = false,
  }) : filesCreated = List.unmodifiable(filesCreated),
       filesReplaced = List.unmodifiable(filesReplaced),
       filesRemoved = List.unmodifiable(filesRemoved),
       directoriesCreated = List.unmodifiable(directoriesCreated);

  factory ContextEffects.fromJson(Map<String, Object?> json) {
    requireSemantic(json['networkRequests'] == 0, 'network');
    return ContextEffects(
      filesCreated: readStrings(json['filesCreated']),
      filesReplaced: readStrings(json['filesReplaced']),
      filesRemoved: readStrings(json['filesRemoved']),
      directoriesCreated: readStrings(json['directoriesCreated']),
      processesStarted: json['processesStarted']! as int,
      excludeModified: json['excludeModified']! as bool,
    );
  }

  final List<String> filesCreated;
  final List<String> filesReplaced;
  final List<String> filesRemoved;
  final List<String> directoriesCreated;
  final int processesStarted;
  final bool excludeModified;
  final int networkRequests = 0;

  /// Si escribió, eliminó o creó algo.
  bool get wrote =>
      excludeModified ||
      [
        filesCreated,
        filesReplaced,
        filesRemoved,
        directoriesCreated,
      ].any((paths) => paths.isNotEmpty);

  Map<String, Object?> toJson() => {
    'filesCreated': filesCreated,
    'filesReplaced': filesReplaced,
    'filesRemoved': filesRemoved,
    'directoriesCreated': directoriesCreated,
    'processesStarted': processesStarted,
    'excludeModified': excludeModified,
    'networkRequests': networkRequests,
  };
}

/// Un comando existente que la persona puede ejecutar a continuación.
final class ContextNextAction {
  ContextNextAction({
    required this.command,
    required List<String> arguments,
    required this.purpose,
    required this.effect,
  }) : arguments = List.unmodifiable(arguments);

  factory ContextNextAction.fromJson(Map<String, Object?> json) =>
      ContextNextAction(
        command: ContextCommand.fromWireName(json['command']! as String),
        arguments: readStrings(json['arguments']),
        purpose: json['purpose']! as String,
        effect: json['effect']! as String,
      );

  final ContextCommand command;
  final List<String> arguments;
  final String purpose;
  final String effect;

  Map<String, Object?> toJson() => {
    'command': command.toWireName(),
    'arguments': arguments,
    'purpose': purpose,
    'effect': effect,
  };
}
