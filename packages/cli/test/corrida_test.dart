/// [RegistroDeCorridas]: temporal + `rename`, y lo que la lectura no hace.
///
/// El escritor deja aparecer el nombre final con el contenido entero o no lo
/// deja aparecer. No hay lectura parcial que probar porque no existe: lo que
/// hay para probar es que un temporal huérfano no se confunde con un
/// documento, y que la ausencia de documento es un hecho legible, no un
/// error.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;
import 'package:test/test.dart';

PullRequestDraft _draftDePrueba() => PullRequestDraft(
  runId: 'corrida-1',
  branch: 'rama',
  base: 'develop',
  artefacto: ArtefactoDeRevision(
    superficie: SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: const [],
      estado: EstadoDeCorrida.verde,
    ),
    candidato: CandidateIdentity(
      contentRevision: 'arbol-1',
      baseRevision: 'base-1',
    ),
    intent: 'sostener el arnés',
    plan: null,
    sinPlanPorque: 'no hay elementos de trabajo',
    alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
  ),
);

DocumentoDeCorrida documentoDePrueba() =>
    DocumentoDeCorrida.preparado(revision: 'a' * 40, draft: _draftDePrueba());

void main() {
  late Directory temporal;

  setUp(() => temporal = Directory.systemTemp.createTempSync('registro_'));
  tearDown(() => temporal.deleteSync(recursive: true));

  test('lo escrito se vuelve a leer igual', () async {
    final registro = RegistroDeCorridas(raiz: temporal.path);
    final doc = documentoDePrueba();
    await registro.escribir('r-1', doc);
    expect((await registro.leer('r-1'))!.toJson(), doc.toJson());
  });

  test('una corrida que no existe devuelve nulo, no lanza', () async {
    // «No hay documento» es un hecho que la recuperación tiene que poder
    // ramificar: significa que el proceso murió antes de `prepared`, y lo
    // único que quedó es un objeto inalcanzable que el `gc` recoge.
    final registro = RegistroDeCorridas(raiz: temporal.path);
    expect(await registro.leer('nunca-existio'), isNull);
  });

  test('un temporal huérfano NO se lee como documento', () async {
    // El escritor usa temporal + `rename` para que nadie lea a medias. Si el
    // proceso muere entre los dos, el temporal queda; leerlo sería leer un
    // documento a medio escribir.
    final registro = RegistroDeCorridas(raiz: temporal.path);
    await registro.escribir('r-2', documentoDePrueba());
    final dir = Directory(rutas.join(temporal.path, 'runs'));
    final huerfano = File(rutas.join(dir.path, 'r-3.json.tmp'));
    await huerfano.writeAsString('{"formatVersion":1,"estado":"prepared"');
    expect(await registro.leer('r-3'), isNull);
    expect(await huerfano.exists(), isTrue, reason: 'no se borra a escondidas');
  });
}
