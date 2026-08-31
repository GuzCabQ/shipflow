/// `orchestration` — el compositor de etapas.
///
/// **Solo ve `core`.** No conoce ningún plugin, ningún CLI agéntico y ningún
/// sistema de tickets, y una regla de arquitectura lo hace cumplir. Por eso la
/// cascada sabe que sus pasos son `Verifier` y nada más.
///
/// Hoy contiene la cascada. Faltan la política de autonomía, los presupuestos
/// y el corte temprano, y su ausencia está declarada donde corresponde.
library;

export 'src/cascada.dart';
