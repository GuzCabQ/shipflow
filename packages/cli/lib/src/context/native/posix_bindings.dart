import 'dart:ffi';

typedef OpenAtNative =
    Int32 Function(Int32, Pointer<Uint8>, Int32, VarArgs<(Uint32,)>);
typedef OpenAt = int Function(int, Pointer<Uint8>, int, int);
typedef FdCall = int Function(int);
typedef IoCall = int Function(int, Pointer<Uint8>, int);
typedef IoNative = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef StatCall = int Function(int, Pointer<Uint8>);
typedef StatAt = int Function(int, Pointer<Uint8>, Pointer<Uint8>, int);
typedef StatAtNative =
    Int32 Function(Int32, Pointer<Uint8>, Pointer<Uint8>, Int32);
typedef PathCall = int Function(int, Pointer<Uint8>, int);
typedef RenameAt = int Function(int, Pointer<Uint8>, int, Pointer<Uint8>);
typedef RenameAtNative =
    Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Uint8>);

/// Las funciones de libc que usa el almacén, todas llamadas hoja: no
/// vuelven a Dart, así que errno se lee intacto en la llamada siguiente.
/// `openat` es variádica: su modo viaja como `VarArgs`, que en ARM64 de
/// Apple va por la pila y no por registro.
final class PosixBindings {
  PosixBindings(this.errnoSymbol);

  final String errnoSymbol;
  final _libc = DynamicLibrary.process();

  late final OpenAt openAt = _libc.lookupFunction<OpenAtNative, OpenAt>(
    'openat',
    isLeaf: true,
  );
  late final FdCall close = _fd('close');
  late final FdCall fsync = _fd('fsync');
  late final IoCall read = _libc.lookupFunction<IoNative, IoCall>(
    'read',
    isLeaf: true,
  );
  late final IoCall write = _libc.lookupFunction<IoNative, IoCall>(
    'write',
    isLeaf: true,
  );
  late final StatCall fstat = _libc
      .lookupFunction<Int32 Function(Int32, Pointer<Uint8>), StatCall>(
        'fstat',
        isLeaf: true,
      );
  late final StatAt fstatAt = _libc.lookupFunction<StatAtNative, StatAt>(
    'fstatat',
    isLeaf: true,
  );
  late final PathCall mkdirAt = _path('mkdirat');
  late final PathCall unlinkAt = _path('unlinkat');
  late final RenameAt renameAt = _libc.lookupFunction<RenameAtNative, RenameAt>(
    'renameat',
    isLeaf: true,
  );
  late final int Function(int, int) flock = _libc
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
        isLeaf: true,
      );
  late final Pointer<Int32> Function() errno = _libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        errnoSymbol,
        isLeaf: true,
      );
  late final Pointer<Uint8> Function(int) malloc = _libc
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('malloc', isLeaf: true);
  late final void Function(Pointer<Uint8>) free = _libc
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free', isLeaf: true);

  FdCall _fd(String name) =>
      _libc.lookupFunction<Int32 Function(Int32), FdCall>(name, isLeaf: true);

  PathCall _path(String name) => _libc
      .lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Uint32), PathCall>(
        name,
        isLeaf: true,
      );
}
