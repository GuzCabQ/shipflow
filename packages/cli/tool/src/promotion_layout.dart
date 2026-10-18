import 'dart:io';

final class PromotionException implements Exception {
  const PromotionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Los archivos que una promoción usa dentro del bin-dir. Ninguno se sigue si
/// es un enlace simbólico.
final class PromotionLayout {
  PromotionLayout(Directory bin) : bin = bin.absolute;

  static const installedName = 'shipflow';
  static const candidateName = '.shipflow.candidate';
  static const previousName = '.shipflow.previous';
  static const manifestName = '.shipflow.promote.json';
  static const manifestDraftName = '.shipflow.promote.json.tmp';
  static const lockName = '.shipflow.promote.lock';

  final Directory bin;

  File get installed => _file(installedName);
  File get candidate => _file(candidateName);
  File get previous => _file(previousName);
  File get manifest => _file(manifestName);
  File get manifestDraft => _file(manifestDraftName);
  File get lock => _file(lockName);

  List<File> get all => [
    installed,
    candidate,
    previous,
    manifest,
    manifestDraft,
    lock,
  ];

  File _file(String name) => File('${bin.path}/$name');
}

PromotionException inconsistentState(PromotionLayout layout, String detail) =>
    PromotionException(
      'el estado de ${layout.bin.path} no coincide con su manifiesto: '
      '$detail; no se toca nada hasta revisarlo.',
    );
