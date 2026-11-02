import 'dart:convert';

import 'package:core/core.dart';

import 'context_codec.dart';
import 'context_decisions.dart';

const _maxCompactDiagnostics = 10;

/// La respuesta JSON de [result] con su salto final, dentro de [maxBytes].
/// Si el detalle no cabe, una versión compacta conserva outcome, código,
/// estados, efectos reales y siguientes acciones, sin el contexto; nunca un
/// JSON truncado.
String encodeContextWithinLimit(
  ContextOperationResult result, {
  int maxBytes = maxResponseBytes,
}) {
  final full = '${jsonEncode(result.toJson())}\n';
  if (utf8.encode(full).length <= maxBytes) return full;
  return '${jsonEncode(_compact(result).toJson())}\n';
}

ContextOperationResult _compact(ContextOperationResult r) =>
    ContextOperationResult(
      command: r.command,
      operation: r.operation,
      outcome: r.outcome,
      exitCode: r.exitCode,
      contextState: r.contextState,
      freshness: r.freshness,
      sharing: r.sharing,
      checks: r.checks,
      diagnostics: [
        ...r.diagnostics.take(_maxCompactDiagnostics),
        diagnostic(
          'detail_omitted',
          'La respuesta completa no cabe; se omitió el contexto guardado. '
              'Consulta el archivo con shipflow doctor.',
        ),
      ],
      context: null,
      effects: r.effects,
      nextActions: r.nextActions,
    );
