import 'package:core/core.dart';

import '../context/context_codec.dart';
import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import 'assessment_codec.dart';
import 'assessment_freshness.dart';
import 'assessment_preflight.dart';
import 'assessment_service.dart';
import 'assessment_store.dart';

/// El contexto citado sigue con sus bytes y no hay una operación de init
/// sin terminar.
Future<void> unchangedContext(ContextStore store, CitedContext cited) async {
  final bytes = await store.readRelative(
    projectPath,
    maxBytes: maxProjectBytes,
  );
  if (bytes == null || sha256Of(bytes) != cited.digest) {
    throw const AssessmentAbort('concurrent_change');
  }
  if (await store.readRelative(transactionPath, maxBytes: 1) != null) {
    throw const AssessmentAbort('context_recovery_pending');
  }
}

/// El contexto citado y las fuentes de [snapshot] se confirman ahora: un
/// cambio demostrado es `source_changed`; una entrada sellada que ya no se
/// pudo cotejar es `concurrent_change`, porque sin cambio demostrado no
/// equivale a confirmado.
Future<void> unchangedSources(
  AssessmentService s,
  AssessmentRequest r,
  CitedContext cited,
  AssessmentSnapshot snapshot,
) async {
  await unchangedContext(s.store, cited);
  final now = await s.observeInputs(s.root, cited.context, s.limits(r.profile));
  final before = [
    for (final i in snapshot.inputs)
      if (i.kind != AssessmentInputKind.context) i,
  ];
  if (changedInputs(before, now).isNotEmpty) {
    throw const AssessmentAbort('source_changed');
  }
  if (uncheckedInputs(before, now).isNotEmpty) {
    throw const AssessmentAbort('concurrent_change');
  }
}
