import 'dart:io';

/// Enumera un directorio sin seguir enlaces y a demanda, para que el
/// recorrido deje de pedir entradas al agotar su presupuesto. Las pruebas lo
/// sustituyen para provocar fallos que el sistema no reproduce a pedido.
typedef DirectoryLister =
    Stream<FileSystemEntity> Function(Directory directory);

Stream<FileSystemEntity> listWithoutFollowing(Directory directory) =>
    directory.list(followLinks: false);
