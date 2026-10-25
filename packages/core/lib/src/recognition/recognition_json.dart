/// Lee una lista JSON de objetos con [read].
List<T> readObjects<T>(
  Object? json,
  T Function(Map<String, Object?> json) read,
) => [
  for (final item in json! as List<Object?>)
    read(item! as Map<String, Object?>),
];

/// Lee una lista JSON de cadenas.
List<String> readStrings(Object? json) => [
  for (final item in json! as List<Object?>) item! as String,
];

/// Lee un objeto JSON con [read].
T readObject<T>(Object? json, T Function(Map<String, Object?> json) read) =>
    read(json! as Map<String, Object?>);
