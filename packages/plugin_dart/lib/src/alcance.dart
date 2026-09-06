/// El observador de alcance de este stack.
///
/// Es lo que vivía dentro de `PasoDeCascada` como `_mirar` y `separar`. Salió
/// de ahí por una razón de autoridad y no de orden: mientras el paso decidiera
/// qué era suyo, decidía su propia exención.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;

/// El sufijo de los archivos que las herramientas de este stack leen.
const sufijoDeFuente = '.dart';

class ObservadorDeAlcanceDart implements ScopeObserver {
  final String directorio;

  const ObservadorDeAlcanceDart({required this.directorio});

  @override
  Future<ScopeObservation> observe(List<String> requested) async {
    final observados = <ObservedSubject>[];
    final noObservados = <UnobservedSubject>[];

    // **Defensiva, no una propiedad que hoy se pueda comprobar.** Este método
    // no tiene ningún `await`: corre de punta a punta antes de que el
    // llamador recupere el control, así que copiar `requested` o no copiarlo
    // da exactamente el mismo resultado, y ninguna prueba puede distinguir
    // las dos versiones —lo confirmaron 350 pruebas en verde con esta copia
    // revertida—. La copia es contra el día en que este método gane una
    // espera real (una lectura async del árbol, por ejemplo): recién ahí el
    // llamador podría mutar `requested` mientras la observación sigue en
    // curso, y lo que se recorre dejaría de coincidir con lo que se le pasa a
    // `ScopeObservation`. Se usa la MISMA copia en las dos partes para que,
    // si ese día llega, el código ya diga lo que promete.
    final pedido = List<String>.unmodifiable(requested);
    for (final sujeto in pedido) {
      final r = _mirar(sujeto);
      if (r.causa != null) {
        noObservados.add(UnobservedSubject(subject: sujeto, cause: r.causa!));
      } else {
        observados.add(ObservedSubject(
          subject: sujeto,
          ofStack: r.archivos > 0,
          files: r.archivos,
          reason: r.archivos > 0 ? null : r.motivo,
        ));
      }
    }

    return ScopeObservation(
      requested: pedido,
      observed: observados,
      unobserved: noObservados,
      observedAt: DateTime.now().toUtc(),
    );
  }

  /// Cuántos archivos de fuente hay bajo un sujeto; o por qué no es del stack;
  /// o por qué no se pudo establecer.
  ///
  /// **Los componentes ocultos no se cuentan al recorrer un directorio**, y
  /// eso está medido: la herramienta salta todo lo que cuelga de una carpeta
  /// que empieza con punto. Un sujeto nombrado explícitamente sí se procesa
  /// aunque sea oculto, también medido, y por eso la regla se aplica a lo que
  /// hay debajo del sujeto y no al sujeto.
  ({int archivos, String? motivo, String? causa}) _mirar(String pedido) {
    final absoluto =
        rutas.isAbsolute(pedido) ? pedido : rutas.join(directorio, pedido);
    try {
      if (File(absoluto).existsSync()) {
        return absoluto.endsWith(sufijoDeFuente)
            ? (archivos: 1, motivo: null, causa: null)
            : (
                archivos: 0,
                motivo: 'no es un archivo de fuente de este stack',
                causa: null,
              );
      }
      final carpeta = Directory(absoluto);
      if (!carpeta.existsSync()) {
        return (archivos: 0, motivo: null, causa: 'no existe en el árbol');
      }
      final cuantos = carpeta
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith(sufijoDeFuente))
          .where((f) => !rutas
              .split(rutas.relative(f.path, from: absoluto))
              .any((parte) => parte.startsWith('.')))
          .length;
      return cuantos == 0
          ? (
              archivos: 0,
              motivo: 'no contiene ningún archivo de fuente',
              causa: null,
            )
          : (archivos: cuantos, motivo: null, causa: null);
    } on FileSystemException catch (e) {
      // **No poder mirar es un dato, no una excepción que se escapa.** Se
      // atrapa esta familia y no `Object`: un error de programación tiene que
      // seguir subiendo.
      return (
        archivos: 0,
        motivo: null,
        causa: 'no se pudo mirar: ${e.osError?.message ?? e.message}',
      );
    }
  }
}
