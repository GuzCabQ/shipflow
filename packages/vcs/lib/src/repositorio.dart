/// El repositorio local. **Sabe de `git` y de nada más.**
///
/// No conoce el lenguaje del proyecto, ni el CLI agéntico, ni la forja. Lo
/// primero y lo segundo están sostenidos por reglas de arquitectura; lo tercero
/// por el corte entre `ChangeSink` y `PullRequestSink`.
///
/// **Corre `git` por proceso, con su propia costura.** La que usa el plugin
/// del stack no se puede reusar: `deps-hacia-core` prohíbe que este paquete lo
/// vea, y subir la costura a `core` sería meter procesos en el dominio, que no
/// habla de eso. La duplicación es de treinta líneas y es el precio del corte;
/// compartirla costaría más.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

/// Se lanza cuando `git` no hizo lo que se le pidió.
///
/// **Lleva el comando y lo que dijo.** Un fallo de repositorio sin la salida
/// de la herramienta obliga a reproducirlo a mano para saber qué pasó.
class GitFallo implements Exception {
  final String invocacion;
  final int codigo;
  final String salida;

  const GitFallo(this.invocacion, this.codigo, this.salida);

  @override
  String toString() => 'GitFallo($invocacion → $codigo): $salida';
}

/// Se lanza cuando lo que se pide no se puede commitear.
class RebanadaNoAplicable implements Exception {
  final String reason;
  final String queHacer;
  const RebanadaNoAplicable(this.reason, this.queHacer);

  @override
  String toString() => 'RebanadaNoAplicable: $reason';
}

class RepositorioGit implements ChangeSink {
  /// La raíz del repositorio sobre el que se trabaja.
  final String directorio;

  /// El ejecutable. **Es inyectable solo para poder probar que su ausencia se
  /// nota**: una herramienta que no está no puede leerse como que no había
  /// nada que hacer.
  final String programa;

  const RepositorioGit({required this.directorio, this.programa = 'git'});

  Future<ProcessResult> _git(List<String> args) async {
    final ProcessResult r;
    try {
      r = await Process.run(programa, args,
          workingDirectory: directorio,
          stdoutEncoding: utf8,
          stderrEncoding: utf8);
    } on ProcessException catch (e) {
      throw GitFallo(
          '$programa ${args.join(" ")}', -1, '${e.message} (${e.executable})');
    }
    return r;
  }

  /// Corre `git` y **exige que haya salido bien**. Un código distinto de cero
  /// que se ignora es un cambio que se cree hecho y no está.
  Future<String> _exigir(List<String> args) async {
    final r = await _git(args);
    if (r.exitCode != 0) {
      throw GitFallo('$programa ${args.join(" ")}', r.exitCode,
          '${r.stdout}${r.stderr}'.trim());
    }
    return (r.stdout as String).trim();
  }

  @override
  Future<void> useBranch(String name) async {
    if (name.trim().isEmpty) {
      throw const RebanadaNoAplicable('El nombre de rama está vacío.',
          'Dale un nombre; una rama sin nombre no se puede retomar después.');
    }
    // **Idempotente**: la orquestación la pide al empezar y `--resume` la
    // vuelve a pedir. Que la segunda vez falle rompería la reanudación que
    // ADR-014 exige.
    final existe = await _git(['rev-parse', '--verify', '--quiet', name]);
    await _exigir(
        existe.exitCode == 0 ? ['switch', name] : ['switch', '--create', name]);
  }

  @override
  Future<String> apply(PullRequestSlice slice) async {
    if (slice.files.isEmpty) {
      throw const RebanadaNoAplicable(
          'La rebanada no nombra ningún archivo.',
          'Un commit vacío afirma un cambio que no existe. Poné los archivos '
              'en la rebanada, o no la apliques.');
    }
    if (slice.intent.trim().isEmpty) {
      throw const RebanadaNoAplicable(
          'La rebanada no dice por qué existe.',
          'El `intent` es lo que ADR-014 llama intención, y es el mensaje del '
              'commit: sin él nadie puede revisar por qué se hizo.');
    }

    await _exigir(['add', '--', ...slice.files]);

    // **`-- <rutas>` es la cláusula 1 hecha comando.** Sin eso, `git commit`
    // se lleva lo que hubiera quedado en el índice de antes, y el artefacto de
    // revisión declararía cubiertos cambios que nadie planeó. Está medido: con
    // rutas explícitas, un archivo staged de antes queda afuera.
    await _exigir(['commit', '--message', slice.intent, '--', ...slice.files]);

    return _exigir(['rev-parse', 'HEAD']);
  }

  /// La rama actual.
  Future<String> get ramaActual => _exigir(['branch', '--show-current']);

  /// Si el árbol tiene cambios sin commitear.
  Future<bool> get sucio async =>
      (await _exigir(['status', '--porcelain'])).isNotEmpty;
}
