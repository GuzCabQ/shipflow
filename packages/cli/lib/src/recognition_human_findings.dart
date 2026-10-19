import 'package:core/core.dart';

import 'recognition_human_support.dart';

const _maxGroups = 10;
const _maxEntries = 5;

/// Una línea ya escrita, con el código que la agrupa.
typedef _Entry = ({String code, String line});

/// Lo que impide continuar y lo que sólo advierte, agrupado por código con
/// su cuenta real. Un conflicto siempre bloquea; una limitación, si lo dice.
final class Findings {
  Findings(RecognitionReport report)
    : _blocking = [
        for (final c in report.conflicts)
          (code: c.code, line: _conflict(c, report)),
        for (final l in report.limitations)
          if (l.blocking) (code: l.code, line: _limitation(l)),
      ],
      _warnings = [
        for (final l in report.limitations)
          if (!l.blocking) (code: l.code, line: _limitation(l)),
      ];

  final List<_Entry> _blocking;
  final List<_Entry> _warnings;

  bool get blocked => _blocking.isNotEmpty;
  bool get empty => _blocking.isEmpty && _warnings.isEmpty;

  /// La línea que anuncia las causas antes del inventario, o null.
  String? get summary => switch (_blocking.length) {
    0 => null,
    1 => 'Hay 1 causa que impide continuar; se detalla en «Resultado».',
    final n =>
      'Hay $n causas que impiden continuar; se detallan en '
          '«Resultado».',
  };

  List<String> lines() => [
    if (_blocking.isNotEmpty) ...[
      '  Qué impide continuar:',
      ..._grouped(_blocking),
    ],
    if (_warnings.isNotEmpty) ...[
      '  Advertencias que no bloquean:',
      ..._grouped(_warnings),
    ],
  ];
}

/// Hasta diez grupos en orden de aparición, cada uno con hasta cinco filas.
List<String> _grouped(List<_Entry> entries) {
  final groups = <String, List<String>>{};
  for (final e in entries) {
    groups.putIfAbsent(e.code, () => []).add(e.line);
  }
  return [
    for (final MapEntry(key: code, value: lines) in groups.entries.take(
      _maxGroups,
    )) ...[
      '    ${shown(code)} (${lines.length}):',
      for (final line in lines.take(_maxEntries)) '      - $line',
      if (lines.length > _maxEntries)
        '      Y ${lines.length - _maxEntries} más del mismo tipo; consulta '
            'la salida JSON.',
    ],
    ?more(groups.length - _maxGroups, 'grupo', 'grupos', '    '),
  ];
}

/// Un conflicto con sus fuentes y su valor, hasta cinco.
String _conflict(RecognitionConflict c, RecognitionReport report) {
  final evidence = {for (final e in report.evidence) e.id: e};
  final ids = c.evidenceIds;
  if (ids.isEmpty) return shown(c.message);
  final sources = [
    for (final id in ids.take(_maxEntries))
      if (evidence[id] case final e?) '${shown(e.path)} (${shown(e.value)})',
  ];
  final rest = ids.length - _maxEntries;
  return '${shown(c.message)} · fuentes: ${sources.join(', ')}'
      '${rest > 0 ? ' y $rest más' : ''}';
}

String _limitation(RecognitionLimitation l) {
  final message = l.code == reportLimitReachedCode
      ? splitLimitMessage(l.message).finding
      : l.message;
  return '${shown(message)}${l.path == null ? '' : ' · ${shown(l.path!)}'}';
}

/// El mensaje del límite de reporte en lo que pasó y lo que se puede hacer:
/// su primera oración, y el resto.
({String finding, String action}) splitLimitMessage(String message) {
  final cut = message.indexOf('. ');
  if (cut < 0) return (finding: message, action: '');
  return (
    finding: message.substring(0, cut + 1),
    action: message.substring(cut + 2),
  );
}
