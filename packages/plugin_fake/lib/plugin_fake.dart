/// `plugin_fake` — los puertos del plugin que ya tienen contrato, para
/// pruebas. **Hoy dos de veintitrés**, y los demás llegan con su fase.
///
/// **No es un atajo: es la segunda implementación viva.** Mientras un puerto
/// tenga una sola, no es una abstracción — es una indirección que todavía no
/// se contradijo. El intento anterior tenía quince adaptadores vacíos.
///
/// Lo que este paquete NO hace es adivinar. Cada fake se **configura** con lo
/// que debe responder; ninguno reimplementa la lógica del real, porque un fake
/// que la copia deja de ser un segundo punto de vista y pasa a ser el mismo
/// error escrito dos veces.
library;

export 'src/politica_de_artefactos.dart';
export 'src/topologia.dart';
