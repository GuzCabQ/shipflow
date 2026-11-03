import 'package:core/core.dart';

import '../context/context_codec.dart';
import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import 'assessment_codec.dart';
import 'assessment_draft.dart';

/// El contexto V2 citado: sus bytes exactos, su huella y el documento.
final class CitedContext {
  const CitedContext(this.context, this.bytes, this.digest);

  final ProjectContext context;
  final List<int> bytes;
  final String digest;
}

/// `shipflow/project.json` leído por el almacén anclado y validado por el
/// codec de V2; si falta o no valida, el diagnóstico queda en [draft].
Future<CitedContext?> readCitedContext(
  ContextStore store,
  AssessmentDraft draft,
) async {
  final List<int>? bytes;
  try {
    bytes = await store.readRelative(projectPath, maxBytes: maxProjectBytes);
  } on ContextStoreFailure {
    draft.add('io_failure');
    return null;
  }
  if (bytes == null) {
    draft.add('context_absent');
    return null;
  }
  try {
    final context = const ContextCodec().decodeProject(bytes);
    return CitedContext(context, bytes, sha256Of(bytes));
  } on ContextFormatException {
    draft.add('context_invalid', examples: [projectPath]);
    return null;
  }
}

/// Lo que V2 dice hoy, traducido: el contexto debe ser válido, compatible y
/// vigente; su elección aplicada, o pendiente sólo sin Git; sin operaciones
/// de init ni de assess sin terminar. No escribe nada.
Future<CitedContext?> preflightObserve(
  ContextOperationResult doctor,
  StateOwnership ownership,
  ContextStore store,
  AssessmentDraft draft,
) async {
  draft.gitQueries = doctor.effects.processesStarted;
  for (final d in doctor.diagnostics) {
    if (_fromContext(d.code, doctor.sharing) case final code?) {
      if (!draft.has(code)) draft.add(code, examples: [?d.path]);
    }
  }
  final choiceMissing =
      doctor.sharing.choice == SharingChoice.pending &&
      doctor.sharing.gitState == GitState.available;
  if (choiceMissing && !draft.has('choice_required')) {
    draft.add('choice_required');
  }
  if (ownership.assessmentJournal) draft.add('assessment_recovery_pending');
  if (draft.stopped) return null;
  return readCitedContext(store, draft);
}

/// El código V3 de un diagnóstico de doctor, o null si no afecta a assess.
String? _fromContext(String code, ContextSharing sharing) => switch (code) {
  'recovery_pending' => 'context_recovery_pending',
  'bootstrap_unverified' || 'journal_invalid' => 'state_invalid',
  'not_initialized' || 'ancestor_context' => 'context_absent',
  'recognition_unverified' || 'not_eligible' => 'context_unverified',
  'already_tracked' ||
  'binding_changed' ||
  'sharing_unavailable' => 'sharing_conflict',
  'git_unverified' => 'git_unavailable',
  'choice_pending' =>
    sharing.gitState == GitState.available ? 'choice_required' : null,
  'exclude_shared' || 'detail_omitted' => null,
  'invalid_root' ||
  'io_failure' ||
  'unexpected' ||
  'busy' ||
  'concurrent_change' ||
  'recovery_conflict' ||
  'context_invalid' ||
  'context_incompatible' ||
  'state_occupied' ||
  'state_invalid' ||
  'context_absent' ||
  'context_stale' ||
  'choice_required' ||
  'sharing_conflict' ||
  'git_unavailable' ||
  'git_absent' => code,
  _ => 'context_invalid',
};
