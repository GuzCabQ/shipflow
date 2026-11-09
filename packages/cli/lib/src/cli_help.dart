import 'command/cli_command.dart';

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
const _assessUsages = [
  'shipflow assess [--json] $_budgetText',
  'shipflow assess --show [--json] $_budgetText',
  'shipflow assess --show --previous [--json] $_budgetText',
  'shipflow assess --recover [--json] $_budgetText',
];

const _bootstrapUsages = [
  'shipflow bootstrap [--json] $_budgetText',
  'shipflow bootstrap --show [--scope <ruta> | --history | --draft] [--json] '
      '$_budgetText',
  'shipflow bootstrap --input <archivo.json|-> [--json] $_budgetText',
  'shipflow bootstrap --accept <huella> [--json] $_budgetText',
  'shipflow bootstrap --discard <huella> [--json] $_budgetText',
  'shipflow bootstrap --recover [--json] $_budgetText',
];

const helpCommands = [
  (
    name: initCommand,
    text: 'Inicializa el contexto del proyecto o comprueba el guardado.',
  ),
  (
    name: doctorCommand,
    text: 'Consulta el contexto guardado sin modificar nada.',
  ),
  (
    name: assessCommand,
    text:
        'Observa las referencias del código y guarda o consulta su '
        'levantamiento.',
  ),
  (
    name: bootstrapCommand,
    text:
        'Guarda y consulta las decisiones aceptadas del proyecto y lo que '
        'falta aclarar.',
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
    ..._assessUsages,
    ..._bootstrapUsages,
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

const assessHelp = (
  summary:
      'Observa las referencias del código (import, export y part) y guarda '
      'un levantamiento en shipflow/assessment.json, separado del contexto '
      'de shipflow/project.json, con su evidencia, su cobertura y sus '
      'límites. Consultarlo comprueba si sigue vigente sin volver a '
      'analizar. Guardar no certifica la salud del proyecto: no ejecuta '
      'pruebas ni analiza llamadas, y no ejecuta git add, commit ni push.',
  usage: _assessUsages,
  options: [
    _helpOption,
    (
      flags: [showFlag],
      column: showFlag,
      text:
          'Muestra el levantamiento guardado y comprueba su vigencia, sin '
          'analizar ni escribir.',
    ),
    (
      flags: [previousFlag],
      column: previousFlag,
      text:
          'Con --show, la revisión anterior como historia: no se certifica '
          'vigente.',
    ),
    (
      flags: [recoverFlag],
      column: recoverFlag,
      text:
          'Termina o deshace una publicación propia interrumpida; no repara '
          'archivos dañados ni ajenos.',
    ),
    _jsonOption,
    _budgetOption,
  ],
  command: assessCommand,
);

const bootstrapHelp = (
  summary:
      'Guarda en shipflow/basis.json las decisiones del proyecto que una '
      'persona acepta, sus fuentes y lo que falta aclarar, con su historia. '
      'Preparar no acepta: aceptar exige la huella exacta del borrador '
      'revisado. La autoridad es local y declarada, sin autenticación; una '
      'fuente sin cambios no certifica que la decisión sea correcta, y una '
      'base vacía no significa que el proyecto no tenga reglas. No ejecuta '
      'git add, commit ni push.',
  usage: _bootstrapUsages,
  options: [
    _helpOption,
    (
      flags: [showFlag],
      column: showFlag,
      text: 'Consulta la base aceptada, sin escribir.',
    ),
    (
      flags: [scopeFlag],
      column: '$scopeFlag <ruta>',
      text:
          'Con --show: reglas globales, las de esa ruta y los pendientes de '
          'ámbito desconocido. «.» es la consulta global.',
    ),
    (
      flags: [historyFlag],
      column: historyFlag,
      text: 'Con --show: las aceptaciones en orden, sin releer soportes.',
    ),
    (
      flags: [draftFlag],
      column: draftFlag,
      text: 'Con --show: el borrador guardado, que todavía no está aceptado.',
    ),
    (
      flags: [inputFlag],
      column: '$inputFlag <archivo.json|->',
      text:
          'Prepara un borrador desde JSON; «-» lee la entrada estándar. '
          'Nunca acepta.',
    ),
    (
      flags: [acceptFlag],
      column: '$acceptFlag <huella>',
      text: 'Acepta sólo el borrador con esa huella exacta.',
    ),
    (
      flags: [discardFlag],
      column: '$discardFlag <huella>',
      text: 'Descarta ese borrador; nunca retira decisiones aceptadas.',
    ),
    (
      flags: [recoverFlag],
      column: recoverFlag,
      text:
          'Completa o aborta una publicación ya aceptada que quedó a medias; '
          'no crea una aceptación nueva.',
    ),
    _jsonOption,
    _budgetOption,
  ],
  command: bootstrapCommand,
);
