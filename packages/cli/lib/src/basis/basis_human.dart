import 'package:core/core.dart';

import '../terminal_text.dart';

/// La vista humana de [result], derivada de los mismos datos que el JSON.
String renderBasisHuman(BasisResponse result) {
  final lines = <String>[
    'Base guiada: ${result.outcome.toWireName()} (código ${result.exitCode}).',
    for (final d in result.diagnostics)
      '- ${singleLine(d.message, maxRunes: 200)}',
    for (final a in result.nextActions)
      '  shipflow ${a.command} ${a.arguments.join(' ')}',
  ];
  return '${lines.join('\n')}\n';
}
