import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'linux_api.dart';
import 'macos_api.dart';
import 'posix_bindings.dart';

/// Por qué falló una llamada POSIX, con los números de su plataforma ya
/// traducidos.
enum PosixErrorKind {
  notFound,
  exists,
  notDirectory,
  isDirectory,
  loop,
  wouldBlock,
  accessDenied,
  interrupted,
  unsupported,
  other,
}

final class PosixError implements Exception {
  const PosixError(this.kind, this.errno);

  final PosixErrorKind kind;
  final int errno;

  @override
  String toString() => 'PosixError(${kind.name}, $errno)';
}

enum NativeFileType { regular, directory, link, other }

/// Lo que un `stat` dice de una entrada, sin seguir enlaces.
typedef NativeStat = ({
  NativeFileType type,
  int size,
  int device,
  int inode,
  int permissions,
});

/// Las constantes y el layout de `struct stat` de una plataforma. Se
/// comprueban en pruebas nativas de cada una, no se deducen de otra.
abstract interface class PosixAbi {
  String get name;
  String get errnoSymbol;
  int get readOnly;
  int get writeOnly;
  int get readWrite;
  int get create;
  int get exclusive;
  int get nonBlocking;
  int get directory;
  int get noFollow;
  int get closeOnExec;
  int get atCurrentDirectory;
  int get atSymlinkNoFollow;
  int get atRemoveDirectory;

  /// El tipo, tamaño, dispositivo e inodo de un `struct stat` en [buffer].
  NativeStat readStat(Uint8List buffer);
  PosixErrorKind kindOf(int errno);
}

/// El ABI de esta plataforma, o [PosixErrorKind.unsupported] fuera del
/// corte: Linux x64 y macOS ARM64.
PosixAbi currentPosixAbi() => switch (Abi.current()) {
  Abi.macosArm64 => const MacosArm64Abi(),
  Abi.linuxX64 => const LinuxX64Abi(),
  _ => throw const PosixError(PosixErrorKind.unsupported, 0),
};

const _lockExclusive = 2;
const _lockNonBlocking = 4;
const _unlock = 8;
const _statBytes = 256;
const _chunk = 65536;

/// Llamadas POSIX por descriptor, sin shell ni binario auxiliar. Cada una
/// lanza [PosixError] y lee errno enseguida, en una llamada hoja.
///
/// No es final: las pruebas la extienden para inyectar fallos con el mismo
/// contrato que el adapter real.
class NativePosix {
  NativePosix(this.abi) : _c = PosixBindings(abi.errnoSymbol) {
    try {
      _c.resolveAll();
    } on ArgumentError {
      throw const PosixError(PosixErrorKind.unsupported, 0);
    }
  }

  final PosixAbi abi;
  final PosixBindings _c;

  int get _directoryFlags =>
      abi.readOnly | abi.directory | abi.noFollow | abi.closeOnExec;

  /// Un directorio absoluto ya canónico, como ancla de todo lo demás.
  int openRoot(String absolutePath) => _named(
    absolutePath,
    (name) => _c.openAt(
      abi.atCurrentDirectory,
      name,
      abi.readOnly | abi.directory | abi.closeOnExec,
      0,
    ),
  );

  /// Un subdirectorio de [dirFd], sin seguir un enlace.
  int openDirectory(int dirFd, String name) =>
      _named(name, (n) => _c.openAt(dirFd, n, _directoryFlags, 0));

  /// Para leer, sin seguir enlaces ni esperar a un FIFO.
  int openRead(int dirFd, String name) => _named(
    name,
    (n) => _c.openAt(
      dirFd,
      n,
      abi.readOnly | abi.noFollow | abi.nonBlocking | abi.closeOnExec,
      0,
    ),
  );

  /// Un archivo nuevo que no existía, con [mode].
  int createExclusive(int dirFd, String name, int mode) => _named(
    name,
    (n) => _c.openAt(
      dirFd,
      n,
      abi.writeOnly |
          abi.create |
          abi.exclusive |
          abi.noFollow |
          abi.closeOnExec,
      mode,
    ),
  );

  /// Un archivo de lock, creado si falta y nunca truncado.
  int openLockFile(int dirFd, String name) => _named(
    name,
    (n) => _c.openAt(
      dirFd,
      n,
      abi.readWrite |
          abi.create |
          abi.noFollow |
          abi.nonBlocking |
          abi.closeOnExec,
      420,
    ),
  );

  void close(int fd) => _check(_c.close(fd));

  /// Fija los permisos de [fd] sin depender del umask.
  void fchmod(int fd, int mode) => _check(_c.fchmod(fd, mode));

  void fsync(int fd) => _retrying(() => _c.fsync(fd));

  NativeStat fstat(int fd) =>
      _withStat((buffer) => _check(_c.fstat(fd, buffer)));

  /// La entrada [name] de [dirFd] sin seguirla, o null si no existe.
  NativeStat? lstatAt(int dirFd, String name) {
    try {
      return _withStat(
        (buffer) => _named(
          name,
          (n) => _c.fstatAt(dirFd, n, buffer, abi.atSymlinkNoFollow),
        ),
      );
    } on PosixError catch (e) {
      if (e.kind == PosixErrorKind.notFound) return null;
      rethrow;
    }
  }

  void mkdirat(int dirFd, String name, int mode) =>
      _named(name, (n) => _c.mkdirAt(dirFd, n, mode));

  void renameat(int fromDir, String from, int toDir, String to) =>
      _named(from, (f) => _named(to, (t) => _c.renameAt(fromDir, f, toDir, t)));

  void unlinkat(int dirFd, String name) =>
      _named(name, (n) => _c.unlinkAt(dirFd, n, 0));

  /// Retira el directorio vacío [name]; uno con contenido no se toca.
  void rmdirat(int dirFd, String name) =>
      _named(name, (n) => _c.unlinkAt(dirFd, n, abi.atRemoveDirectory));

  /// Toma el lock exclusivo sin esperar; false si otro lo tiene.
  bool tryLock(int fd) {
    try {
      _retrying(() => _c.flock(fd, _lockExclusive | _lockNonBlocking));
      return true;
    } on PosixError catch (e) {
      if (e.kind == PosixErrorKind.wouldBlock) return false;
      rethrow;
    }
  }

  void unlock(int fd) => _check(_c.flock(fd, _unlock));

  /// Hasta [max] bytes, o hasta el final si es antes.
  List<int> read(int fd, int max) {
    final buffer = _c.malloc(_chunk);
    final bytes = BytesBuilder(copy: false);
    try {
      while (bytes.length < max) {
        final want = max - bytes.length < _chunk ? max - bytes.length : _chunk;
        final got = _retrying(() => _c.read(fd, buffer, want));
        if (got == 0) break;
        bytes.add(Uint8List.fromList(buffer.asTypedList(got)));
      }
      return bytes.takeBytes();
    } finally {
      _c.free(buffer);
    }
  }

  void writeAll(int fd, List<int> bytes) {
    final buffer = _c.malloc(bytes.isEmpty ? 1 : bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      var done = 0;
      while (done < bytes.length) {
        done += _retrying(
          () => _c.write(fd, buffer + done, bytes.length - done),
        );
      }
    } finally {
      _c.free(buffer);
    }
  }

  NativeStat _withStat(void Function(Pointer<Uint8> buffer) call) {
    final buffer = _c.malloc(_statBytes);
    try {
      call(buffer);
      return abi.readStat(Uint8List.fromList(buffer.asTypedList(_statBytes)));
    } finally {
      _c.free(buffer);
    }
  }

  /// [call] con [name] como cadena C, liberada al terminar.
  int _named(String name, int Function(Pointer<Uint8> name) call) {
    final bytes = _cString(name);
    final pointer = _c.malloc(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return _check(call(pointer));
    } finally {
      _c.free(pointer);
    }
  }

  int _retrying(int Function() call) {
    while (true) {
      try {
        return _check(call());
      } on PosixError catch (e) {
        if (e.kind != PosixErrorKind.interrupted) rethrow;
      }
    }
  }

  int _check(int result) {
    if (result >= 0) return result;
    final errno = _c.errno().value;
    throw PosixError(abi.kindOf(errno), errno);
  }
}

/// [name] en UTF-8 con su NUL final. Un NUL interior no llega al sistema.
List<int> _cString(String name) {
  if (name.contains('\u0000')) {
    throw const PosixError(PosixErrorKind.other, 0);
  }
  return [...utf8.encode(name), 0];
}
