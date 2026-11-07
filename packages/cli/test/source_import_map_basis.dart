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
};
