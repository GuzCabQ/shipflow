import 'package:yaml/yaml.dart';

import 'observed_value.dart';

/// Una entrada de `flutter.assets` que el reconocimiento distingue.
sealed class ResourceEntry {
  const ResourceEntry();
}

/// Un directorio literal bajo `assets/`, normalizado y con `/` final.
final class ResourceDirectory extends ResourceEntry {
  const ResourceDirectory(this.path);

  final String path;
}

/// Una forma que este corte no interpreta: no concede exclusiones.
final class UnsupportedResource extends ResourceEntry {
  const UnsupportedResource(this.message);

  final String message;
}

const _globCharacters = ['*', '?', '[', ']', '{', '}'];

/// Las entradas de `flutter.assets` de a una. Un archivo declarado no se
/// informa: no autoriza excluir su carpeta. `flutter.fonts` no se mira.
Iterable<ResourceEntry> resourceEntries(Object? flutter) sync* {
  if (flutter == null) return;
  if (flutter is! YamlMap) {
    yield const UnsupportedResource('«flutter» no es un mapa');
    return;
  }
  final assets = flutter['assets'];
  if (assets == null) return;
  if (assets is! YamlList) {
    yield const UnsupportedResource('«flutter.assets» no es una lista');
    return;
  }
  for (final (index, item) in assets.indexed) {
    if (_entry(item) case final entry?) {
      yield entry is UnsupportedResource
          ? UnsupportedResource('«flutter.assets[$index]» ${entry.message}')
          : entry;
    }
  }
}

ResourceEntry? _entry(Object? item) {
  if (item is! String) return const UnsupportedResource('no es una ruta');
  if (boundObservedValue(item).truncated) {
    return const UnsupportedResource('excede $maxObservedValueBytes bytes');
  }
  if (item.contains('\x00') ||
      item.contains(r'\') ||
      item.contains(':') ||
      _globCharacters.any(item.contains)) {
    return const UnsupportedResource(
      'no es una ruta literal: tiene NUL, URI, patrón o separador invertido',
    );
  }
  return item.endsWith('/') ? _directory(item) : null;
}

/// `./` inicial admitido; absoluto, `.`, `..` o tramos vacíos, no. Tiene que
/// quedar dentro de `assets/`, y nunca puede ser la raíz del paquete.
ResourceEntry _directory(String declared) {
  var path = declared;
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  if (path.isEmpty) {
    return const UnsupportedResource('nombra la raíz del paquete');
  }
  final parts = path.substring(0, path.length - 1).split('/');
  if (path.startsWith('/') ||
      parts.any((p) => p.isEmpty || p == '.' || p == '..')) {
    return const UnsupportedResource(
      'no es un directorio relativo sin tramos vacíos, «.» ni «..»',
    );
  }
  if (parts.first != 'assets') {
    return const UnsupportedResource('no está dentro de «assets/»');
  }
  return ResourceDirectory('${parts.join('/')}/');
}

/// La descripción declarada, si es texto que cabe entero; si no, por qué
/// se omite. Nunca se trunca: un adelanto no es la descripción.
({String? value, String? problem}) declaredDescription(Object? node) =>
    switch (node) {
      null => (value: null, problem: null),
      final String text when !boundObservedValue(text).truncated => (
        value: text,
        problem: null,
      ),
      String() => (value: null, problem: 'excede $maxObservedValueBytes bytes'),
      _ => (value: null, problem: 'no es texto'),
    };
