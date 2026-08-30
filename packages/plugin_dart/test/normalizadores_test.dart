/// Unitarios de los dos normalizadores.
///
/// La suite de contrato prueba que una entrada ilegible LANZA. No prueba
/// **cual** guardia la rechazo, y esa diferencia importa: un guardia al que
/// otro le tapa el caso nunca dispara, y un control que nunca disparo no esta
/// probado. Aca cada uno se identifica por su motivo.
library;

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

QuotedText t(String s) => QuotedText(s, source: 'prueba');

Matcher rechazaPor(String fragmento) => throwsA(isA<UnreadableToolOutput>()
    .having((e) => e.reason, 'motivo', contains(fragmento)));

void main() {
  group('analizador estatico', () {
    const n = NormalizadorDeAnalisis();

    test('el guardia del vacio es el que dispara, y no el decodificador', () {
      // Sin este test, el guardia explicito seria codigo muerto: el
      // decodificador de JSON tambien falla ante el vacio, asi que la suite de
      // contrato quedaria verde con el guardia borrado. Un guardia al que otro
      // le tapa el caso no esta instalado: esta de adorno.
      expect(() => n.normalize(t('')), rechazaPor('vacia'));
      expect(() => n.normalize(t('  \n\t ')), rechazaPor('vacia'));
    });

    test('una version de esquema desconocida no se lee con reglas viejas', () {
      expect(() => n.normalize(t(r'{"version":2,"diagnostics":[]}')),
          rechazaPor('version'));
    });

    test('una severidad sin mapeo no cae en la mas suave', () {
      expect(
          () => n.normalize(t(r'{"version":1,"diagnostics":[{"code":"c",'
              r'"severity":"HINT","problemMessage":"m","location":{"file":"a"}}]}')),
          rechazaPor('Severidad desconocida'));
    });

    test('lo informativo anota y lo demas detiene', () {
      List<Diagnostic> uno(String sev) => n.normalize(
          t('{"version":1,"diagnostics":[{"code":"c","severity":"$sev",'
              r'"problemMessage":"m","location":{"file":"a.txt"}}]}'));
      expect(uno('ERROR').single.severity, Severity.bloquea);
      // La herramienta trae `--fatal-warnings` encendido por defecto: una
      // advertencia detiene igual que un error.
      expect(uno('WARNING').single.severity, Severity.bloquea);
      expect(uno('INFO').single.severity, Severity.reporta);
    });

    test('un hallazgo sin linea la deja nula, no en cero', () {
      // Cero es una linea que existe. Nulo es «la herramienta no dijo».
      final d = n
          .normalize(t(r'{"version":1,"diagnostics":[{"code":"c",'
              r'"severity":"INFO","problemMessage":"m","location":{"file":"a.txt"}}]}'))
          .single;
      expect(d.line, isNull);
      expect(d.file, 'a.txt');
    });

    test('la correccion sugerida va a la escotilla, no al mensaje', () {
      final d = n
          .normalize(t(r'{"version":1,"diagnostics":[{"code":"c",'
              r'"severity":"INFO","problemMessage":"m","correctionMessage":"hace esto",'
              r'"location":{"file":"a.txt","range":{"start":{"line":9}}}}]}'))
          .single;
      expect(d.message.content, 'm',
          reason: 'el mensaje es el de la herramienta y nada mas (INV-6)');
      expect(d.sourceMetadata['correccion'], 'hace esto');
      expect(d.line, 9);
      expect(d.ruleId, 'c',
          reason: 'el codigo de la herramienta viaja tal cual');
    });
  });

  group('formateador', () {
    const n = NormalizadorDeFormato();

    test('sin linea de resumen no hay denominador y no se interpreta', () {
      expect(() => n.normalize(t('Changed lib/a.dart\n')),
          rechazaPor('denominador'));
    });

    test(
        '«no files» se interpreta y da cero: el cero archivos lo juzga el '
        'testigo, no esto', () {
      // Decision escrita, no accidente. Esta salida es la que produce la
      // herramienta cuando le pasan un directorio que no existe, Y SALE CON
      // CODIGO 0. Que eso no sea verde es asunto del paso, que sabe cuantos
      // archivos pidio; el normalizador solo lee un texto, y ese texto no
      // reporta nada.
      expect(n.normalize(t('Formatted no files in 0.00 seconds.\n')), isEmpty);
    });

    test('un archivo sin formatear detiene y trae su alternativa', () {
      final d = n
          .normalize(t('Changed lib/a.dart\n'
              'Formatted 3 files (1 changed) in 0.01 seconds.\n'))
          .single;
      expect(d.file, 'lib/a.dart');
      expect(d.severity, Severity.bloquea);
      expect(d.sourceMetadata['alternativa'], isNotNull,
          reason: 'INV-8: solo detiene lo que puede decir que hacer');
    });

    test('S4 · un archivo que no parsea produce diagnostico con su linea', () {
      final ds = n.normalize(t('Formatted no files in 0.00 seconds.\n'
          'Could not format because the source could not be parsed:\n'
          '\n'
          "line 7, column 1 of lib/roto.dart: Expected to find '}'.\n"
          '  |\n'));
      expect(ds, hasLength(1));
      expect(ds.single.file, 'lib/roto.dart');
      expect(ds.single.line, 7);
      expect(ds.single.severity, Severity.bloquea);
    });

    test('S4 · si el bloque de parseo no deja leer ni una linea, es ilegible',
        () {
      // El salto silencioso exacto que S4 busca: la herramienta dijo que algo
      // no parsea y de ese bloque no salio ningun hallazgo. Devolver la lista
      // sin ellos convertiria un archivo corrupto en silencio.
      expect(
          () => n.normalize(t('Formatted no files in 0.00 seconds.\n'
              'Could not format because the source could not be parsed:\n'
              'formato que no reconocemos\n')),
          rechazaPor('salto silencioso'));
    });
  });
}
