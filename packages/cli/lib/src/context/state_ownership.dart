import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

import '../assessment/assessment_codec.dart';
import '../basis/basis_codec.dart';
import 'context_codec.dart';
import 'secure_context_store.dart';
import 'state_layout.dart';

export 'state_layout.dart'
    show StateOwnership, StateOwnershipKind, generatedGitignore, stateDirectory;

/// La omisión de política que la raíz de composición entrega al plugin.
List<AuthorizedOmission> authorizedStateOmissions(StateOwnership ownership) =>
    ownership.authorizesOmission
    ? [
        AuthorizedOmission(
          relativePath: stateDirectory,
          rule: OmissionRule.toolState,
        ),
      ]
    : const [];

/// Clasifica `shipflow/` de [root] sin escribir, sin seguir enlaces y sin
/// abrir FIFOs: su forma por metadatos, y sus documentos por el almacén
/// anclado y el codec estricto.
Future<StateOwnership> inspectStateOwnership(Directory root) async {
  final layout = await observeStateLayout(root);
  if (layout case StateOwnership ownership) return ownership;
  final observed = layout as ObservedLayout;
  if (observed.entries.isEmpty) return StateOwnership(StateOwnershipKind.empty);
  final SecureContextStore store;
  try {
    store = await SecureContextStore.open(root);
  } on ContextStoreFailure {
    // Sin almacén anclado no se puede acreditar la propiedad.
    return StateOwnership(StateOwnershipKind.invalid, [stateDirectory]);
  }
  try {
    return await _classify(store, observed);
  } finally {
    await store.close();
  }
}

Future<StateOwnership> _classify(
  SecureContextStore store,
  ObservedLayout layout,
) async {
  final (:valid, :invalid) = await _documents(store, layout);
  if (!await _ownGitignore(store, layout)) {
    return StateOwnership(StateOwnershipKind.foreign, [gitignorePath]);
  }
  // Un levantamiento o una base que no validan no invalidan el contexto:
  // su propio comando los informa y conserva; init y doctor siguen sobre
  // project.json, y doctor los muestra en sus checks.
  if (valid.contains(projectPath)) invalid.removeWhere(_ownedApart.contains);
  if (invalid.isNotEmpty) {
    return StateOwnership(StateOwnershipKind.invalid, invalid);
  }
  final unproven = [
    ...await _unprovenAssessment(store, layout, valid),
    ...await _unprovenBasis(store, layout, valid),
  ];
  if (unproven.isNotEmpty) {
    return StateOwnership(StateOwnershipKind.invalid, unproven);
  }
  final decided = _decide(layout, valid);
  return StateOwnership(
    decided.kind,
    decided.findings,
    valid.contains(assessmentTransactionPath),
    _stateOf(layout, valid, basisDocumentPath),
    _stateOf(layout, valid, basisTransactionPath),
  );
}

/// Documentos propios que su comando gobierna aparte del contexto.
const _ownedApart = {
  assessmentDocumentPath,
  basisDocumentPath,
  basisDraftPath,
  basisTransactionPath,
};

BasisIntegrity _stateOf(
  ObservedLayout layout,
  Set<String> valid,
  String path,
) => !layout.documents.contains(path)
    ? BasisIntegrity.absent
    : valid.contains(path)
    ? BasisIntegrity.valid
    : BasisIntegrity.invalid;

/// Los restos de bootstrap que no se pueden acreditar: sin su journal, un
/// temporal nunca, y un candidato sólo si está completo y valida.
Future<List<String>> _unprovenBasis(
  SecureContextStore store,
  ObservedLayout layout,
  Set<String> valid,
) async {
  if (valid.contains(basisTransactionPath)) return const [];
  return [
    ...layout.basisTemporaries,
    for (final candidate in layout.basisCandidates)
      if (!await _validBasisCandidate(store, candidate)) candidate,
  ];
}

final _ownershipLimits = BasisLimits.forProfile(BasisProfile.extended);

Future<bool> _validBasisCandidate(SecureContextStore store, String path) async {
  try {
    final bytes = await store.readRelative(
      path,
      maxBytes: _ownershipLimits.maxBasisBytes,
    );
    if (bytes == null) return false;
    decodeBasis(bytes, limits: _ownershipLimits);
    return true;
  } on ContextFormatException {
    return false;
  } on ContextStoreFailure {
    return false;
  }
}

/// Los restos de assess que no se pueden acreditar: sin su journal, un
/// temporal nunca, y un candidato sólo si está completo y valida.
Future<List<String>> _unprovenAssessment(
  SecureContextStore store,
  ObservedLayout layout,
  Set<String> valid,
) async {
  if (valid.contains(assessmentTransactionPath)) return const [];
  return [
    ...layout.assessmentTemporaries,
    for (final candidate in layout.assessmentCandidates)
      if (!await _validCandidate(store, candidate)) candidate,
  ];
}

Future<bool> _validCandidate(SecureContextStore store, String path) async {
  try {
    final bytes = await store.readRelative(
      path,
      maxBytes: maxAssessmentDocumentBytes,
    );
    if (bytes == null) return false;
    decodeAssessment(bytes);
    return true;
  } on ContextFormatException {
    return false;
  } on ContextStoreFailure {
    return false;
  }
}

/// Bootstrap sin documentos ni restos; propio con contexto o journal
/// válido. Un temporal o un staging sólo se toleran junto a un journal.
StateOwnership _decide(ObservedLayout layout, Set<String> valid) {
  final journal = valid.contains(transactionPath);
  final leftovers = [...layout.temporaries, ...layout.staging];
  if (valid.isEmpty && leftovers.isEmpty) {
    return StateOwnership(StateOwnershipKind.bootstrap);
  }
  if (!journal && leftovers.isNotEmpty) {
    return StateOwnership(StateOwnershipKind.invalid, leftovers);
  }
  if (journal || valid.contains(projectPath)) {
    return StateOwnership(StateOwnershipKind.owned, leftovers);
  }
  return StateOwnership(StateOwnershipKind.invalid, [...valid]..sort());
}

/// Los documentos de [layout] que validan y los que no.
Future<({Set<String> valid, List<String> invalid})> _documents(
  SecureContextStore store,
  ObservedLayout layout,
) async {
  final valid = <String>{};
  final invalid = <String>[];
  for (final path in layout.documents) {
    if (await _validDocument(store, path)) {
      valid.add(path);
    } else {
      invalid.add(path);
    }
  }
  return (valid: valid, invalid: invalid);
}

Future<bool> _validDocument(SecureContextStore store, String path) async {
  try {
    final kind = documentKindOf(path);
    final bytes = await store.readRelative(path, maxBytes: _maxBytes(kind));
    if (bytes == null) return false;
    _decode(kind, bytes);
    return true;
  } on ContextFormatException {
    return false;
  } on ContextStoreFailure {
    return false;
  }
}

/// [bytes] por el codec estricto de [kind]; lanza si no valida.
void _decode(DocumentKind kind, List<int> bytes) {
  const codec = ContextCodec();
  switch (kind) {
    case DocumentKind.project:
      codec.decodeProject(bytes);
    case DocumentKind.settings:
      codec.decodeSettings(bytes);
    case DocumentKind.transaction:
      codec.decodeTransaction(bytes);
    case DocumentKind.assessment:
      decodeAssessment(bytes);
    case DocumentKind.assessmentTransaction:
      decodeAssessmentTransaction(bytes);
    case DocumentKind.basis:
      decodeBasis(bytes, limits: _ownershipLimits);
    case DocumentKind.basisDraft:
      decodeBasisDraft(bytes, limits: _ownershipLimits);
    case DocumentKind.basisTransaction:
      decodeBasisTransaction(bytes, limits: _ownershipLimits);
  }
}

int _maxBytes(DocumentKind kind) => switch (kind) {
  DocumentKind.assessment => maxAssessmentDocumentBytes,
  DocumentKind.basis => _ownershipLimits.maxBasisBytes,
  DocumentKind.basisDraft ||
  DocumentKind.basisTransaction => _ownershipLimits.maxDraftBytes,
  _ => maxProjectBytes,
};

/// Un `.gitignore` sólo puede tener los bytes exactos que genera init.
Future<bool> _ownGitignore(
  SecureContextStore store,
  ObservedLayout layout,
) async {
  if (!layout.hasGitignore) return true;
  try {
    final bytes = await store.readRelative(gitignorePath, maxBytes: 4096);
    return bytes != null &&
        utf8.decode(bytes, allowMalformed: true) == generatedGitignore;
  } on ContextStoreFailure {
    return false;
  }
}
