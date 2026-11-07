import 'package:core/core.dart';

import 'assessment_grammar.dart';
import 'basis/basis_grammar.dart';
import 'cli_grammar.dart';

const initCommand = 'init';
const doctorCommand = 'doctor';
const assessCommand = 'assess';
const bootstrapCommand = 'bootstrap';
const showFlag = '--show';
const previousFlag = '--previous';
const refreshFlag = '--refresh';
const recoverFlag = '--recover';
const sharingFlag = '--sharing';
const jsonFlag = '--json';
const versionFlag = '--version';
const dryRunFlag = '--dry-run';
const helpFlags = {'-h', '--help'};
const reportBudgetFlag = '--report-budget';
const scopeFlag = '--scope';
const historyFlag = '--history';
const draftFlag = '--draft';
const inputFlag = '--input';
const acceptFlag = '--accept';
const discardFlag = '--discard';

/// De qué ayuda se trata, y adónde apunta un error de uso.
enum HelpTopic { root, init, doctor, assess, bootstrap }

/// Lo que los argumentos piden. El token exacto `--json` elige la respuesta
/// estructurada aunque otro token sea inválido.
sealed class CliCommand {
  const CliCommand({required this.json});

  final bool json;
}

/// Lo que se responde sin mirar el proyecto.
sealed class StaticCommand extends CliCommand {
  const StaticCommand({required super.json});
}

final class ShowHelp extends StaticCommand {
  const ShowHelp(this.topic, {required super.json});

  final HelpTopic topic;
}

final class ShowVersion extends StaticCommand {
  const ShowVersion({required super.json});
}

final class RejectUsage extends StaticCommand {
  const RejectUsage(this.problem, this.topic, {required super.json});

  /// Ya acotado a una línea.
  final String problem;
  final HelpTopic topic;
}

/// Cuánto reporte admite una invocación. Vive sólo en ella: no se guarda ni
/// se lee del entorno.
enum ReportBudgetProfile { standard, extended }

final class RunInitDryRun extends CliCommand {
  const RunInitDryRun({
    required super.json,
    this.budgetProfile = ReportBudgetProfile.standard,
  });

  final ReportBudgetProfile budgetProfile;
}

/// Un comando que lee y, salvo doctor, publica el contexto persistente.
sealed class RunContext extends CliCommand {
  const RunContext({
    required super.json,
    this.budgetProfile = ReportBudgetProfile.standard,
  });

  final ReportBudgetProfile budgetProfile;
}

/// `init`: primera incorporación, o verificación del contexto guardado.
final class RunInit extends RunContext {
  const RunInit({required super.json, super.budgetProfile, this.sharing});

  final SharingChoice? sharing;
}

/// `init --refresh`: reobserva y publica un reconocimiento elegible.
final class RunInitRefresh extends RunContext {
  const RunInitRefresh({
    required super.json,
    super.budgetProfile,
    this.sharing,
  });

  final SharingChoice? sharing;
}

/// `init --recover`: termina o deshace una operación propia.
final class RunInitRecover extends RunContext {
  const RunInitRecover({required super.json, super.budgetProfile});
}

/// `doctor`: sólo lee y explica.
final class RunDoctor extends RunContext {
  const RunDoctor({required super.json, super.budgetProfile});
}

/// `assess`: genera, consulta, consulta la anterior o recupera. Nunca
/// pregunta; `--json` sólo cambia la forma de la respuesta.
final class RunAssessment extends CliCommand {
  const RunAssessment({
    required super.json,
    required this.action,
    this.previous = false,
    this.budgetProfile = ReportBudgetProfile.standard,
  });

  final AssessmentOperation action;

  /// Sólo con `--show`: la revisión anterior, como historia.
  final bool previous;
  final ReportBudgetProfile budgetProfile;
}

/// `bootstrap`: guía, prepara, consulta, acepta, descarta o recupera la
/// base guiada. Sin operación explícita es la guía, que sólo pregunta en
/// una terminal.
final class RunBootstrap extends CliCommand {
  const RunBootstrap({
    required super.json,
    required this.operation,
    this.scope,
    this.history = false,
    this.draft = false,
    this.input,
    this.digest,
    this.profile = BasisProfile.standard,
  });

  final BasisOperation operation;

  /// Sólo con `--show`: la ruta consultada; `.` es la consulta global.
  final String? scope;
  final bool history;
  final bool draft;

  /// Sólo con `--input`: el archivo, o `-` para la entrada estándar.
  final String? input;

  /// Sólo con `--accept` o `--discard`: la huella exacta del borrador.
  final String? digest;
  final BasisProfile profile;
}

const _root = Grammar({versionFlag, ...helpFlags});
const _init = Grammar(
  {dryRunFlag, refreshFlag, recoverFlag, ...helpFlags},
  acceptsBudget: true,
  acceptsSharing: true,
);
const _doctor = Grammar(helpFlags, acceptsBudget: true);

/// Decide el comando sólo a partir de [arguments]: no lee nada más.
CliCommand parseCliCommand(List<String> arguments) {
  final json = arguments.contains(jsonFlag);
  if (arguments.isNotEmpty && arguments.first == initCommand) {
    return _parseInit(arguments.sublist(1), json: json);
  }
  if (arguments.isNotEmpty && arguments.first == doctorCommand) {
    return _parseDoctor(arguments.sublist(1), json: json);
  }
  if (arguments.isNotEmpty && arguments.first == assessCommand) {
    return parseAssess(arguments.sublist(1), json: json);
  }
  if (arguments.isNotEmpty && arguments.first == bootstrapCommand) {
    return parseBootstrap(arguments.sublist(1), json: json);
  }
  if (_root.firstProblem(arguments) case final problem?) {
    return RejectUsage(problem, HelpTopic.root, json: json);
  }
  if (arguments.contains(versionFlag)) return ShowVersion(json: json);
  return ShowHelp(HelpTopic.root, json: json);
}

CliCommand _parseInit(List<String> options, {required bool json}) {
  if (_init.firstProblem(options) case final problem?) {
    return RejectUsage(problem, HelpTopic.init, json: json);
  }
  if (options.any(helpFlags.contains)) {
    return ShowHelp(HelpTopic.init, json: json);
  }
  final profile = budgetProfileIn(options);
  final sharing = sharingIn(options);
  if (options.contains(dryRunFlag)) {
    return RunInitDryRun(json: json, budgetProfile: profile);
  }
  if (options.contains(refreshFlag)) {
    return RunInitRefresh(json: json, budgetProfile: profile, sharing: sharing);
  }
  if (options.contains(recoverFlag)) {
    return RunInitRecover(json: json, budgetProfile: profile);
  }
  return RunInit(json: json, budgetProfile: profile, sharing: sharing);
}

CliCommand _parseDoctor(List<String> options, {required bool json}) {
  if (_doctor.firstProblem(options) case final problem?) {
    return RejectUsage(problem, HelpTopic.doctor, json: json);
  }
  if (options.any(helpFlags.contains)) {
    return ShowHelp(HelpTopic.doctor, json: json);
  }
  return RunDoctor(json: json, budgetProfile: budgetProfileIn(options));
}
