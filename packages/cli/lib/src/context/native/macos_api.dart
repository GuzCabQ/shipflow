import 'dart:typed_data';

import 'posix_api.dart';

/// macOS en ARM64: constantes de `<fcntl.h>`, `<errno.h>` y el `struct stat`
/// de inodos de 64 bits. Las pruebas nativas lo contrastan con `stat -f`.
final class MacosArm64Abi implements PosixAbi {
  const MacosArm64Abi();

  @override
  String get name => 'macos-arm64';
  @override
  String get errnoSymbol => '__error';
  @override
  int get readOnly => 0x0000;
  @override
  int get writeOnly => 0x0001;
  @override
  int get readWrite => 0x0002;
  @override
  int get nonBlocking => 0x0004;
  @override
  int get create => 0x0200;
  @override
  int get exclusive => 0x0800;
  @override
  int get noFollow => 0x0100;
  @override
  int get directory => 0x100000;
  @override
  int get closeOnExec => 0x1000000;
  @override
  int get atCurrentDirectory => -2;
  @override
  int get atRemoveDirectory => 0x0080;
  @override
  int get atSymlinkNoFollow => 0x0020;

  /// `st_dev` int32 en 0, `st_mode` uint16 en 4, `st_ino` uint64 en 8 y
  /// `st_size` int64 en 96.
  @override
  NativeStat readStat(Uint8List buffer) {
    final data = ByteData.sublistView(buffer);
    return (
      type: fileTypeOf(data.getUint16(4, Endian.little)),
      permissions: data.getUint16(4, Endian.little) & 4095,
      size: data.getInt64(96, Endian.little),
      device: data.getInt32(0, Endian.little),
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
    35 => PosixErrorKind.wouldBlock,
    62 => PosixErrorKind.loop,
    _ => PosixErrorKind.other,
  };
}

/// El tipo de entrada según `S_IFMT`, igual en ambas plataformas.
NativeFileType fileTypeOf(int mode) => switch (mode & 0xF000) {
  0x8000 => NativeFileType.regular,
  0x4000 => NativeFileType.directory,
  0xA000 => NativeFileType.link,
  _ => NativeFileType.other,
};
