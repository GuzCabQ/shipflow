import 'dart:typed_data';

import 'macos_api.dart';
import 'posix_api.dart';

/// Linux en x86-64: constantes de glibc y el `struct stat` del kernel para
/// esa arquitectura. Las pruebas nativas lo contrastan con `stat -c`.
final class LinuxX64Abi implements PosixAbi {
  const LinuxX64Abi();

  @override
  String get name => 'linux-x64';
  @override
  String get errnoSymbol => '__errno_location';
  @override
  int get readOnly => 0x0000;
  @override
  int get writeOnly => 0x0001;
  @override
  int get readWrite => 0x0002;
  @override
  int get create => 0x0040;
  @override
  int get exclusive => 0x0080;
  @override
  int get nonBlocking => 0x0800;
  @override
  int get directory => 0x10000;
  @override
  int get noFollow => 0x20000;
  @override
  int get closeOnExec => 0x80000;
  @override
  int get atCurrentDirectory => -100;
  @override
  int get atRemoveDirectory => 0x0200;
  @override
  int get atSymlinkNoFollow => 0x0100;

  /// `st_dev` uint64 en 0, `st_ino` uint64 en 8, `st_mode` uint32 en 24 y
  /// `st_size` int64 en 48.
  @override
  NativeStat readStat(Uint8List buffer) {
    final data = ByteData.sublistView(buffer);
    return (
      type: fileTypeOf(data.getUint32(24, Endian.little)),
      permissions: data.getUint32(24, Endian.little) & 4095,
      size: data.getInt64(48, Endian.little),
      device: data.getUint64(0, Endian.little),
      inode: data.getUint64(8, Endian.little),
    );
  }

  @override
  PosixErrorKind kindOf(int errno) => switch (errno) {
    2 => PosixErrorKind.notFound,
    4 => PosixErrorKind.interrupted,
    13 || 1 => PosixErrorKind.accessDenied,
    17 => PosixErrorKind.exists,
    20 => PosixErrorKind.notDirectory,
    21 => PosixErrorKind.isDirectory,
    11 => PosixErrorKind.wouldBlock,
    40 => PosixErrorKind.loop,
    _ => PosixErrorKind.other,
  };
}
