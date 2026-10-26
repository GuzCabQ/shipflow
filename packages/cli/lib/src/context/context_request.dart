import 'package:core/core.dart';

import '../cli_command.dart';

/// El reconocimiento actual de la raíz, ensamblado dentro de [profile] y con
/// las omisiones que la raíz de composición ya autorizó.
typedef ContextRecognizer =
    Future<RecognitionReport> Function(
      ReportBudgetProfile profile,
      List<AuthorizedOmission> omissions,
    );

/// Lo que se pide a una operación de contexto. La versión, la raíz y la
/// entrada y salida se inyectan al servicio, no viajan aquí.
final class ContextRequest {
  const ContextRequest({
    required this.operation,
    this.sharing,
    this.profile = ReportBudgetProfile.standard,
    this.choose,
  });

  final ContextOperation operation;

  /// La elección explícita de `--sharing`, o null.
  final SharingChoice? sharing;
  final ReportBudgetProfile profile;

  /// Pregunta la elección en una terminal, antes de cualquier efecto; null
  /// es cancelar. Sin [choose] (JSON o sin terminal) no se pregunta.
  final Future<SharingChoice?> Function()? choose;
}
