import 'recognition_json.dart';

/// Algo que un futuro `init` haría; el reconocimiento no lo aplica.
final class ProposedAction {
  const ProposedAction({required this.code, required this.description});

  factory ProposedAction.fromJson(Map<String, Object?> json) => ProposedAction(
    code: json['code']! as String,
    description: json['description']! as String,
  );

  final String code;
  final String description;

  Map<String, Object?> toJson() => {'code': code, 'description': description};
}

final class RecognitionProposal {
  RecognitionProposal({
    required this.eligible,
    required List<String> pluginIds,
    required List<ProposedAction> actions,
  }) : pluginIds = List.unmodifiable(pluginIds),
       actions = List.unmodifiable(actions);

  factory RecognitionProposal.fromJson(Map<String, Object?> json) =>
      RecognitionProposal(
        eligible: json['eligible']! as bool,
        pluginIds: readStrings(json['pluginIds']),
        actions: readObjects(json['actions'], ProposedAction.fromJson),
      );

  final bool eligible;
  final List<String> pluginIds;
  final List<ProposedAction> actions;

  Map<String, Object?> toJson() => {
    'eligible': eligible,
    'pluginIds': pluginIds,
    'actions': [for (final action in actions) action.toJson()],
  };
}

/// Lo que el reconocimiento le hizo al mundo.
final class RecognitionEffects {
  const RecognitionEffects({
    required this.filesWritten,
    required this.directoriesCreated,
    required this.processesStarted,
    required this.networkRequests,
  });

  factory RecognitionEffects.fromJson(Map<String, Object?> json) =>
      RecognitionEffects(
        filesWritten: json['filesWritten']! as int,
        directoriesCreated: json['directoriesCreated']! as int,
        processesStarted: json['processesStarted']! as int,
        networkRequests: json['networkRequests']! as int,
      );

  /// Un reconocimiento no escribe, no lanza procesos ni usa la red.
  static const none = RecognitionEffects(
    filesWritten: 0,
    directoriesCreated: 0,
    processesStarted: 0,
    networkRequests: 0,
  );

  final int filesWritten;
  final int directoriesCreated;
  final int processesStarted;
  final int networkRequests;

  Map<String, Object?> toJson() => {
    'filesWritten': filesWritten,
    'directoriesCreated': directoriesCreated,
    'processesStarted': processesStarted,
    'networkRequests': networkRequests,
  };
}
