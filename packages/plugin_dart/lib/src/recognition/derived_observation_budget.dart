import 'package:core/core.dart';

/// El presupuesto derivado de una producción: uno solo, compartido por el
/// escáner y los observadores. Cada uno cobra lo que va a retener antes de
/// construirlo; una observación que pasa de borrador a final no se vuelve a
/// cobrar, pero cada fila o referencia nueva sí.
final class DerivedObservationBudget {
  DerivedObservationBudget(this.limits);

  final ReportLimits limits;
  DerivedUsage _used = const DerivedUsage();

  /// Lo cobrado hasta ahora, como un valor inmutable.
  DerivedUsage get usage => _used;

  /// Cobra [items] elementos y los bytes UTF-8 de [texts], o lanza
  /// [ReportLimitExceeded] sin cobrar nada.
  void charge({int items = 0, Iterable<String> texts = const []}) {
    var bytes = 0;
    for (final text in texts) {
      bytes += utf8Length(text);
    }
    _used = admitDerivedUsage(_used, limits, items: items, textBytes: bytes);
  }

  /// Una fila semántica: un elemento y sus textos.
  void row(Iterable<String> texts) => charge(items: 1, texts: texts);

  /// Recorre [source] de a uno: cobra cada elemento como fila con
  /// [textsOf] y sólo entonces lo construye con [build]. El primero que no
  /// cabe detiene el recorrido sin construirse ni pedir el siguiente.
  Iterable<T> admitEach<S, T>(
    Iterable<S> source, {
    required Iterable<String> Function(S item) textsOf,
    required T Function(S item) build,
  }) sync* {
    for (final item in source) {
      row(textsOf(item));
      yield build(item);
    }
  }
}
