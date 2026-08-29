/// Los requisitos de instalación de una regla, como invariantes de construcción.
///
/// Que estén en el constructor y no en un validador aparte es el punto entero:
/// un validador se puede no llamar. Cada prueba de acá corresponde a un
/// invariante de PSEUDOCODIGO parte A.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

Rule regla({
  Severity severity = Severity.reporta,
  SignalType signalType = SignalType.deterministaSobreElCambio,
  ControlLayer layer = ControlLayer.integracionContinua,
  List<String> knownEvasions = const [],
  String? alternative,
  bool prohibitive = false,
}) =>
    Rule(
      id: 'R-1',
      statement: 'enunciado',
      origin: RuleOrigin.derivada,
      loadLevel: LoadLevel.bajoDemanda,
      signalType: signalType,
      severity: severity,
      layer: layer,
      knownEvasions: knownEvasions,
      alternative: alternative,
      prohibitive: prohibitive,
    );

Matcher rechazaPor(String invariante) => throwsA(isA<RuleNotInstallable>()
    .having((e) => e.invariant, 'invariante', invariante));

void main() {
  test('INV-11 · una prohibición sin alternativa no se instala', () {
    expect(() => regla(prohibitive: true), rechazaPor('INV-11'));
    expect(() => regla(prohibitive: true, alternative: '   '),
        rechazaPor('INV-11'));
    expect(
        regla(prohibitive: true, alternative: 'hacé esto').prohibitive, isTrue);
  });

  test('INV-8 · se bloquea solo si se puede decir qué hacer', () {
    expect(() => regla(severity: Severity.bloquea), rechazaPor('INV-8'));
    expect(regla(severity: Severity.bloquea, alternative: 'hacé esto').severity,
        equals(Severity.bloquea));
  });

  test('INV-4 · un control inferencial nunca bloquea', () {
    expect(
      () => regla(
          signalType: SignalType.inferencial,
          severity: Severity.bloquea,
          alternative: 'hacé esto'),
      rechazaPor('INV-4'),
    );
  });

  test('INV-3 · ningún gancho se instala sin sus evasiones declaradas', () {
    expect(() => regla(layer: ControlLayer.ganchos), rechazaPor('INV-3'));
    expect(
        regla(layer: ControlLayer.ganchos, knownEvasions: ['se saltea así'])
            .layer,
        equals(ControlLayer.ganchos));
  });

  test('INV-10 · lo que bloquea no se funda en la capa de ganchos', () {
    expect(
      () => regla(
          layer: ControlLayer.ganchos,
          knownEvasions: ['se saltea así'],
          severity: Severity.bloquea,
          alternative: 'hacé esto'),
      rechazaPor('INV-10'),
    );
  });

  test('el mensaje del rechazo dice qué hacer, no solo qué falta', () {
    try {
      regla(prohibitive: true);
      fail('debería haber sido rechazada');
    } on RuleNotInstallable catch (e) {
      expect(e.reason.toLowerCase(), contains('escribí'));
    }
  });

  group('ADR-013 · una regla entra reportando…', () {
    test('…salvo que su tipo de señal sea instrumento', () {
      final instrumento = Rule.entering(
        id: 'R-2',
        statement: 'el meta-check compara pasos registrados contra ejecutados',
        origin: RuleOrigin.derivada,
        loadLevel: LoadLevel.siempre,
        signalType: SignalType.instrumento,
        layer: ControlLayer.integracionContinua,
        alternative: 'arreglá el instrumento antes de seguir',
      );
      expect(instrumento.severity, equals(Severity.bloquea));
    });

    test('una determinista nueva entra reportando', () {
      final nueva = Rule.entering(
        id: 'R-3',
        statement: 'x',
        origin: RuleOrigin.intencional,
        loadLevel: LoadLevel.bajoDemanda,
        signalType: SignalType.deterministaSobreElCambio,
        layer: ControlLayer.cascada,
      );
      expect(nueva.severity, equals(Severity.reporta));
    });

    test('una inferencial nueva entra reportando y no puede promoverse', () {
      final nueva = Rule.entering(
        id: 'R-4',
        statement: 'x',
        origin: RuleOrigin.derivada,
        loadLevel: LoadLevel.soloAlPedirlo,
        signalType: SignalType.inferencial,
        layer: ControlLayer.cascada,
      );
      expect(nueva.severity, equals(Severity.reporta));
    });
  });

  test('una regla cargada de JSON pasa por los mismos invariantes', () {
    // El camino que esquivaba el validador en el intento anterior: la regla no
    // se escribía a mano, se leía de un archivo de configuración.
    final json = regla(prohibitive: true, alternative: 'hacé esto').toJson()
      ..['alternative'] = null;
    expect(() => Rule.fromJson(json), rechazaPor('INV-11'));
  });
}
