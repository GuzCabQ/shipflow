/// `plugin_dart` — lo que el arnés necesita saber del stack Dart/Flutter.
///
/// **Es el único paquete donde las cadenas `dart`, `flutter` y `pubspec`
/// pueden aparecer**, y una regla de CI lo hace cumplir. Todo lo que el resto
/// del sistema sabe de este ecosistema pasa por acá, detrás de un puerto.
///
/// Los hechos que codifica no se inventaron acá: están declarados en el
/// registro semilla del corpus como `N1-01` a `N1-07`, y cada uno dice qué
/// puerto lo usa.
library;

export 'src/politica_de_artefactos.dart';
export 'src/topologia.dart';
