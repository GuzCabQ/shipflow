import 'dart:io';
import 'dart:isolate';

/// Los schemas, fixtures y compat V4, copiados byte a byte del paquete
/// técnico. Síncrono: las pruebas por fixture se registran al cargar, y
/// la ruta no depende del directorio desde el que se corre.
String v4Fixtures() {
  final barrel = Isolate.resolvePackageUriSync(
    Uri.parse('package:cli/cli.dart'),
  );
  return '${File.fromUri(barrel!).parent.parent.path}/test/fixtures/v4';
}
