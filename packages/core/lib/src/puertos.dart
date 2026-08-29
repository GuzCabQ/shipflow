/// Los puertos. **Solo interfaces: ninguna implementación vive acá.**
///
/// Todas las flechas apuntan hacia adentro. `core` no conoce ningún stack,
/// ningún CLI y ningún sistema de tickets; cuando necesita algo de ellos,
/// declara un puerto y espera que alguien de afuera lo satisfaga.
///
/// **Ningún puerto de este archivo tiene implementación todavía**, y eso está
/// declarado en `arquitectura.json` bajo `puertos-sin-implementacion`, con la
/// fase en que cada uno aparece. Sin esa declaración, «no hay implementación»
/// sería indistinguible de «se nos olvidó».
library;

import 'entidades.dart';
import 'credencial.dart';
import 'observacion.dart';
import 'regla.dart';
import 'valores.dart';

// --- Entrada -----------------------------------------------------------

/// De dónde salen los [WorkItem]. Solo lectura.
abstract interface class WorkItemSource {
  Future<WorkItem> fetch(String id);
  Future<List<WorkItem>> list();
}

/// Cómo se le contesta a la fuente. **Separado de [WorkItemSource] a
/// propósito**: leer un ticket no debería exigir permiso de escritura sobre él.
abstract interface class WorkItemFeedback {
  Future<void> comment(String workItemId, String body);
  Future<void> transition(String workItemId, String state);
}

/// Contexto adicional del que el trabajo depende y que no está en el código.
abstract interface class ContextSource {
  Future<List<QuotedText>> gather(WorkItem item);
}

// --- Stack · las implementa el plugin del lenguaje ---------------------

/// La topología del proyecto que se está trabajando.
abstract interface class ProjectTopology {
  Future<List<Package>> packages();
}

/// Qué artefactos produce y consume el stack, y cuáles no se tocan.
abstract interface class ArtifactPolicy {
  bool isGenerated(String path);
  bool isEditable(String path);
}

/// Un paso de la cascada. **Devuelve su testigo junto con sus diagnósticos**:
/// un [Verifier] que devolviera solo diagnósticos no podría distinguir «limpio»
/// de «no corrí» (INV-2).
abstract interface class Verifier {
  String get id;
  Future<VerificationOutcome> run(List<String> subjects);
}

/// Traduce la salida cruda de una herramienta a [Diagnostic] normalizados.
abstract interface class DiagnosticNormalizer {
  List<Diagnostic> normalize(QuotedText rawOutput);
}

/// Sabe cuándo hay que regenerar código y cómo.
abstract interface class CodegenTrigger {
  bool needsRun(List<String> changedFiles);
  Future<VerificationOutcome> run();
}

/// Resuelve el grafo de dependencias del proyecto trabajado.
abstract interface class DependencyResolver {
  Future<Map<String, List<String>>> graph();
}

/// El catálogo de clases de cambio. **Lo declara el plugin**: `core` solo sabe
/// que existen y que seleccionan estrategia.
abstract interface class ChangeClassCatalog {
  List<ChangeClass> all();
  ChangeClass? byId(String id);
}

// --- Agente · las implementa el adapter del CLI ajeno ------------------

/// Ejecuta el CLI agéntico del usuario en modo headless y normaliza sus
/// eventos a [Trace].
///
/// **Reemplaza al `ModelGateway` de la v0.1**: no hablamos con una API de
/// modelo, hablamos con el CLI que el usuario ya tiene instalado.
abstract interface class AgentRunner {
  Future<Trace> run(Plan plan, {required Duration budget});
}

/// Instala y retira los ganchos de la capa de ganchos.
///
/// **Toda instalación declara sus evasiones**: [Rule] rechaza en su
/// constructor cualquier regla de esa capa que no las traiga (INV-3).
abstract interface class HookInstaller {
  Future<void> install(List<Rule> rules);
  Future<void> uninstall();

  /// Qué hay instalado de verdad, leído del sistema y no de lo que creemos
  /// haber escrito.
  Future<List<String>> installed();
}

/// Sabe dónde van los archivos de la capa de prosa proyectada en cada CLI.
abstract interface class ContextProjector {
  Future<void> project(List<Rule> rules);
  Future<List<String>> targets();
}

// --- Salida e infraestructura ------------------------------------------

/// Por donde salen los cambios al mundo.
abstract interface class ChangeSink {
  Future<void> apply(Plan plan);
}

/// El árbol de trabajo: leer, escribir, y saber si está sucio.
abstract interface class Workspace {
  Future<String> read(String path);
  Future<void> write(String path, String contents);
  Future<bool> isDirty();
  Future<String> revision();
}

/// Por donde salen las trazas.
abstract interface class TraceSink {
  Future<void> emit(Trace trace);
}

/// Guarda y entrega credenciales. **Devuelve [Credential], nunca cadenas**:
/// el tipo es lo que impide que el secreto termine en una traza (INV-5).
abstract interface class CredentialStore {
  Future<Credential?> read(String key);
  Future<void> write(String key, Credential value);
  Future<void> delete(String key);
}

// --- Sensores inferenciales · anotan, nunca bloquean -------------------

/// Mira un diff y anota. Devuelve [Finding], que **no tiene severidad**: por
/// eso no puede detener nada (ADR-006).
abstract interface class ReviewSensor {
  Future<List<Finding>> review(List<String> changedFiles);

  /// Qué miró y qué NO miró, con el motivo. Es el hueco `RS-1` del sensor real
  /// analizado: sin esto, un reporte sin la sección de seguridad se lee como
  /// «seguridad ok».
  Future<Witness> attestation();
}

/// Audita las trazas en busca de patrones que ningún check determinista ve.
abstract interface class TraceAuditor {
  Future<List<Finding>> audit(Trace trace);
}

// --- Aportados por el plugin, además de los de stack -------------------

/// Prosa y skills del ecosistema: el cuadrante **guía inferencial** (`D-010`).
abstract interface class RuleContributor {
  List<Rule> contribute();
}

/// Qué mirar en un diff de este lenguaje: el cuadrante **sensor inferencial**
/// (`D-011`).
abstract interface class ReviewCriteria {
  /// Cada criterio con su id estable, para telemetría y promoción.
  Map<String, QuotedText> criteria();

  /// Lo que ya imponen los lints y el sensor **no** debe comentar (`RS-5`).
  List<String> coveredByLints();
}

/// Vías alternativas conocidas por control (`D-012`).
///
/// Es un puerto y no documentación por una razón operativa: sin evasiones el
/// gancho no se instala, así que esto tiene que ser consultable en tiempo de
/// instalación, no leíble por una persona.
abstract interface class EvasionCatalog {
  List<String> evasionsFor(String controlId);
}

/// El catálogo de formas a las que se puede traducir un criterio de aceptación
/// (ADR-016, `D-013`). Es lo que INV-1 exige que exista antes de admitir un
/// [WorkItem].
abstract interface class AssertionForms {
  List<String> forms();
  bool supports(String formId);
}
