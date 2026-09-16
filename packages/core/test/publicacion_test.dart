import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('lo utilizable no cabe donde va lo incompleto', () {
    expect(PullRequestOpen(url: 'u'), isA<PublicacionUtilizable>());
    expect(PullRequestMerged(url: 'u'), isA<PublicacionUtilizable>());
    expect(
      PullRequestClosed(url: 'u'),
      isNot(isA<PublicacionUtilizable>()),
      reason: 'cerrado es terminal y NO completo',
    );
  });

  test('la acción siguiente se deriva de la variante y su causa', () {
    expect(
      PushFailed(causa: CausaDePublicacion.red).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
    expect(
      PushUnknown(causa: CausaDePublicacion.desconocida).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
    expect(
      PushFailed(causa: CausaDePublicacion.permisos).nextAction,
      AccionSiguiente.corregirPermisos,
      reason: 'reintentar no ayuda',
    );
    expect(
      PullRequestFailed(causa: CausaDePublicacion.red).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
    expect(
      PullRequestUnknown(causa: CausaDePublicacion.red).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
    expect(
      PullRequestClosed(url: 'u').nextAction,
      AccionSiguiente.entregaNuevaExplicita,
    );
    expect(PullRequestOpen(url: 'u').nextAction, AccionSiguiente.ninguna);
    expect(PullRequestMerged(url: 'u').nextAction, AccionSiguiente.ninguna);
  });

  test('permisos no es reintentable y el cerrado tampoco', () {
    expect(PushFailed(causa: CausaDePublicacion.permisos).retryable, isFalse);
    expect(PullRequestClosed(url: 'u').retryable, isFalse);
    expect(PushFailed(causa: CausaDePublicacion.red).retryable, isTrue);
    expect(PushUnknown(causa: CausaDePublicacion.red).retryable, isTrue);
  });

  test('solo lo utilizable es entrega completa', () {
    expect(PullRequestOpen(url: 'u').deliveryStatus, EstadoDeEntrega.completa);
    expect(
      PullRequestMerged(url: 'u').deliveryStatus,
      EstadoDeEntrega.completa,
    );
    expect(
      PullRequestClosed(url: 'u').deliveryStatus,
      EstadoDeEntrega.incompletaNoReintentable,
    );
    expect(
      PushFailed(causa: CausaDePublicacion.red).deliveryStatus,
      EstadoDeEntrega.incompletaReintentable,
    );
    expect(
      PushFailed(causa: CausaDePublicacion.permisos).deliveryStatus,
      EstadoDeEntrega.incompletaNoReintentable,
    );
  });

  test('la razón segura sale de la causa, no de un texto externo', () {
    for (final c in CausaDePublicacion.values) {
      final razon = PushFailed(causa: c).safeReason;
      expect(razon, isNotEmpty);
      expect(razon.contains('ghp_'), isFalse);
    }
  });

  test('una URL en blanco no identifica ningún PR', () {
    expect(() => PullRequestOpen(url: '  '), throwsArgumentError);
    expect(() => PullRequestClosed(url: ''), throwsArgumentError);
  });

  test('un kind que no nombra ninguna variante lanza', () {
    expect(
      () => PublicationOutcome.fromJson(const {'kind': 'inventado'}),
      throwsFormatException,
    );
  });

  test('cada fromJson rechaza un discriminador ajeno', () {
    expect(
      () => PullRequestOpen.fromJson(const {'kind': 'merged', 'url': 'u'}),
      throwsArgumentError,
    );
  });
}
