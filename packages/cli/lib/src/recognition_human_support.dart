import 'terminal_text.dart';

const maxShownRunes = 240;

/// Un valor del proyecto en una línea segura y acotada.
String shown(String value) => singleLine(value, maxRunes: maxShownRunes);

/// Cuántas filas no se muestran, con [indent], o null si no falta ninguna.
String? more(int extra, String singular, String plural, String indent) =>
    extra <= 0
    ? null
    : extra == 1
    ? '${indent}Hay 1 $singular adicional; consulta la salida JSON.'
    : '${indent}Hay $extra $plural adicionales; consulta la salida JSON.';
