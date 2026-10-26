@Timeout(Duration(seconds: 60))
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cli/src/context/native/posix_api.dart';
import 'package:test/test.dart';

/// Lo que dice el `stat` del sistema, el testigo independiente del layout.
Future<({int inode, int device, int size, int mode})> systemStat(
  String path,
) async {
  final format = Platform.isMacOS
      ? ['-f', '%i %d %z %p']
      : ['-c', '%i %d %s %f'];
  final result = await Process.run('stat', [...format, path]);
  final [inode, device, size, mode] = (result.stdout as String).trim().split(
    ' ',
  );
  return (
    inode: int.parse(inode),
    device: int.parse(device),
    size: int.parse(size),
    mode: int.parse(mode, radix: Platform.isMacOS ? 8 : 16),
  );
}

void main() {
  late Directory dir;
  late NativePosix posix;
  late int dirFd;

  setUp(() {
    dir = Directory(
      Directory.systemTemp
          .createTempSync('shipflow-abi-')
          .resolveSymbolicLinksSync(),
    );
    posix = NativePosix(currentPosixAbi());
    dirFd = posix.openRoot(dir.path);
  });
  tearDown(() {
    posix.close(dirFd);
    dir.deleteSync(recursive: true);
  });

  test('the ABI is the one of this platform, and no other', () {
    final abi = currentPosixAbi();
    expect(abi.name, switch (Abi.current()) {
      Abi.macosArm64 => 'macos-arm64',
      Abi.linuxX64 => 'linux-x64',
      _ => fail('plataforma fuera del corte: ${Abi.current()}'),
    });
  });

  test('fstat agrees with the system stat on inode, device and size', () async {
    final file = File('${dir.path}/a')..writeAsStringSync('x' * 1234);
    final fd = posix.openRead(dirFd, 'a');
    addTearDown(() => posix.close(fd));
    final native = posix.fstat(fd);
    final system = await systemStat(file.path);
    expect(native.type, NativeFileType.regular);
    expect(native.size, 1234);
    expect(native.size, system.size);
    expect(native.inode, system.inode);
    expect(native.device, system.device);
    expect(native.permissions, system.mode & 4095);
  });

  test('lstatAt names directories, links and absences without following', () {
    Directory('${dir.path}/d').createSync();
    Link('${dir.path}/l').createSync('/');
    expect(posix.lstatAt(dirFd, 'd')!.type, NativeFileType.directory);
    expect(posix.lstatAt(dirFd, 'l')!.type, NativeFileType.link);
    expect(posix.lstatAt(dirFd, 'nada'), isNull);
  });

  test('errno is classified with this platform numbers', () {
    File('${dir.path}/f').writeAsStringSync('');
    Link('${dir.path}/l').createSync('${dir.path}/f');
    expect(
      () => posix.openRead(dirFd, 'l'),
      throwsA(_kind(PosixErrorKind.loop)),
    );
    expect(
      () => posix.openDirectory(dirFd, 'f'),
      throwsA(_kind(PosixErrorKind.notDirectory)),
    );
    expect(
      () => posix.openRead(dirFd, 'nada'),
      throwsA(_kind(PosixErrorKind.notFound)),
    );
    posix.mkdirat(dirFd, 'nuevo', 448);
    expect(
      () => posix.mkdirat(dirFd, 'nuevo', 448),
      throwsA(_kind(PosixErrorKind.exists)),
    );
  });

  test('the creation mode travels as a variadic argument', () async {
    final fd = posix.createExclusive(dirFd, 'modo', 384);
    posix.close(fd);
    expect((await systemStat('${dir.path}/modo')).mode & 511, 384);
    expect(
      () => posix.createExclusive(dirFd, 'modo', 384),
      throwsA(_kind(PosixErrorKind.exists)),
    );
  });

  test('flock is per open description and does not wait', () {
    final first = posix.openLockFile(dirFd, 'lock');
    final second = posix.openLockFile(dirFd, 'lock');
    addTearDown(() {
      posix.close(first);
      posix.close(second);
    });
    expect(posix.tryLock(first), isTrue);
    expect(posix.tryLock(second), isFalse);
    posix.unlock(first);
    expect(posix.tryLock(second), isTrue);
  });

  test('write, fsync and read move whole buffers', () {
    final fd = posix.createExclusive(dirFd, 'datos', 420);
    final bytes = List.generate(200000, (i) => i % 251);
    posix.writeAll(fd, bytes);
    posix.fsync(fd);
    posix.close(fd);
    final again = posix.openRead(dirFd, 'datos');
    addTearDown(() => posix.close(again));
    expect(posix.read(again, 300000), bytes);
  });

  test('M7: a libc without a required symbol is an unsupported platform', () {
    expect(
      () => NativePosix(_MissingSymbol(currentPosixAbi())),
      throwsA(_kind(PosixErrorKind.unsupported)),
    );
  });
}

Matcher _kind(PosixErrorKind kind) =>
    isA<PosixError>().having((e) => e.kind, 'kind', kind);

/// El ABI de esta plataforma con un símbolo de errno que no existe, como un
/// glibc sin las funciones que el almacén necesita.
final class _MissingSymbol implements PosixAbi {
  _MissingSymbol(this.real);

  final PosixAbi real;

  @override
  String get errnoSymbol => 'shipflow_no_existe';
  @override
  String get name => real.name;
  @override
  int get readOnly => real.readOnly;
  @override
  int get writeOnly => real.writeOnly;
  @override
  int get readWrite => real.readWrite;
  @override
  int get create => real.create;
  @override
  int get exclusive => real.exclusive;
  @override
  int get nonBlocking => real.nonBlocking;
  @override
  int get directory => real.directory;
  @override
  int get noFollow => real.noFollow;
  @override
  int get closeOnExec => real.closeOnExec;
  @override
  int get atCurrentDirectory => real.atCurrentDirectory;
  @override
  int get atSymlinkNoFollow => real.atSymlinkNoFollow;
  @override
  int get atRemoveDirectory => real.atRemoveDirectory;
  @override
  NativeStat readStat(Uint8List buffer) => real.readStat(buffer);
  @override
  PosixErrorKind kindOf(int errno) => real.kindOf(errno);
}
