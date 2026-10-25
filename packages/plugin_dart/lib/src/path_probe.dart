import 'dart:io';

/// ENOENT y ENOTDIR, iguales en macOS y Linux: no existe, o un tramo
/// anterior es un archivo y nada puede existir debajo.
const _absentErrors = {2, 20};

/// Si [path] no existe de verdad. Un tramo que no se puede mirar, por
/// permisos u otro motivo, no cuenta como inexistente.
bool isAbsentPath(String path) {
  try {
    File(path).resolveSymbolicLinksSync();
    return false;
  } on FileSystemException catch (error) {
    return _absentErrors.contains(error.osError?.errorCode);
  }
}
