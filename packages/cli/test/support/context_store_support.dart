import 'dart:io';

import 'package:cli/src/context/native/posix_api.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:test/test.dart';

Matcher storeFailure(String code) =>
    isA<ContextStoreFailure>().having((f) => f.code, 'code', code);

/// Una raíz canónica y una carpeta hermana «de fuera», ambas temporales.
final class StoreSandbox {
  StoreSandbox._(this.root, this.outside);

  static Future<StoreSandbox> create() async {
    final base = Directory(
      Directory.systemTemp
          .createTempSync('shipflow-store-')
          .resolveSymbolicLinksSync(),
    );
    return StoreSandbox._(
      Directory('${base.path}/raiz')..createSync(),
      Directory('${base.path}/fuera')..createSync(),
    );
  }

  final Directory root;
  final Directory outside;
  final _stores = <SecureContextStore>[];

  String path(String relative) => '${root.path}/$relative';

  Future<SecureContextStore> open({NativePosix? api}) async {
    final store = await SecureContextStore.open(root, api: api);
    _stores.add(store);
    return store;
  }

  Directory directory(String relative) =>
      Directory(path(relative))..createSync(recursive: true);

  File file(String relative, String text) {
    final file = File(path(relative));
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(text);
  }

  File outsideFile(String name, String text) =>
      File('${outside.path}/$name')..writeAsStringSync(text);

  Directory outsideDirectory(String name) =>
      Directory('${outside.path}/$name')..createSync();

  List<String> entriesOf(String relative) => [
    for (final e in Directory(path(relative)).listSync())
      e.path.substring(path(relative).length + 1),
  ]..sort();

  /// Tipo y bytes de cada entrada, sin abrir FIFOs ni seguir enlaces.
  Map<String, String> snapshot() => {
    for (final e in root.listSync(recursive: true, followLinks: false))
      e.path.substring(root.path.length + 1): switch (e) {
        Link() => 'enlace ${e.targetSync()}',
        File()
            when FileSystemEntity.typeSync(e.path, followLinks: false) ==
                FileSystemEntityType.file =>
          'archivo ${e.readAsBytesSync()}',
        Directory() => 'directorio',
        _ => 'otro',
      },
  };

  Future<void> dispose() async {
    for (final store in _stores) {
      await store.close();
    }
    await Process.run('chmod', ['-R', 'u+rwx', root.parent.path]);
    root.parent.deleteSync(recursive: true);
  }
}

/// Una sustitución del destino justo antes del rename: la carrera que una
/// comprobación por nombre no puede cerrar.
final class SwapBeforeRename extends NativePosix {
  SwapBeforeRename(this.swap) : super(currentPosixAbi());

  final void Function() swap;
  var _done = false;

  @override
  void renameat(int fromDir, String from, int toDir, String to) {
    if (!_done) {
      _done = true;
      swap();
    }
    super.renameat(fromDir, from, toDir, to);
  }
}

/// fsync que falla, como un disco que no confirma la escritura.
final class FailingFlush extends NativePosix {
  FailingFlush() : super(currentPosixAbi());

  @override
  void fsync(int fd) => throw const PosixError(PosixErrorKind.other, 5);
}
