import 'dart:io';

import 'package:cli/src/context/secure_context_store.dart';

/// Un dueño de lease en otro proceso. Uso: `<raíz> context|directory`.
/// Abre el almacén en la raíz, toma el recurso, escribe «held» y espera a
/// que lo terminen: nunca suelta el lease por sí mismo.
Future<void> main(List<String> args) async {
  final store = await SecureContextStore.open(Directory(args[0]));
  final resource = args[1] == 'directory'
      ? store.directoryLock()
      : store.contextLock();
  try {
    await store.acquirePublication([resource]);
    stdout.writeln('held');
  } on ContextStoreFailure catch (failure) {
    stdout.writeln('failed ${failure.code}');
  }
  await stdout.flush();
  await stdin.drain<void>();
}
