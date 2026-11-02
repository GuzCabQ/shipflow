import 'cli_command.dart';

typedef HelpOption = ({List<String> flags, String column, String text});
typedef Help = ({
  String summary,
  List<String> usage,
  List<HelpOption> options,
  String? command,
});

const _budgetText = '[--report-budget=standard|extended]';
const _dryRunUsage = 'shipflow init --dry-run [--json] $_budgetText';
const _initUsages = [
  _dryRunUsage,
  'shipflow init [--sharing=share|local] [--json] $_budgetText',
  'shipflow init --refresh [--sharing=share|local] [--json] $_budgetText',
  'shipflow init --recover [--json] $_budgetText',
];
const _doctorUsage = 'shipflow doctor [--json] $_budgetText';

const helpCommands = [
  (
    name: initCommand,
    text: 'Inicializa el contexto del proyecto o comprueba el guardado.',
  ),
  (
    name: doctorCommand,
    text: 'Consulta el contexto guardado sin modificar nada.',
  ),
];

const _helpOption = (
  flags: ['-h', '--help'],
  column: '-h, --help',
  text: 'Muestra esta ayuda.',
);
const _jsonOption = (
  flags: [jsonFlag],
  column: jsonFlag,
  text: 'Emite una única respuesta JSON; nunca pregunta.',
);
const _budgetOption = (
  flags: ['$reportBudgetFlag=standard', '$reportBudgetFlag=extended'],
  column: '$reportBudgetFlag=standard|extended',
  text:
      'Perfil del reconocimiento de esta invocación: standard, el de omisión, '
      'o extended, que admite uno mayor y puede consumir más recursos. No se '
      'guarda entre invocaciones.',
);

const rootHelp = (
  summary:
      'Shipflow supervisa cambios de software verificables y recuperables.',
  usage: [
    'shipflow [--help] [--json]',
    'shipflow --version [--json]',
    ..._initUsages,
    _doctorUsage,
  ],
  options: [
    _helpOption,
    (
      flags: [versionFlag],
      column: versionFlag,
      text: 'Muestra la versión del ejecutable.',
    ),
    _jsonOption,
  ],
  command: null,
);

const initHelp = (
  summary:
      'Reconoce el proyecto y guarda su contexto inicial en '
      'shipflow/project.json, para reutilizarlo al volver sin repetir '
      'decisiones. Guardar no certifica su salud: no comprueba si compila, si '
      'pasan sus pruebas, su arquitectura ni el SDK instalado. Shipflow no '
      'ejecuta git add, commit ni push.',
  usage: _initUsages,
  options: [
    _helpOption,
    (
      flags: [dryRunFlag],
      column: dryRunFlag,
      text: 'Sólo inspecciona: no escribe, no pregunta ni ejecuta procesos.',
    ),
    (
      flags: [refreshFlag],
      column: refreshFlag,
      text:
          'Reemplaza el contexto guardado por lo observado ahora, si el '
          'reconocimiento es elegible; conserva su identidad.',
    ),
    (
      flags: [recoverFlag],
      column: recoverFlag,
      text:
          'Termina o deshace una operación propia interrumpida; no reinicia '
          'archivos dañados ni ajenos.',
    ),
    (
      flags: ['$sharingFlag=share', '$sharingFlag=local'],
      column: '$sharingFlag=share|local',
      text:
          'Elige sin preguntar: share deja el contexto listo para versionarlo; '
          'local lo excluye con una regla propia en el exclude local de Git, '
          'que en copias de trabajo vinculadas puede alcanzar la misma ruta '
          'en las demás copias de ese repositorio en el equipo.',
    ),
    _jsonOption,
    _budgetOption,
  ],
  command: initCommand,
);

const doctorHelp = (
  summary:
      'Consulta el contexto guardado: su integridad, su vigencia frente a lo '
      'observado ahora, operaciones pendientes y la conservación elegida, y '
      'explica la siguiente acción. Sólo lee: no escribe ni repara.',
  usage: [_doctorUsage],
  options: [_helpOption, _jsonOption, _budgetOption],
  command: doctorCommand,
);
