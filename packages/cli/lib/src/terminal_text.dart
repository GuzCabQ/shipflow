/// [value] en una sola línea acotada: escapa controles, separadores de línea
/// y controles bidireccionales, y corta después de [maxRunes] runes visibles
/// con `…`.
String singleLine(String value, {required int maxRunes}) {
  final shown = StringBuffer();
  var length = 0;
  for (final rune in value.runes) {
    final piece = _escape(rune);
    final pieceLength = piece.runes.length;
    if (length + pieceLength > maxRunes) return '$shown…';
    shown.write(piece);
    length += pieceLength;
  }
  return '$shown';
}

String _escape(int rune) {
  switch (rune) {
    case 0x0A:
      return r'\n';
    case 0x0D:
      return r'\r';
    case 0x09:
      return r'\t';
    case 0x5C:
      return r'\\';
    case 0x27:
      return r"\'";
  }
  if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
    return '\\x${rune.toRadixString(16).padLeft(2, '0')}';
  }
  if (_isInvisibleControl(rune)) {
    return '\\u{${rune.toRadixString(16)}}';
  }
  return String.fromCharCode(rune);
}

/// Los separadores de línea, los controles bidireccionales y los sustitutos
/// sueltos pueden partir o reordenar una línea de terminal aunque los
/// caracteres de control ya estén escapados.
bool _isInvisibleControl(int rune) =>
    rune == 0x2028 ||
    rune == 0x2029 ||
    (rune >= 0x202A && rune <= 0x202E) ||
    (rune >= 0x2066 && rune <= 0x2069) ||
    (rune >= 0xD800 && rune <= 0xDFFF);
