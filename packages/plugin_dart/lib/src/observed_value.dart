import 'dart:convert';

/// El máximo, en bytes UTF-8, de una cadena extraída de una fuente.
const maxObservedValueBytes = 4096;

const _ellipsis = '…';

/// [raw] dentro de [maxObservedValueBytes]: tal cual si cabe, o un adelanto
/// UTF-8 válido terminado en `…` que, con él, sigue cabiendo.
({String text, bool truncated}) boundObservedValue(String raw) {
  if (utf8.encode(raw).length <= maxObservedValueBytes) {
    return (text: raw, truncated: false);
  }
  final budget = maxObservedValueBytes - utf8.encode(_ellipsis).length;
  final preview = StringBuffer();
  var used = 0;
  for (final rune in raw.runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (used + size > budget) break;
    preview.writeCharCode(rune);
    used += size;
  }
  return (text: '$preview$_ellipsis', truncated: true);
}
