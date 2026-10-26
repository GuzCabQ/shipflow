import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

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
  final store = await SecureContextStore.open(root);
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
  final invalid = <String>[];
  final valid = <String>{};
  for (final path in layout.documents) {
    if (await _validDocument(store, path)) {
      valid.add(path);
    } else {
      invalid.add(path);
    }
  }
  if (!await _ownGitignore(store, layout)) {
    return StateOwnership(StateOwnershipKind.foreign, [gitignorePath]);
  }
  if (invalid.isNotEmpty) {
    return StateOwnership(StateOwnershipKind.invalid, invalid);
  }
  return _decide(layout, valid);
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

Future<bool> _validDocument(SecureContextStore store, String path) async {
  const codec = ContextCodec();
  try {
    final bytes = await store.readRelative(path, maxBytes: maxProjectBytes);
    if (bytes == null) return false;
    switch (documentKindOf(path)) {
      case DocumentKind.project:
        codec.decodeProject(bytes);
      case DocumentKind.settings:
        codec.decodeSettings(bytes);
      case DocumentKind.transaction:
        codec.decodeTransaction(bytes);
    }
    return true;
  } on ContextFormatException {
    return false;
  } on ContextStoreFailure {
    return false;
  }
}

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
