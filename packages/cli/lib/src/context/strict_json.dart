import 'dart:convert';

import 'package:core/core.dart';

/// La profundidad máxima de anidamiento de un documento de contexto.
const maxContextJsonDepth = 64;

/// [bytes] como JSON estricto, antes de materializar nada que no quepa: a
/// lo sumo [maxBytes] bytes, UTF-8 sin BOM, sin claves repetidas, sin
/// sustitutos sueltos, a lo sumo [maxDepth] niveles y sólo números enteros.
/// Un objeto conserva el orden de sus claves.
Object? decodeStrictJson(
  List<int> bytes, {
  required int maxBytes,
  int maxDepth = maxContextJsonDepth,
}) {
  if (bytes.length > maxBytes) throw _parser('too_large');
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    throw _parser('invalid_json');
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw _parser('invalid_utf8');
  }
  return _Parser(text, maxDepth).document();
}

ContextFormatException _parser(String code) =>
    ContextFormatException(ContextFormatLayer.parser, code);

final class _Parser {
  _Parser(this.text, this.maxDepth);

  final String text;
  final int maxDepth;
  var position = 0;
  var depth = 0;

  Object? document() {
    final value = this.value();
    _whitespace();
    if (position != text.length) throw _parser('invalid_json');
    return value;
  }

  Object? value() {
    _whitespace();
    if (position >= text.length) throw _parser('invalid_json');
    return switch (text[position]) {
      '{' => _object(),
      '[' => _array(),
      '"' => _string(),
      't' => _literal('true', true),
      'f' => _literal('false', false),
      'n' => _literal('null', null),
      _ => _integer(),
    };
  }

  Map<String, Object?> _object() {
    _enter();
    final map = <String, Object?>{};
    if (_next('}')) return _leave(map);
    do {
      _whitespace();
      if (!_at('"')) throw _parser('invalid_json');
      final key = _string();
      if (map.containsKey(key)) throw _parser('duplicate_key');
      _whitespace();
      _expect(':');
      map[key] = value();
      _whitespace();
    } while (_next(','));
    _expect('}');
    return _leave(map);
  }

  List<Object?> _array() {
    _enter();
    final list = <Object?>[];
    if (_next(']')) return _leave(list);
    do {
      list.add(value());
      _whitespace();
    } while (_next(','));
    _expect(']');
    return _leave(list);
  }

  void _enter() {
    position++;
    if (++depth > maxDepth) throw _parser('too_deep');
    _whitespace();
  }

  T _leave<T>(T value) {
    depth--;
    return value;
  }

  String _string() {
    position++;
    final buffer = StringBuffer();
    while (true) {
      if (position >= text.length) throw _parser('invalid_json');
      final unit = text.codeUnitAt(position++);
      if (unit == 0x22) break;
      if (unit < 0x20) throw _parser('invalid_json');
      buffer.writeCharCode(unit == 0x5C ? _escape() : unit);
    }
    final result = buffer.toString();
    if (!isWellFormedText(result)) throw _parser('invalid_text');
    return result;
  }

  int _escape() {
    if (position >= text.length) throw _parser('invalid_json');
    final escaped = text[position++];
    return switch (escaped) {
      '"' => 0x22,
      r'\' => 0x5C,
      '/' => 0x2F,
      'b' => 0x08,
      'f' => 0x0C,
      'n' => 0x0A,
      'r' => 0x0D,
      't' => 0x09,
      'u' => _hex(),
      _ => throw _parser('invalid_json'),
    };
  }

  int _hex() {
    if (position + 4 > text.length) throw _parser('invalid_json');
    final digits = text.substring(position, position + 4);
    if (!RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(digits)) {
      throw _parser('invalid_json');
    }
    position += 4;
    return int.parse(digits, radix: 16);
  }

  /// Sólo enteros: una fracción o un exponente no es un valor de contexto.
  int _integer() {
    final match = RegExp(r'-?(?:0|[1-9][0-9]*)').matchAsPrefix(text, position);
    if (match == null) throw _parser('invalid_json');
    position = match.end;
    if (position < text.length && '.eE'.contains(text[position])) {
      throw _parser('invalid_json');
    }
    return int.tryParse(match[0]!) ?? (throw _parser('invalid_json'));
  }

  Object? _literal(String word, Object? value) {
    if (!text.startsWith(word, position)) throw _parser('invalid_json');
    position += word.length;
    return value;
  }

  void _whitespace() {
    while (position < text.length && ' \t\n\r'.contains(text[position])) {
      position++;
    }
  }

  bool _at(String char) => position < text.length && text[position] == char;

  bool _next(String char) {
    if (!_at(char)) return false;
    position++;
    return true;
  }

  void _expect(String char) {
    if (!_next(char)) throw _parser('invalid_json');
  }
}
