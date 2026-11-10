import 'dart:convert';
import 'dart:io';

import 'package:cli/src/command/cli_command.dart';
import 'package:cli/src/context/context_codec.dart';
import 'package:cli/src/context/context_request.dart';
import 'package:cli/src/context/context_service.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:cli/src/recognition_runner.dart';
import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:vcs/vcs.dart';

/// Una raíz canónica de proyecto y Git controlado por el PATH que se elija.
final class ServiceSandbox {
  ServiceSandbox._(this.base, this.root);

  static ServiceSandbox create() {
    final base = Directory(
      Directory.systemTemp
          .createTempSync('shipflow-svc-')
          .resolveSymbolicLinksSync(),
    );
    return ServiceSandbox._(
      base,
      Directory('${base.path}/proyecto')..createSync(),
    );
  }

  /// Otra raíz bajo la misma base, como una segunda copia de trabajo.
  factory ServiceSandbox.at(Directory base, Directory root) =>
      ServiceSandbox._(base, root);

  final Directory base;
  final Directory root;
  var _ids = 0;

  /// Sin Git: un PATH vacío y fuera del proyecto.
  Map<String, String> get noGit => {'PATH': '${base.path}/sin-git'};

  Map<String, String> get realGit => {
    'PATH': Platform.environment['PATH']!,
    'HOME': Platform.environment['HOME']!,
  };

  /// Un Git que responde a la primera observación y falla desde la
  /// segunda: la corroboración de la modalidad ya no lo alcanza.
  Map<String, String> get gitFailingAfterObservation {
    final dir = Directory('${base.path}/git-falla')..createSync();
    final seen = '${dir.path}/visto';
    File('${dir.path}/git').writeAsStringSync(
      '#!/bin/sh\n'
      'case " \$* " in *" --version "*)\n'
      '  if [ -f "$seen" ]; then exit 128; fi\n'
      '  : > "$seen" ;;\n'
      'esac\n'
      'exec /usr/bin/git "\$@"\n',
    );
    Process.runSync('/bin/chmod', ['+x', '${dir.path}/git']);
    return {'PATH': dir.path, 'HOME': Platform.environment['HOME']!};
  }

  String path(String relative) => '${root.path}/$relative';

  File file(String relative, String text) {
    final file = File(path(relative));
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(text);
  }

  /// Un paquete reconocible en la raíz.
  void project() => file('pubspec.yaml', 'name: app\n');

  void gitInit() {
    for (final args in [
      ['init', '-q', '-b', 'main'],
      ['config', 'user.email', 'prueba@example.invalid'],
      ['config', 'user.name', 'Prueba'],
    ]) {
      Process.runSync('git', args, workingDirectory: root.path);
    }
  }

  String newId() {
    _ids++;
    return '00000000-0000-4000-8000-${_ids.toString().padLeft(12, '0')}';
  }

  Future<ContextOperationResult> run(
    ContextOperation operation, {
    SharingChoice? sharing,
    Map<String, String>? git,
    ReportBudgetProfile profile = ReportBudgetProfile.standard,
    ContextStore Function(ContextStore real)? wrap,
    Future<SharingChoice?> Function(SharingQuestion question)? choose,
    Future<ContextStore> Function(Directory)? openAdministration,
  }) async {
    final real = await SecureContextStore.open(root);
    try {
      return await _service(
        wrap == null ? real : wrap(real),
        git,
        openAdministration,
      ).run(
        ContextRequest(
          operation: operation,
          sharing: sharing,
          profile: profile,
          choose: choose,
        ),
      );
    } finally {
      await real.close();
    }
  }

  /// Un servicio sobre [store], para invocarlo más de una vez. Quien abre el
  /// almacén lo cierra.
  ProjectContextService service(
    ContextStore store, {
    Map<String, String>? git,
  }) => _service(store, git, null);

  ProjectContextService _service(
    ContextStore store,
    Map<String, String>? git,
    Future<ContextStore> Function(Directory)? openAdministration,
  ) => ProjectContextService(
    root: root,
    store: store,
    git: GitContextAdapter(parentEnvironment: git ?? noGit),
    recognize: _recognize,
    codec: const ContextCodec(),
    version: '0.0.0-prueba',
    now: () => DateTime.utc(2026, 10, 25, 12),
    newId: newId,
    openAdministration: openAdministration,
  );

  Future<RecognitionReport> _recognize(
    ReportBudgetProfile profile,
    List<AuthorizedOmission> omissions,
  ) => recognizeRoot(
    root,
    (r, {required reportLimits, required authorizedOmissions}) =>
        recognizeDartProject(
          r,
          reportLimits: reportLimits,
          authorizedOmissions: authorizedOmissions,
        ),
    budgetProfile: profile,
    authorizedOmissions: omissions,
  );

  /// Tipo y bytes de cada entrada, sin seguir enlaces.
  Map<String, String> snapshot([Directory? of]) {
    final dir = of ?? root;
    return {
      for (final e in dir.listSync(recursive: true, followLinks: false))
        e.path.substring(dir.path.length + 1): switch (e) {
          Link() => 'enlace ${e.targetSync()}',
          File() => 'archivo ${base64.encode(e.readAsBytesSync())}',
          _ => 'directorio',
        },
    };
  }

  ProjectContext savedContext() => const ContextCodec().decodeProject(
    File(path('shipflow/project.json')).readAsBytesSync(),
  );

  void dispose() => base.deleteSync(recursive: true);
}

/// La muerte del proceso en medio de una operación: el servicio no la
/// atrapa, así que no limpia nada.
final class SimulatedCrash extends Error {}

/// Un almacén real que muere después de su escritura número [after]: lo
/// que quedó en disco es lo que un proceso terminado dejaría.
class CrashingStore implements ContextStore {
  CrashingStore(this.real, this.after);

  final ContextStore real;
  final int after;
  var writes = 0;

  void _tick() {
    if (++writes > after) throw SimulatedCrash();
  }

  @override
  Future<void> publishRelative(
    String path,
    List<int> bytes, {
    required String? expectedSha256,
  }) async {
    _tick();
    await real.publishRelative(path, bytes, expectedSha256: expectedSha256);
  }

  @override
  Future<void> removeRelative(
    String path, {
    required String expectedSha256,
  }) async {
    _tick();
    await real.removeRelative(path, expectedSha256: expectedSha256);
  }

  @override
  Future<List<String>> createDirectory(String path) =>
      real.createDirectory(path);

  @override
  Future<void> removeDirectory(String path) async {
    _tick();
    await real.removeDirectory(path);
  }

  @override
  Future<List<int>?> readRelative(String path, {required int maxBytes}) =>
      real.readRelative(path, maxBytes: maxBytes);

  @override
  ContextResource contextLock() => real.contextLock();

  @override
  ContextResource directoryLock() => real.directoryLock();

  @override
  Future<ContextLease> acquirePublication(List<ContextResource> resources) =>
      real.acquirePublication(resources);

  @override
  Future<void> close() async {}
}
