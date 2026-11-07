import 'dart:convert';

import 'package:core/core.dart';

import '../cli_response.dart';
import 'basis_human.dart';

/// La respuesta de [result]: una línea JSON o la vista humana, ambas del
/// mismo resultado y con los mismos efectos; mostrar no ejecuta acciones.
CliResponse presentBasis(
  BasisResponse result, {
  required bool json,
  required BasisLimits limits,
}) => CliResponse(
  exitCode: result.exitCode,
  channel: CliOutputChannel.stdout,
  payload: json ? '${jsonEncode(result.toJson())}\n' : renderBasisHuman(result),
);
