import 'package:cli/src/context/native/posix_api.dart';

/// Dónde falla el close de un descriptor del lease: después del cierre real
/// (el descriptor queda libre) o antes (queda abierto y lo cierra la prueba).
enum LeaseCloseFailure { afterClosing, beforeClosing }

/// Las llamadas POSIX reales del almacén, anotadas en [events], con fallos
/// inyectados donde se pidan:
/// - [unlockFails]: el unlock del lease suelta de verdad y después lanza;
/// - [closeFails]: el close de un descriptor del lease, según su modo;
/// - [fsyncAfterRename]: EIO en el fsync del directorio justo después del
///   rename de `assessment.json` (un fallo del trabajo ya publicado);
/// - [readWhileLocked]: lanza al abrir para leer con el lock tomado (un
///   fallo del trabajo antes de publicar).
final class ReleasePosix extends NativePosix {
  ReleasePosix(
    this.events, {
    this.unlockFails,
    this.closeFails,
    this.fsyncAfterRename = false,
    this.readWhileLocked,
  }) : super(currentPosixAbi());

  static const eio = PosixError(PosixErrorKind.other, 5);

  final List<String> events;
  final (Object, StackTrace)? unlockFails;
  final (LeaseCloseFailure, Object, StackTrace)? closeFails;
  final bool fsyncAfterRename;
  final (Object, StackTrace)? readWhileLocked;

  /// Descriptores del lease que siguen abiertos porque su close falló antes
  /// de cerrar: la limpieza de la prueba los cierra aparte.
  final leaked = <int>[];
  final _locked = <int>{};
  int? _renamedDir;

  bool get _holdingLock => _locked.isNotEmpty;

  @override
  bool tryLock(int fd) {
    final taken = super.tryLock(fd);
    if (taken) {
      _locked.add(fd);
      events.add('lease.lock');
    }
    return taken;
  }

  @override
  void unlock(int fd) {
    super.unlock(fd);
    events.add('lease.unlock');
    if (unlockFails case (final e, final t)) Error.throwWithStackTrace(e, t);
  }

  @override
  void close(int fd) {
    if (!_locked.remove(fd)) return super.close(fd);
    if (closeFails case (LeaseCloseFailure.beforeClosing, final e, final t)) {
      leaked.add(fd);
      events.add('lease.close.fail');
      Error.throwWithStackTrace(e, t);
    }
    super.close(fd);
    events.add('lease.close');
    if (closeFails case (LeaseCloseFailure.afterClosing, final e, final t)) {
      Error.throwWithStackTrace(e, t);
    }
  }

  @override
  void renameat(int fromDir, String from, int toDir, String to) {
    super.renameat(fromDir, from, toDir, to);
    events.add('rename $to');
    if (to == 'assessment.json') _renamedDir = toDir;
  }

  @override
  void unlinkat(int dirFd, String name) {
    super.unlinkat(dirFd, name);
    events.add('unlink $name');
  }

  @override
  void fsync(int fd) {
    if (fsyncAfterRename && fd == _renamedDir) {
      _renamedDir = null;
      events.add('fsync.fail');
      throw eio;
    }
    super.fsync(fd);
  }

  @override
  int openRead(int dirFd, String name) {
    if (readWhileLocked case (final e, final t) when _holdingLock) {
      events.add('read.fail $name');
      Error.throwWithStackTrace(e, t);
    }
    return super.openRead(dirFd, name);
  }

  /// Cierra lo que dejó abierto un close fallido antes de cerrar.
  void closeLeaked() {
    for (final fd in leaked) {
      super.close(fd);
    }
    leaked.clear();
  }
}

/// Un fallo con una traza propia, para reconocerlo donde llegue.
(Object, StackTrace) injected(Object error, String trace) =>
    (error, StackTrace.fromString(trace));
