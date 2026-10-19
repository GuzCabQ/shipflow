import 'dart:io';

import 'recognition_codes.dart';
import 'stable_file_reader.dart';

const linkMessage = 'es un enlace simbólico y no se sigue';

const _directory = FileSystemEntityType.directory;
const _file = FileSystemEntityType.file;

/// La raíz real fijada al empezar y las comprobaciones de que una ruta
/// enumerada sigue siendo lo que era, dentro de ella.
final class RootGuard {
  RootGuard(this.root) : _authorizedRoot = _canonical(root.path);

  final Directory root;

  /// La raíz real al empezar. Las rutas se comparan con ella y no con una
  /// nueva resolución de [root], que otro proceso pudo cambiar por un enlace.
  final String? _authorizedRoot;

  String relative(String path) {
    final prefix = root.path.endsWith('/') ? root.path : '${root.path}/';
    return path == root.path ? '.' : path.substring(prefix.length);
  }

  ({String code, String message})? escapedDirectory(String path) =>
      _escaped(path, _directory);

  ({String code, String message})? escapedFile(String path) =>
      _escaped(path, _file);

  /// Por qué [path] ya no es lo que se enumeró: un [expected] sin enlaces
  /// dentro de la raíz. Se comprueba antes y después de usarlo, porque entre
  /// la enumeración y el uso otro proceso pudo cambiar un tramo por un enlace
  /// y el sistema lo seguiría. Queda la ventana de cambiarlo y restaurarlo
  /// entre ambas comprobaciones; en una fuente, además con lecturas iguales.
  ({String code, String message})? _escaped(
    String path,
    FileSystemEntityType expected,
  ) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      return (code: LimitationCode.symlinkNotFollowed, message: linkMessage);
    }
    if (type != expected) {
      return expected == _file
          ? (
              code: LimitationCode.sourceUnreadable,
              message: 'no es un archivo regular; no se abrió',
            )
          : (
              code: LimitationCode.sourceChanged,
              message: 'dejó de ser un directorio durante el recorrido',
            );
    }
    if (_authorizedRoot != null &&
        _canonical(path) == '$_authorizedRoot/${relative(path)}') {
      return null;
    }
    return (
      code: LimitationCode.sourceChanged,
      message: 'su ruta salió de la raíz durante el recorrido; no se usó',
    );
  }
}

/// La ruta real de [path], o null si ya no se puede resolver.
String? _canonical(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

/// El código y el motivo de una fuente que no se aceptó.
(String, String) rejectionOf(StableRead read) => switch (read) {
  OversizedSource(:final size) => (
    LimitationCode.sourceTooLarge,
    'mide $size bytes y excede su máximo; no se leyó',
  ),
  UnstableSource() => (
    LimitationCode.sourceChanged,
    'cambió entre dos lecturas; la observación no es estable',
  ),
  UnreadableSource(:final reason) => (
    LimitationCode.sourceUnreadable,
    'no se pudo leer ($reason)',
  ),
  StableSource() => throw StateError('una fuente estable no se rechaza'),
};

/// El último tramo de [path].
String nameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

int byName(FileSystemEntity a, FileSystemEntity b) =>
    nameOf(a.path).compareTo(nameOf(b.path));
