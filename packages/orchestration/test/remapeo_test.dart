/// El remapeo de rutas, y el límite que no cruza: el mensaje de la
/// herramienta no se toca.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

/// Una observación de un único sujeto del stack, solo para tener con qué
/// construir un `ResultadoDeCascada` coherente. Ningún test de este archivo
/// mira el alcance: lo que importa es [Diagnostic.file] y [Diagnostic.message].
ScopeObservation _alcance() => ScopeObservation(
  requested: const ['lib'],
  observed: [ObservedSubject(subject: 'lib', ofStack: true, files: 1)],
  unobserved: const [],
  observedAt: DateTime.utc(2026),
);

Witness _testigo(ScopeObservation alcance) => Witness(
  invocation: 'herramienta',
  subjects: alcance.usable(),
  exitCode: 0,
  omitted: const [],
  finishedAt: DateTime.utc(2026),
);

Diagnostic _diagnostico({
  required String file,
  String ruleId = 'r',
  QuotedText? message,
}) => Diagnostic(
  file: file,
  severity: Severity.reporta,
  ruleId: ruleId,
  message: message ?? const QuotedText('m', source: 'test'),
);

/// Un `ResultadoDeCascada` de un único paso `A`, con [diagnosticos] tal como
/// los produjo.
ResultadoDeCascada _cascadaCon(List<Diagnostic> diagnosticos) {
  final alcance = _alcance();
  return ResultadoDeCascada(
    registrados: [RegisteredStep(id: 'A', expectedScope: alcance.usable())],
    alcance: alcance,
    desenlaces: {
      'A': Executed(witness: _testigo(alcance), diagnostics: diagnosticos),
    },
  );
}

/// Una cascada con un único diagnóstico, sobre el archivo [archivo].
ResultadoDeCascada cascadaConDiagnosticoEn(String archivo) =>
    _cascadaCon([_diagnostico(file: archivo)]);

/// Una cascada con un único diagnóstico cuyo mensaje es [mensaje] — el
/// archivo es irrelevante para lo que este ayudante existe para probar.
ResultadoDeCascada cascadaConMensaje(String mensaje) => _cascadaCon([
  _diagnostico(
    file: 'lib/a.txt',
    message: QuotedText(mensaje, source: 'tool'),
  ),
]);

/// Una cascada con tres diagnósticos, en un orden que la prueba de
/// preservación pueda distinguir de cualquier reordenamiento.
ResultadoDeCascada cascadaConTresDiagnosticos() => _cascadaCon([
  _diagnostico(file: 'lib/a.txt', ruleId: 'r1'),
  _diagnostico(file: '/usr/lib/toolchain/x.txt', ruleId: 'r2'),
  _diagnostico(file: 'lib/b.txt', ruleId: 'r3'),
]);

/// El primer diagnóstico de [cascada], en el orden en que la cascada los
/// produjo.
Diagnostic primerDiagnostico(ResultadoDeCascada cascada) =>
    cascada.diagnosticos.first;

/// Todos los diagnósticos de [cascada], en orden.
List<Diagnostic> diagnosticosDe(ResultadoDeCascada cascada) =>
    cascada.diagnosticos;

void main() {
  test('el archivo del diagnóstico pasa a ser el del usuario', () {
    final remapeado = remapear(
      cascadaConDiagnosticoEn('/tmp/cand-1/lib/a.txt'),
      raizDelCandidato: '/tmp/cand-1',
    );
    expect(primerDiagnostico(remapeado).file, 'lib/a.txt');
  });

  test('el MENSAJE no se toca, aunque mencione la raíz temporal', () {
    // La evidencia se cita, no se reescribe. Una cita adulterada es peor que
    // una ruta rara: el revisor no puede saber qué dijo la herramienta.
    final sucio = cascadaConMensaje('no se pudo leer /tmp/cand-1/lib/a.txt');
    final remapeado = remapear(sucio, raizDelCandidato: '/tmp/cand-1');
    expect(
      primerDiagnostico(remapeado).message.content,
      contains('/tmp/cand-1/lib/a.txt'),
    );
  });

  test('un archivo que NO está bajo la raíz del candidato se deja igual', () {
    // Puede pasar: una herramienta que reporte sobre su propia instalación.
    // Reescribirlo inventaría una ruta del usuario que no existe.
    final remapeado = remapear(
      cascadaConDiagnosticoEn('/usr/lib/toolchain/x.txt'),
      raizDelCandidato: '/tmp/cand-1',
    );
    expect(primerDiagnostico(remapeado).file, '/usr/lib/toolchain/x.txt');
  });

  test('el remapeo no pierde ningún diagnóstico ni cambia su orden', () {
    final antes = cascadaConTresDiagnosticos();
    final despues = remapear(antes, raizDelCandidato: '/tmp/cand-1');
    expect(
      diagnosticosDe(despues).map((d) => d.ruleId).toList(),
      diagnosticosDe(antes).map((d) => d.ruleId).toList(),
    );
  });
}
