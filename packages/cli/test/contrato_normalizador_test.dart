/// Suite de contrato de `DiagnosticNormalizer`, contra las TRES
/// implementaciones vivas: dos reales —una por herramienta— y la falsa.
///
/// El formato de cada una es distinto y la suite no lo conoce: cada caso trae
/// su propia muestra. Lo que se prueba es el CONTRATO —las cuatro clausulas
/// del puerto—, no que ningun parseo concreto este bien.
///
/// **Las muestras de las reales son salida capturada de verdad**, no inventada
/// a mano. Una muestra escrita de memoria es un fixture que miente sobre si
/// mismo: la suite queda verde contra un formato que la herramienta no emite.
///
/// **Residuo declarado.** Que esas muestras sigan pareciendose a lo que la
/// herramienta emite HOY, esta suite no lo sabe: son cadenas congeladas. Lo
/// cubre el paso de cascada de la rebanada siguiente, que invoca la
/// herramienta de verdad sobre el fixture y le pasa la salida a este mismo
/// normalizador. Hasta que ese paso exista, el hueco esta abierto y escrito.
///
/// **Segundo residuo declarado.** `Formatted no files` se interpreta sin error
/// y devuelve la lista vacia, y esta bien que asi sea: el normalizador lee un
/// texto y ese texto no reporta nada. Que CERO ARCHIVOS MIRADOS no sea verde
/// no es asunto suyo sino del testigo del paso, que es quien sabe cuantos
/// archivos pidio. Queda escrito aca para que la clausula 1 no se lea como si
/// cubriera algo que no cubre.
library;

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';

/// Salida real de `dart analyze --format=json` sobre un archivo con un error
/// de tipos y dos variables sin usar.
const analisisConHallazgos =
    r'''{"version":1,"diagnostics":[{"code":"invalid_assignment","severity":"ERROR","type":"COMPILE_TIME_ERROR","location":{"file":"/tmp/lib/malo.dart","range":{"start":{"offset":46,"line":3,"column":14},"end":{"offset":47,"line":3,"column":15}}},"problemMessage":"A value of type 'int' can't be assigned to a variable of type 'String'.","correctionMessage":"Try changing the type of the variable, or casting the right-hand type to 'String'.","documentation":"https://dart.dev/diagnostics/invalid_assignment"},{"code":"unused_local_variable","severity":"WARNING","type":"STATIC_WARNING","location":{"file":"/tmp/lib/malo.dart","range":{"start":{"offset":20,"line":2,"column":7},"end":{"offset":27,"line":2,"column":14}}},"problemMessage":"The value of the local variable 'sinUsar' isn't used.","correctionMessage":"Try removing the variable or using it.","documentation":"https://dart.dev/diagnostics/unused_local_variable"},{"code":"unused_local_variable","severity":"WARNING","type":"STATIC_WARNING","location":{"file":"/tmp/lib/malo.dart","range":{"start":{"offset":42,"line":3,"column":10},"end":{"offset":43,"line":3,"column":11}}},"problemMessage":"The value of the local variable 'x' isn't used.","correctionMessage":"Try removing the variable or using it.","documentation":"https://dart.dev/diagnostics/unused_local_variable"}]}''';

/// Lo que emite cuando corrio y no encontro nada. **Afirma haber mirado**, que
/// es la unica razon por la que este plugin usa este formato y no el otro.
const analisisLimpio = r'''{"version":1,"diagnostics":[]}''';

/// Salida real de `dart format --output=none`: primero la corriente estandar,
/// despues la de error, que es como la ensambla quien lo invoca.
const formatoConHallazgos = r'''Changed lib/feo.dart
Formatted 2 files (1 changed) in 0.00 seconds.
Could not format because the source could not be parsed:

line 2, column 1 of lib/roto.dart: Expected to find '}'.
  ╷
2 │  
  │ ^
  ╵
line 2, column 1 of lib/roto.dart: Expected to find ')'.
  ╷
2 │  
  │ ^
  ╵
line 2, column 1 of lib/roto.dart: Expected an identifier.
  ╷
2 │ 
  │ ^
  ╵
line 2, column 1 of lib/roto.dart: A function body must be provided.
  ╷
2 │ 
  │ ^
  ╵
''';

const formatoLimpio = 'Formatted 1 file (0 changed) in 0.00 seconds.\n';

class _Caso {
  final DiagnosticNormalizer normalizador;

  /// Corrio y no encontro nada. Tiene que devolver la lista vacia SIN lanzar.
  final String limpio;

  /// Corrio y encontro [cuantos] cosas.
  final String conHallazgos;
  final int cuantos;

  /// Entradas que NO se pueden interpretar, con el motivo por el que estan.
  final Map<String, String> ilegibles;

  const _Caso(this.normalizador,
      {required this.limpio,
      required this.conHallazgos,
      required this.cuantos,
      required this.ilegibles});
}

/// Ilegibles que valen para cualquier formato: son la clausula 2 y su vecina.
const ilegiblesUniversales = {
  'la entrada vacia': '',
  'la entrada en blanco': '   \n  \t\n',
};

final implementaciones = <String, _Caso>{
  'real · analizador estatico': _Caso(
    const NormalizadorDeAnalisis(),
    limpio: analisisLimpio,
    conHallazgos: analisisConHallazgos,
    cuantos: 3,
    ilegibles: {
      ...ilegiblesUniversales,
      'texto que no es del formato': 'no soy una salida de nada',
      'un esquema de version futura': r'{"version":99,"diagnostics":[]}',
      'la raiz no es un objeto': r'[]',
      'los hallazgos no son una lista': r'{"version":1,"diagnostics":"nada"}',
      'un hallazgo sin ubicacion':
          r'{"version":1,"diagnostics":[{"code":"c","severity":"ERROR","problemMessage":"m"}]}',
      'una severidad que no sabe mapear':
          r'{"version":1,"diagnostics":[{"code":"c","severity":"FATAL","problemMessage":"m","location":{"file":"a"}}]}',
      'la salida de la OTRA herramienta': formatoConHallazgos,
    },
  ),
  'real · formateador': _Caso(
    const NormalizadorDeFormato(),
    limpio: formatoLimpio,
    conHallazgos: formatoConHallazgos,
    // Un archivo sin formatear y las cuatro quejas del que no parsea.
    cuantos: 5,
    ilegibles: {
      ...ilegiblesUniversales,
      'texto que no es del formato': 'no soy una salida de nada',
      // El caso que importa: hay hallazgos pero falta el DENOMINADOR. Sin el,
      // esta lista no se puede leer.
      'hallazgos sin linea de resumen': 'Changed lib/a.dart\n',
      'la salida de la OTRA herramienta': analisisConHallazgos,
    },
  ),
  'falsa · formato propio, trivial': _Caso(
    const NormalizadorFalso(),
    limpio: '${NormalizadorFalso.encabezado}\n',
    conHallazgos: '${NormalizadorFalso.encabezado}\n'
        'bloquea|src/a|12|regla-x|Primer mensaje\n'
        'reporta|src/b||regla-y|Segundo mensaje\n',
    cuantos: 2,
    ilegibles: {
      ...ilegiblesUniversales,
      'texto que no es del formato': 'no soy una salida de nada',
      'una linea con campos de menos':
          '${NormalizadorFalso.encabezado}\nbloquea|src/a|12\n',
      'una severidad que no sabe mapear':
          '${NormalizadorFalso.encabezado}\nfatal|src/a|1|r|m\n',
    },
  ),
};

QuotedText _entrada(String texto, String quien) =>
    QuotedText(texto, source: quien);

void main() {
  test('la suite corre contra las TRES implementaciones, y dos son reales', () {
    expect(implementaciones, hasLength(3));
    expect(
        implementaciones.keys.where((k) => k.startsWith('real')), hasLength(2),
        reason: 'sin las reales esto no es una suite de contrato');
  });

  for (final entrada in implementaciones.entries) {
    final quien = entrada.key;
    final caso = entrada.value;

    group(quien, () {
      final n = caso.normalizador;

      caso.ilegibles.forEach((motivo, texto) {
        test('$motivo no se interpreta: lanza, no devuelve vacio', () {
          // Clausula 1. Es LA clausula: devolver `[]` aca haria que «no
          // entendi» y «todo bien» se leyeran igual, que es la clase 1 exacta.
          expect(
            () => n.normalize(_entrada(texto, quien)),
            throwsA(isA<UnreadableToolOutput>()),
            reason: 'devolver una lista vacia ante esto es un falso verde',
          );
        });
      });

      test('la salida limpia se interpreta y da cero hallazgos', () {
        // El otro lado de la clausula 1: un normalizador que rechazara
        // cualquier entrada seria inutil y las pruebas de arriba pasarian
        // igual. Este test impide que la clausula se cumpla por la via de no
        // funcionar.
        final r = n.normalize(_entrada(caso.limpio, quien));
        expect(r, isEmpty);
      });

      test('una salida con hallazgos los devuelve TODOS', () {
        final r = n.normalize(_entrada(caso.conHallazgos, quien));
        expect(r, hasLength(caso.cuantos),
            reason: 'un normalizador que descarta lo que no entiende devuelve '
                'menos de los que hay, y nada lo dice');
      });

      test('la lista devuelta es inmodificable', () {
        final r = n.normalize(_entrada(caso.conHallazgos, quien));
        expect(
            () => r.add(Diagnostic(
                  file: 'x',
                  severity: Severity.reporta,
                  ruleId: 'r',
                  message: const QuotedText('m', source: 'test'),
                )),
            throwsUnsupportedError);
      });

      test(
          'el mensaje de cada hallazgo es el de la herramienta, sin '
          'reescribir', () {
        // Clausula 4, INV-6. Se comprueba contra el texto de entrada: si el
        // normalizador redactara el mensaje, el suyo no estaria ahi.
        final r = n.normalize(_entrada(caso.conHallazgos, quien));
        for (final d in r) {
          expect(caso.conHallazgos, contains(d.message.content),
              reason: 'el mensaje «${d.message.content}» no aparece en la '
                  'salida de la herramienta: alguien lo reescribio');
        }
      });
    });
  }
}
