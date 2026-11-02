import 'dart:async';
import 'dart:isolate';

import 'directive_extractor.dart';

/// Analiza [content] de [path] dentro de [deadline]: sus directivas, un
/// fallo o el plazo vencido. Las pruebas la sustituyen.
typedef DirectiveParser =
    Future<DirectiveBatch> Function(
      String content,
      String path,
      Duration deadline,
    );

/// Un trabajador en otro isolate que analiza un archivo por vez. Si un
/// archivo vence su plazo, el isolate se mata sin esperar y el siguiente
/// archivo usa uno nuevo: ningún resultado tardío se acepta. No ejecuta
/// código del proyecto ni lanza procesos.
final class IsolateDirectiveParser {
  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _replies;
  StreamIterator<Object?>? _incoming;

  Future<DirectiveBatch> call(
    String content,
    String path,
    Duration deadline,
  ) async {
    await _start();
    _requests!.send((content, path));
    try {
      final more = await _incoming!.moveNext().timeout(deadline);
      if (!more) return const ParseTimedOut();
      return _incoming!.current! as DirectiveBatch;
    } on TimeoutException {
      await close();
      return const ParseTimedOut();
    }
  }

  Future<void> _start() async {
    if (_isolate != null) return;
    final replies = ReceivePort();
    final incoming = StreamIterator<Object?>(replies);
    final isolate = await Isolate.spawn(_serve, replies.sendPort);
    await incoming.moveNext();
    _requests = incoming.current! as SendPort;
    _isolate = isolate;
    _replies = replies;
    _incoming = incoming;
  }

  /// Mata el isolate, si lo hay, y suelta sus puertos.
  Future<void> close() async {
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    await _incoming?.cancel();
    _isolate = null;
    _requests = null;
    _replies = null;
    _incoming = null;
  }
}

void _serve(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    final (content, path) = message! as (String, String);
    replies.send(extractDirectives(content, path));
  });
}
