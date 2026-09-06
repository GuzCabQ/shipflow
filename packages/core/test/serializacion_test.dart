/// Ida y vuelta con VALORES, no con nombres de campo.
///
/// El verificador de `tool/analisis` compara los nombres de los campos
/// contra las claves del JSON, y declara su residuo: no mira los valores. Un
/// `toJson` que escriba `'path': ''` lo pasa en verde. Esto es ese residuo.
///
/// **Y una lección que costó un sabotaje.** La primera versión de este archivo
/// comparaba `toJson → fromJson → toJson` contra `toJson`. Las dos mitades de
/// esa igualdad salían del mismo `toJson`, así que un campo escrito como
/// constante coincidía consigo mismo y el test pasaba. Era la **clase 1**
/// entera: el instrumento en verde sobre algo que no midió.
///
/// La corrección no es comparar más cosas a mano: es que **la instancia
/// canónica no tenga ningún valor por defecto en ningún campo**. Entonces
/// «ningún valor del JSON es un valor por defecto» se vuelve una aserción
/// derivada, y cualquier campo aplastado a `''`, `0`, `null` o vacío la rompe.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Recorre el JSON y devuelve las rutas cuyo valor es un valor por defecto.
List<String> valoresPorDefecto(Object? nodo, [String ruta = '']) {
  if (nodo == null) return [ruta];
  if (nodo is String) return nodo.isEmpty ? [ruta] : const [];
  if (nodo is num) return nodo == 0 ? [ruta] : const [];
  if (nodo is bool) return nodo ? const [] : [ruta];
  if (nodo is List) {
    if (nodo.isEmpty) return [ruta];
    return [
      for (var i = 0; i < nodo.length; i++)
        ...valoresPorDefecto(nodo[i], '$ruta[$i]'),
    ];
  }
  if (nodo is Map) {
    if (nodo.isEmpty) return [ruta];
    return [
      for (final e in nodo.entries)
        ...valoresPorDefecto(
            e.value, ruta.isEmpty ? '${e.key}' : '$ruta.${e.key}'),
    ];
  }
  return const [];
}

void main() {
  final cita = QuotedText('texto de afuera', source: 'sistema-externo');

  final criterio = AcceptanceCriterion(
    id: 'AC-1',
    statement:
        QuotedText('el saldo no puede quedar negativo', source: 'ticket'),
    assertionForm: 'forma-de-aserción-7',
  );

  final item = WorkItem(
    id: 'W-1',
    title: QuotedText('título', source: 'ticket'),
    description: QuotedText('descripción larga', source: 'ticket'),
    criteria: [criterio],
    sourceMetadata: {
      'campoDelAdapter': 'valor',
      'anidado': {'a': 1}
    },
  );

  final diagnostico = Diagnostic(
    file: 'lib/algo.fuente',
    line: 42,
    severity: Severity.bloquea,
    ruleId: 'R-9',
    message: QuotedText('mensaje de la herramienta', source: 'analizador'),
    sourceMetadata: {'columna': 7},
  );

  // exitCode 3 y no 0: un cero sería el valor por defecto, y entonces este
  // campo no probaría nada.
  final omision = Omission(
    subject: 'lib/ilegible.fuente',
    reason: 'no se pudo leer',
  );

  final testigo = Witness(
    invocation: 'verificador --sobre lib/',
    subjects: const ['lib/algo.fuente'],
    omitted: [omision],
    exitCode: 3,
    finishedAt: DateTime.utc(2026, 8, 29, 12, 34, 56),
  );

  final intento = Attempt(
    invocation: 'verificador --sobre lib/',
    subjects: const ['lib/algo.fuente'],
    termination: Termination.tiempoAgotado,
    exitCode: 124,
    note: 'se cortó por presupuesto de tiempo',
    finishedAt: DateTime.utc(2026, 8, 29, 12, 34, 56),
  );

  final traza = Trace(
    runId: 'run-1',
    startedAt: DateTime.utc(2026, 8, 29, 12, 0, 0),
    operational: OperationalSurface(
      toolsUsed: ['leer', 'escribir'],
      inputTokens: 1234,
      outputTokens: 567,
      elapsed: Duration(seconds: 89),
    ),
    cognitive: CognitiveSurface(
      available: true,
      decisions: ['eligió el camino corto'],
      planSummary: 'resumen',
    ),
    contextual: ContextualSurface(
      revision: 'abc123',
      filesInContext: ['lib/algo.fuente'],
      dirtyWorktree: true,
    ),
  );

  final regla = Rule(
    id: 'R-1',
    statement: 'no hagas aquello',
    origin: RuleOrigin.derivada,
    loadLevel: LoadLevel.bajoDemanda,
    signalType: SignalType.deterministaSobreElCambio,
    severity: Severity.bloquea,
    layer: ControlLayer.integracionContinua,
    knownEvasions: const ['se lo saltea con una bandera'],
    alternative: 'hacé esto otro',
    prohibitive: true,
  );

  final rebanada =
      PullRequestSlice(id: 'PR-1', intent: 'por qué existe', files: ['a.txt']);

  /// Cada entrada: la instancia canónica y cómo se la reconstruye.
  final canonicas =
      <String, (Map<String, Object?>, Object Function(Map<String, Object?>))>{
    'QuotedText': (cita.toJson(), QuotedText.fromJson),
    'Witness': (testigo.toJson(), Witness.fromJson),
    'AcceptanceCriterion': (criterio.toJson(), AcceptanceCriterion.fromJson),
    'WorkItem': (item.toJson(), WorkItem.fromJson),
    'ChangeClass': (
      const ChangeClass('clase-opaca').toJson(),
      ChangeClass.fromJson
    ),
    'Diagnostic': (diagnostico.toJson(), Diagnostic.fromJson),
    'Package': (
      Package(name: 'p', path: 'packages/p', dependsOn: ['core']).toJson(),
      Package.fromJson
    ),
    'PullRequestSlice': (rebanada.toJson(), PullRequestSlice.fromJson),
    'Plan': (
      Plan(
        workItemId: 'W-1',
        files: ['lib/algo.fuente'],
        tests: ['test/algo_prueba.fuente'],
        slices: [rebanada],
      ).toJson(),
      Plan.fromJson
    ),
    'OperationalSurface': (
      traza.operational.toJson(),
      OperationalSurface.fromJson
    ),
    'CognitiveSurface': (traza.cognitive.toJson(), CognitiveSurface.fromJson),
    'ContextualSurface': (
      traza.contextual.toJson(),
      ContextualSurface.fromJson
    ),
    'Trace': (traza.toJson(), Trace.fromJson),
    'Finding': (
      Finding(
        sensorId: 'S-1',
        criterionId: 'C-1',
        file: 'lib/algo.fuente',
        line: 9,
        note: cita,
      ).toJson(),
      Finding.fromJson
    ),
    'Rule': (regla.toJson(), Rule.fromJson),
    'Omission': (omision.toJson(), Omission.fromJson),
    'Attempt': (intento.toJson(), Attempt.fromJson),
    'Executed': (
      Executed(witness: testigo, diagnostics: [diagnostico]).toJson(),
      Executed.fromJson
    ),
    'Aborted': (Aborted(attempt: intento).toJson(), Aborted.fromJson),
    // **`Skipped` NO entra acá.** `Skipped` ahora rechaza cualquier sujeto
    // que el observador haya declarado del stack (invariante nueva, ver la
    // suite de verificación), así que la única instancia válida de
    // `notOfStack` trae exclusivamente sujetos ajenos — y esos SIEMPRE traen
    // `files: 0` y `ofStack: false` por el invariante de `ObservedSubject`.
    // Ninguna instancia canónica válida puede entonces hacer viajar esos dos
    // campos con un valor no default, así que este check —que exige
    // exactamente eso— no se le puede aplicar. Antes esta entrada usaba una
    // segunda instancia con un sujeto contradictorio (del stack) para
    // esquivarlo; era el síntoma del hallazgo crítico de la ronda 1,
    // convertido en dato de prueba. Ver el caso dedicado más abajo, que hace
    // lo mismo que ya hace `ScopeObservation` con su propio campo forzoso.
    'Unobservable': (
      Unobservable(causes: [
        UnobservedSubject(subject: 'no/existe', cause: 'no existe en el árbol')
      ]).toJson(),
      Unobservable.fromJson
    ),
    'Broken': (
      Broken(
        component: 'analizador-x',
        error: 'no se pudo invocar el binario',
        context: 'paso lib/algo.fuente',
      ).toJson(),
      Broken.fromJson
    ),
    'ObservedSubject · del stack': (
      ObservedSubject(subject: 'lib/codigo', ofStack: true, files: 2).toJson(),
      ObservedSubject.fromJson
    ),
    'ObservedSubject · ajeno al stack': (
      ObservedSubject(
        subject: 'lib/ajeno',
        ofStack: false,
        files: 0,
        reason: 'está fuera del stack',
      ).toJson(),
      ObservedSubject.fromJson
    ),
    'UnobservedSubject': (
      UnobservedSubject(
        subject: 'no/existe',
        cause: 'no existe en el árbol',
      ).toJson(),
      UnobservedSubject.fromJson
    ),
    'ScopeObservation · con sujetos del stack': (
      ScopeObservation(
        requested: const ['lib', 'no/existe'],
        observed: [
          ObservedSubject(subject: 'lib', ofStack: true, files: 2),
        ],
        unobserved: [
          UnobservedSubject(
              subject: 'no/existe', cause: 'no existe en el árbol'),
        ],
        observedAt: DateTime.utc(2026, 9, 5),
      ).toJson(),
      ScopeObservation.fromJson
    ),
    'ScopeObservation · con sujetos ajenos': (
      ScopeObservation(
        requested: const ['lib', 'LEEME.md'],
        observed: [
          ObservedSubject(
            subject: 'lib',
            ofStack: false,
            files: 0,
            reason: 'está fuera del stack',
          ),
        ],
        unobserved: [
          UnobservedSubject(subject: 'LEEME.md', cause: 'no es código fuente'),
        ],
        observedAt: DateTime.utc(2026, 9, 5),
      ).toJson(),
      ScopeObservation.fromJson
    ),
  };

  /// Clases cuyos campos son EXCLUYENTES: ninguna instancia puede tenerlos
  /// todos con valor, así que la precondición se cumple **sobre el conjunto**
  /// de sus instancias canónicas y no dentro de una.
  ///
  /// Es una excepción declarada, no un silencio: si mañana alguien agrega un
  /// tercer campo excluyente y no suma su instancia, este check lo caza igual
  /// —el campo nuevo quedaría en su default en TODAS—.
  const excluyentes = {'ObservedSubject', 'ScopeObservation'};

  group('la instancia canónica no trae valores por defecto', () {
    // Es la precondición de todo lo demás. Sin esto, un campo aplastado a `''`
    // o a `0` coincide consigo mismo en la ida y vuelta y no lo nota nadie.
    for (final e in canonicas.entries) {
      final clase = e.key.split(' · ').first;
      if (excluyentes.contains(clase)) continue;
      test(e.key, () {
        expect(valoresPorDefecto(e.value.$1), isEmpty,
            reason: 'estos campos salen con su valor por defecto, así que no '
                'distinguen «viajó» de «se perdió»');
      });
    }

    for (final clase in excluyentes) {
      test('$clase · entre todas sus instancias', () {
        final instancias = [
          for (final e in canonicas.entries)
            if (e.key.split(' · ').first == clase) e.value.$1,
        ];
        expect(instancias, hasLength(greaterThan(1)),
            reason: 'una clase con campos excluyentes necesita más de una '
                'instancia canónica, o la precondición no se puede cumplir');
        final enDefectoEnTodas = valoresPorDefecto(instancias.first)
            .where((ruta) =>
                instancias.every((i) => valoresPorDefecto(i).contains(ruta)))
            .toList();
        expect(enDefectoEnTodas, isEmpty,
            reason: 'estos campos salen con su valor por defecto en TODAS las '
                'instancias, así que no distinguen «viajó» de «se perdió»');
      });
    }
  });

  group('ida y vuelta sin pérdida (ADR-002)', () {
    for (final e in canonicas.entries) {
      test(e.key, () {
        final (original, reconstruir) = e.value;
        final texto = jsonEncode(original);
        final vuelto = reconstruir(jsonDecode(texto) as Map<String, Object?>);
        expect(jsonEncode((vuelto as dynamic).toJson()), equals(texto),
            reason: 'algún campo de ${e.key} no sobrevivió el viaje');
      });
    }
  });

  test('la escotilla de metadatos transporta sin interpretar (D-015)', () {
    final ida = WorkItem.fromJson(
        jsonDecode(jsonEncode(item.toJson())) as Map<String, Object?>);
    expect(ida.sourceMetadata['anidado'], equals({'a': 1}));
  });

  test('un enum viaja por nombre, no por índice', () {
    // Reordenar un enum no debe cambiar el significado de una traza vieja.
    expect(diagnostico.toJson()['severity'], equals('bloquea'));
  });

  test('la observación de alcance no pierde nada, y no trae vacíos', () {
    final o = ScopeObservation(
      requested: const ['lib', 'no/existe'],
      observed: [ObservedSubject(subject: 'lib', ofStack: true, files: 3)],
      unobserved: [
        UnobservedSubject(subject: 'no/existe', cause: 'no existe en el árbol')
      ],
      observedAt: DateTime.utc(2026, 9, 5),
    );
    // `reason` es nulo cuando el sujeto SÍ es del stack, y eso es correcto:
    // se excluye de la comprobación de vacíos porque su ausencia es el dato.
    final json = o.toJson();
    for (final e in json['observed']! as List) {
      (e as Map).remove('reason');
    }
    expect(valoresPorDefecto(json), isEmpty);
    expect(ScopeObservation.fromJson(o.toJson()).toJson(), o.toJson());
  });

  test("'Skipped' no pierde nada, y no trae vacíos que no sean forzosos", () {
    // Mismo caso que el de arriba, para el mismo motivo: `notOfStack` solo
    // admite sujetos ajenos al stack (la invariante que cerró el hallazgo
    // crítico de la ronda 1), y esos siempre traen `files: 0` y
    // `ofStack: false` — no hay ninguna instancia VÁLIDA de `Skipped` que
    // pueda demostrar que esos dos campos no son un valor por defecto
    // aplastado. Se excluyen de la comprobación de vacíos por la misma razón
    // que arriba excluye `reason`, y el round-trip se verifica a mano en vez
    // de por la lista `canonicas`.
    final s = Skipped(notOfStack: [
      ObservedSubject(
          subject: 'lib/ajeno-a', ofStack: false, files: 0, reason: 'motivo a'),
      ObservedSubject(
          subject: 'lib/ajeno-b', ofStack: false, files: 0, reason: 'motivo b'),
    ]);
    final json = s.toJson();
    for (final e in json['notOfStack']! as List) {
      (e as Map)
        ..remove('files')
        ..remove('ofStack');
    }
    expect(valoresPorDefecto(json), isEmpty);
    expect(Skipped.fromJson(s.toJson()).toJson(), s.toJson());
  });
}
