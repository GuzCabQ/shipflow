// Lo que cada archivo de `lib` y `bin` del CLI puede importar o exportar.
// Fijarlo hace visible en la revisión toda dependencia nueva.

import 'source_import_map_assessment.dart';
import 'source_import_map_basis.dart';
import 'source_import_map_context.dart';

/// Cada archivo de `lib` y `bin` con lo que importa o exporta.
const expectedImports = {
  'bin/shipflow.dart': {
    'dart:io',
    'package:cli/cli.dart',
    'package:plugin_dart/plugin_dart.dart',
  },
  'lib/cli.dart': {
    'src/assessment/assessment_cli.dart',
    'src/build_version.dart',
    'src/cli_application.dart',
    'src/cli_command.dart',
    'src/cli_emitter.dart',
    'src/cli_process_boundary.dart',
    'src/cli_response.dart',
    'src/logical_root.dart',
    'src/bounded_recognition_json.dart',
    'src/recognition_presenter.dart',
    'src/recognition_runner.dart',
  },
  'lib/src/bounded_recognition_json.dart': {
    'dart:convert',
    'package:core/core.dart',
    'cli_application.dart',
  },
  'lib/src/build_version.dart': <String>{},
  'lib/src/cli_application.dart': {
    'dart:convert',
    'cli_command.dart',
    'cli_help.dart',
    'cli_response.dart',
  },
  'lib/src/assessment_grammar.dart': {
    'package:core/core.dart',
    'cli_command.dart',
    'cli_grammar.dart',
  },
  'lib/src/cli_command.dart': {
    'package:core/core.dart',
    'assessment_grammar.dart',
    'cli_grammar.dart',
  },
  'lib/src/cli_emitter.dart': {
    'dart:convert',
    'dart:io',
    'cli_response.dart',
    'internal_failure.dart',
  },
  'lib/src/cli_grammar.dart': {
    'package:core/core.dart',
    'cli_command.dart',
    'terminal_text.dart',
  },
  'lib/src/cli_help.dart': {'cli_command.dart'},
  'lib/src/cli_process_boundary.dart': {
    'dart:io',
    'package:vcs/vcs.dart',
    'assessment/assessment_cli.dart',
    'cli_command.dart',
    'context/context_prompt.dart',
    'cli_response.dart',
    'internal_failure.dart',
    'recognition_runner.dart',
  },
  'lib/src/cli_response.dart': <String>{},
  'lib/src/internal_failure.dart': {
    'cli_application.dart',
    'cli_response.dart',
  },
  'lib/src/logical_root.dart': {'dart:convert', 'dart:io'},
  'lib/src/recognition_human.dart': {
    'package:core/core.dart',
    'cli_command.dart',
    'recognition_human_context.dart',
    'recognition_human_findings.dart',
    'recognition_human_support.dart',
  },
  'lib/src/recognition_human_context.dart': {
    'package:core/core.dart',
    'recognition_human_support.dart',
  },
  'lib/src/recognition_human_findings.dart': {
    'package:core/core.dart',
    'recognition_human_support.dart',
  },
  'lib/src/recognition_human_support.dart': {'terminal_text.dart'},
  'lib/src/recognition_presenter.dart': {
    'package:core/core.dart',
    'bounded_recognition_json.dart',
    'cli_command.dart',
    'cli_response.dart',
    'recognition_human.dart',
  },
  'lib/src/recognition_runner.dart': {
    'dart:io',
    'package:core/core.dart',
    'package:vcs/vcs.dart',
    'assessment/assessment_cli.dart',
    'cli_application.dart',
    'cli_command.dart',
    'cli_response.dart',
    'logical_root.dart',
    'context/context_cli.dart',
    'context/context_prompt.dart',
    'context/state_ownership.dart',
    'recognition_presenter.dart',
  },
  'lib/src/terminal_text.dart': <String>{},
  ...assessmentImports,
  ...basisImports,
  ...contextImports,
};
