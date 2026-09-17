/// El cliente de GitHub: la primera implementación viva de `PullRequestSink`.
///
/// Habla con la API REST usando solo la biblioteca estándar de entrada y
/// salida del lenguaje —sin dependencias externas, como pide `contexto.md`—
/// y hace la búsqueda idempotente que impide que un reintento abra un
/// segundo pull request.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

import 'empuje.dart';

/// La clave del entorno bajo la que viaja el token de GitHub. Es la misma que
/// declara `clavesDeCredencial` en `core`; se repite acá como literal, y no
/// se importa esa constante, porque esta clase necesita UNA clave concreta de
/// GitHub y `clavesDeCredencial` es la lista de todas las que existen en el
/// repositorio, presente o futura.
const _claveDeCredencial = 'SHIPFLOW_GITHUB_TOKEN';

/// Dónde vive el repositorio y cómo se habla con su API. **Quién es la
/// forja no lo sabe `core`**: vive acá, en su propio adapter.
class ConfiguracionDeGitHub {
  final String duenio;
  final String repositorio;
  final Uri baseDeLaApi;
  final String urlDelRemoto;

  const ConfiguracionDeGitHub({
    required this.duenio,
    required this.repositorio,
    required this.baseDeLaApi,
    required this.urlDelRemoto,
  });
}

/// La línea del marcador estable: la clave de la búsqueda idempotente.
///
/// **Vive acá y no en quien arma el cuerpo del PR**, porque es
/// [SalidaDePrDeGitHub] quien la busca — la clave de una búsqueda pertenece a
/// quien busca. La tarea que arma el cuerpo completo del PR (`cuerpoDeGitHub`,
/// que todavía no existe) va a llamar a esta misma función para incluir la
/// línea, así que esta declaración no se mueve cuando esa tarea llegue.
///
/// Va en el cuerpo y no en el título porque el título se trunca (ver
/// `PullRequestRequest.titulo`). Lleva su propio `formatVersion` —del
/// marcador, no de ningún otro formato del repositorio— para poder cambiar
/// esta línea sin que la búsqueda deje de encontrar los pull requests que ya
/// la llevan con la forma vieja.
String marcadorEstable(PullRequestRequest solicitud) =>
    '<!-- shipflow:pr formatVersion=1 '
    'runId=${solicitud.draft.runId} revision=${solicitud.revision} -->';

/// La salida real: por acá sale un pull request de verdad.
///
/// **El cuerpo que arma [open] hoy es SOLO [marcadorEstable].** No es el
/// diseño final — es apenas lo que esta tarea necesita para que la búsqueda
/// idempotente tenga algo verificable en qué apoyarse, sin depender de la
/// tarea que todavía no existe. La tarea siguiente reemplaza esa línea única
/// por el render completo del artefacto y sigue llamando a [marcadorEstable]
/// para no duplicar la clave de la búsqueda. Quien lea este archivo antes de
/// que esa tarea llegue no debe leer el cuerpo mínimo de acá como la forma
/// definitiva del cuerpo de un PR.
class SalidaDePrDeGitHub implements PullRequestSink {
  final ConfiguracionDeGitHub configuracion;
  final CredentialSource credenciales;
  final EmpujeAislado empuje;
  final HttpClient Function() _crearCliente;

  SalidaDePrDeGitHub({
    required this.configuracion,
    required this.credenciales,
    required this.empuje,
    HttpClient Function()? clienteHttp,
  }) : _crearCliente = clienteHttp ?? HttpClient.new;

  @override
  Future<PublicationOutcome> open(PullRequestRequest request) async {
    final credencial = await credenciales.read(_claveDeCredencial);
    if (credencial == null) {
      // Sin credencial no se toca la red: no hay con qué autenticar ni la
      // búsqueda ni el push. Es `PushFailed` y no `PullRequestFailed` porque
      // todavía no se intentó nada de lo que hace específicamente a un pull
      // request — nada remoto ocurrió en absoluto.
      return PushFailed(causa: CausaDePublicacion.autenticacion);
    }

    final cliente = _crearCliente();
    try {
      final PublicationOutcome? existente;
      try {
        existente = await _buscarExistente(cliente, request, credencial);
      } on Object {
        // La búsqueda es de solo lectura: no tiene efecto remoto que dejar a
        // medias. Un fallo acá es un fallo común y reintentable, no un
        // `unknown` — `unknown` está reservado para el paso que sí puede
        // haber escrito algo del otro lado.
        return PullRequestFailed(causa: CausaDePublicacion.red);
      }
      if (existente != null) return existente;

      final resultadoDelEmpuje = await empuje.empujar(
        urlDelRemoto: configuracion.urlDelRemoto,
        credencial: credencial,
        revision: request.revision,
        rama: request.draft.branch,
      );
      // `NoEmpujado.desenlace` ya es un `PublicationOutcome`: se devuelve tal
      // cual, sin envolverlo en nada que pierda la distinción entre `push`
      // fallido y `push` desconocido que `EmpujeAislado` ya hizo.
      if (resultadoDelEmpuje is NoEmpujado) {
        return resultadoDelEmpuje.desenlace;
      }

      return await _crearPr(cliente, request, credencial);
    } finally {
      cliente.close(force: true);
    }
  }

  /// Encabeza el pedido con la credencial. **Nunca la interpola fuera de
  /// [Credential.use]**: el encabezado se arma adentro, y lo que sale de acá
  /// es el pedido ya autenticado, nunca el secreto suelto.
  void _autenticar(HttpClientRequest pedido, Credential credencial) {
    pedido.headers.set(
      HttpHeaders.authorizationHeader,
      credencial.use((secreto) => 'Bearer $secreto'),
    );
    pedido.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    pedido.headers.set('X-GitHub-Api-Version', '2022-11-28');
  }

  Uri _urlDePulls({Map<String, String>? query}) {
    final base = configuracion.baseDeLaApi;
    final path =
        '${base.path}/repos/${configuracion.duenio}/${configuracion.repositorio}/pulls';
    return query == null
        ? base.replace(path: path)
        : base.replace(path: path, queryParameters: query);
  }

  /// La búsqueda idempotente. **Rama y base no alcanzan**: una rama
  /// reutilizada recuperaría un PR ajeno. La clave completa es
  /// repositorio/remoto (fijos en [configuracion]), rama origen, rama base,
  /// la revisión esperada, el marcador estable con su propio `runId` y
  /// `revision`, y el estado del PR.
  Future<PublicationOutcome?> _buscarExistente(
    HttpClient cliente,
    PullRequestRequest request,
    Credential credencial,
  ) async {
    final uri = _urlDePulls(
      query: {
        'head': '${configuracion.duenio}:${request.draft.branch}',
        'base': request.draft.base,
        'state': 'all',
      },
    );
    final pedido = await cliente.getUrl(uri);
    _autenticar(pedido, credencial);
    final respuesta = await pedido.close();
    final cuerpo = await utf8.decoder.bind(respuesta).join();
    final lista = jsonDecode(cuerpo) as List<Object?>;
    final marcador = marcadorEstable(request);

    for (final item in lista) {
      final pr = item as Map<String, Object?>;
      final cabeza = pr['head'] as Map<String, Object?>?;
      if (cabeza?['sha'] != request.revision) continue;
      final cuerpoDelPr = pr['body'] as String? ?? '';
      if (!cuerpoDelPr.contains(marcador)) continue;

      final url = pr['html_url']! as String;
      final estado = pr['state'] as String?;
      final fusionadoEl = pr['merged_at'];
      if (estado == 'open') {
        // Ya hay un PR abierto para esta misma revisión: no se empuja de
        // nuevo, se devuelve el que ya existe.
        return PullRequestOpen(url: url);
      }
      if (fusionadoEl != null) return PullRequestMerged(url: url);
      if (estado == 'closed') return PullRequestClosed(url: url);
    }
    return null;
  }

  Future<PublicationOutcome> _crearPr(
    HttpClient cliente,
    PullRequestRequest request,
    Credential credencial,
  ) async {
    final String cuerpoDeLaRespuesta;
    final int codigo;
    final ContentType? tipoDeContenido;
    try {
      final pedido = await cliente.postUrl(_urlDePulls());
      _autenticar(pedido, credencial);
      pedido.headers.contentType = ContentType.json;
      pedido.write(
        jsonEncode({
          'title': request.titulo,
          'head': request.draft.branch,
          'base': request.draft.base,
          'body': marcadorEstable(request),
        }),
      );
      final respuesta = await pedido.close();
      codigo = respuesta.statusCode;
      tipoDeContenido = respuesta.headers.contentType;
      cuerpoDeLaRespuesta = await utf8.decoder.bind(respuesta).join();
    } on Object {
      // Ni excepción ni socket cortado dicen si el POST llegó a crear el PR
      // del otro lado. Reportarlo como `failed` haría que quien reintenta
      // abra un segundo pull request; `unknown` es lo que lo manda de nuevo
      // por la búsqueda idempotente en vez de por una creación ciega.
      return PullRequestUnknown(causa: CausaDePublicacion.red);
    }

    if (tipoDeContenido?.mimeType != 'application/json') {
      // La forja real contesta este endpoint en JSON, tanto si crea el PR
      // como si lo rechaza. Una respuesta que no lo es —un `200` en blanco,
      // la página de un proxy intermedio— no es un desenlace de GitHub que
      // este cliente sepa leer: es el mismo cuadro que una conexión cortada
      // a mitad de camino, y no hay código de estado que la vuelva confiable.
      return PullRequestUnknown(causa: CausaDePublicacion.red);
    }

    if (codigo == HttpStatus.created) {
      try {
        final data = jsonDecode(cuerpoDeLaRespuesta) as Map<String, Object?>;
        final url = data['html_url'] as String?;
        if (url == null || url.trim().isEmpty) {
          // 201 sin URL utilizable es una respuesta incompleta, no un
          // fallo: el servidor puede haber creado el PR igual.
          return PullRequestUnknown(causa: CausaDePublicacion.red);
        }
        return PullRequestOpen(url: url);
      } on FormatException {
        return PullRequestUnknown(causa: CausaDePublicacion.red);
      }
    }
    // El cuerpo de la respuesta de error no se mira nunca: solo el código de
    // estado decide la causa. Copiar el texto del servidor a `safeReason`
    // sería exactamente lo que esa cadena promete no hacer.
    return switch (codigo) {
      HttpStatus.unauthorized => PullRequestFailed(
        causa: CausaDePublicacion.autenticacion,
      ),
      HttpStatus.forbidden => PullRequestFailed(
        causa: CausaDePublicacion.permisos,
      ),
      HttpStatus.unprocessableEntity => PullRequestFailed(
        causa: CausaDePublicacion.rechazoDeLaForja,
      ),
      _ => PullRequestFailed(causa: CausaDePublicacion.desconocida),
    };
  }
}
