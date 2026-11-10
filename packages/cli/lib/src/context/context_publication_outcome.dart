import 'package:core/core.dart';

/// Lo que una publicación dejó de hecho, sin referencias a la sesión ni al
/// servicio: la sesión lo proyecta sobre su resultado. Las listas se copian
/// inmodificables para que quien lo recibe no pueda cambiarlo.
sealed class PublicationOutcome {
  const PublicationOutcome();
}

/// No había nada que publicar: la modalidad comprobada y sus diagnósticos.
/// La comprobación Git ya se hizo antes de cerrar la administración.
final class NothingToPublish extends PublicationOutcome {
  NothingToPublish({
    required this.sharing,
    required List<ContextDiagnostic> diagnostics,
  }) : diagnostics = List.unmodifiable(diagnostics);

  final ContextSharing sharing;
  final List<ContextDiagnostic> diagnostics;
}

/// La publicación no se completó: un rechazo previo o una transacción no
/// exitosa. [journalLeft] indica que quedó un journal para `init --recover`.
final class PublicationRefused extends PublicationOutcome {
  PublicationRefused({
    required List<ContextDiagnostic> diagnostics,
    this.journalLeft = false,
  }) : diagnostics = List.unmodifiable(diagnostics);

  final List<ContextDiagnostic> diagnostics;
  final bool journalLeft;
}

/// La publicación se completó: la modalidad aplicada y el reconocimiento que
/// queda, si cambió. El éxito concreto lo fija la sesión.
final class PublicationCompleted extends PublicationOutcome {
  const PublicationCompleted({
    required this.choice,
    required this.effective,
    required this.recognition,
  });

  final SharingChoice choice;
  final SharingEffective effective;
  final PortableRecognition? recognition;
}
