// Lo que cada archivo de `lib/src/assessment` puede importar o exportar.

const assessmentImports = {
  'lib/src/assessment/assessment_binding.dart': {'package:core/core.dart'},
  'lib/src/assessment/assessment_codec.dart': {
    'dart:convert',
    'package:core/core.dart',
    'package:crypto/crypto.dart',
    '../context/strict_json.dart',
    'assessment_journal_shape.dart',
    'assessment_response_shape.dart',
    'assessment_shape.dart',
  },
  'lib/src/assessment/assessment_journal_shape.dart': {
    'package:core/core.dart',
    '../context/context_shape.dart',
  },
  'lib/src/assessment/assessment_response_shape.dart': {
    'package:core/core.dart',
    '../context/context_shape.dart',
    'assessment_shape.dart',
  },
  'lib/src/assessment/assessment_shape.dart': {
    'package:core/core.dart',
    '../context/context_shape.dart',
  },
};
