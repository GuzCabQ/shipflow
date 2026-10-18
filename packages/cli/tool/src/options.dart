/// Lee [arguments] como pares `--nombre valor`, con cada nombre de [names] a
/// lo sumo una vez. Devuelve null ante cualquier otra forma; qué opciones son
/// obligatorias lo decide cada herramienta.
Map<String, String>? parseNamedOptions(
  List<String> arguments,
  Set<String> names,
) {
  if (arguments.length.isOdd) return null;
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    final name = arguments[i];
    if (!names.contains(name) || options.containsKey(name)) return null;
    options[name] = arguments[i + 1];
  }
  return options;
}
