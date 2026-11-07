// Lo que cada archivo de `lib/src/basis` puede importar o exportar.

const basisImports = {
  'lib/src/basis/basis_canonical.dart': {
    'dart:convert',
    'package:crypto/crypto.dart',
  },
  'lib/src/basis/basis_codec.dart': {
    'dart:convert',
    'package:core/core.dart',
    '../context/strict_json.dart',
    'basis_canonical.dart',
    'basis_document_shape.dart',
    'basis_response_shape.dart',
  },
  'lib/src/basis/basis_document_shape.dart': {
    'package:core/core.dart',
    '../context/context_shape.dart',
    'basis_shape.dart',
  },
  'lib/src/basis/basis_preconditions.dart': {
    'package:core/core.dart',
    '../context/state_layout.dart',
    'basis_sources.dart',
  },
  'lib/src/basis/basis_preflight.dart': {
    'package:core/core.dart',
    '../context/context_codec.dart',
    '../context/secure_context_store.dart',
    '../context/state_layout.dart',
    'basis_canonical.dart',
  },
  'lib/src/basis/basis_response_shape.dart': {
    'package:core/core.dart',
    '../context/context_shape.dart',
    'basis_document_shape.dart',
    'basis_shape.dart',
  },
  'lib/src/basis/basis_shape.dart': {
    'package:core/core.dart',
    '../context/context_shape.dart',
  },
  'lib/src/basis/basis_source_policy.dart': <String>{},
  'lib/src/basis/basis_sources.dart': {
    'dart:convert',
    'package:core/core.dart',
    '../context/secure_context_store.dart',
    'basis_canonical.dart',
    'basis_source_policy.dart',
  },
};
