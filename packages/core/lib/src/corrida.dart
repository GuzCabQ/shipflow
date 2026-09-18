/// El desenlace de una corrida de `ship`: qué pasó con el trabajo local y con
/// el efecto remoto, como **un solo tipo cerrado**.
///
/// **Por qué un tipo y no una conjunción de banderas.** La versión anterior del
/// diseño tenía una tabla que no era función: sus causas se solapaban —una
/// corrida sin confirmar puede además traer un secreto, y el arnés roto
/// coincidía con dos códigos a la vez— y admitía combinaciones que no
/// significan nada, como un pull request abierto sobre una corrida donde el
/// arnés se rompió.
library;

import 'desenlace.dart';

/// Los estados desde los que **se puede publicar**.
///
/// `errorInterno` no está, y esa ausencia es el mecanismo: sin él en el tipo,
/// una publicación sobre una corrida donde el arnés se rompió deja de ser
/// escribible. No hay que acordarse de comprobarlo.
enum EstadoPublicable {
  verde,
  rojo,
  noConcluyente;

  /// El publicable que le corresponde a un estado de corrida, o nulo si ese
  /// estado no autoriza publicar nada.
  ///
  /// **Devuelve nulo en vez de lanzar** porque «no se puede publicar» es un
  /// hecho del dominio que el llamador tiene que poder ramificar, no un error
  /// de programación.
  static EstadoPublicable? desde(EstadoDeCorrida estado) => switch (estado) {
    EstadoDeCorrida.verde => EstadoPublicable.verde,
    EstadoDeCorrida.rojo => EstadoPublicable.rojo,
    EstadoDeCorrida.noConcluyente => EstadoPublicable.noConcluyente,
    EstadoDeCorrida.errorInterno => null,
  };
}

/// Por qué una corrida no intentó publicar.
///
/// **Son cuatro y `errorInterno` no es una de ellas**: es un ESTADO, y entra
/// por [verificationGate]. Ver el ruling del plan de esta rebanada. Con cinco,
/// la fila «gate con errorInterno» de la tabla de códigos quedaría
/// inalcanzable, y una fila que no se puede producir se lee como cobertura de
/// un caso que no existe.
enum CausaDeNoIntento {
  /// El detector encontró un secreto en el diff de la rebanada.
  secretDetected,

  /// La compuerta por estado no autorizó: rojo o no concluyente sin
  /// `--allow-incomplete`, o el arnés roto, que no se autoriza con nada.
  verificationGate,

  /// Falta `--yes`. Sin él la corrida se comporta como una previsualización.
  confirmationMissing,

  /// `--dry-run`: no se pidió efecto ninguno.
  previewOnly,
}
