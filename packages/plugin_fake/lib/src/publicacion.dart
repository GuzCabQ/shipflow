import 'package:core/core.dart';

/// Un `PullRequestSink` que no habla con nadie. **Se configura, no adivina.**
///
/// No busca ni empuja: se le dice qué [PublicationOutcome] devolver, y esa
/// misma respuesta es la que entrega en cada llamada. Eso no es una limitación
/// — es lo que le permite a la suite de contrato exigirle idempotencia a las
/// dos implementaciones con la misma pregunta: repetir `open` con la misma
/// solicitud tiene que devolver el mismo desenlace utilizable, y un fake que
/// recuerda y repite lo cumple por diseño, sin reimplementar ninguna búsqueda.
///
/// **Puede configurarse con cualquier variante de [PublicationOutcome],
/// incluido un desenlace ambiguo (`unknown`).** Sin eso, la suite de contrato
/// no podría plantearle a la implementación falsa la misma pregunta que le
/// plantea a la real sobre qué hace un llamador que reintenta tras una
/// respuesta que no se sabe si tuvo efecto.
class SalidaDePrFalsa implements PullRequestSink {
  /// Qué devuelve `open`, siempre la misma para toda la vida de esta
  /// instancia.
  final PublicationOutcome respuesta;

  /// Cada solicitud recibida, en orden. Le permite a la suite de contrato
  /// comprobar cuántas veces se llamó a `open` sin que este fake tenga que
  /// saber qué significa eso — esa lectura es de quien prueba.
  final List<PullRequestRequest> recibidas = [];

  SalidaDePrFalsa({required this.respuesta});

  @override
  Future<PublicationOutcome> open(PullRequestRequest request) async {
    recibidas.add(request);
    return respuesta;
  }
}

/// Una `CredentialSource` configurada. **No lee el entorno**: si lo leyera,
/// una prueba pasaría o fallaría según el shell de quien la corre, que es
/// exactamente lo que un fake existe para evitar.
class FuenteDeCredencialFalsa implements CredentialSource {
  final Map<String, Credential> credenciales;

  const FuenteDeCredencialFalsa({this.credenciales = const {}});

  @override
  Future<Credential?> read(String key) async => credenciales[key];
}
