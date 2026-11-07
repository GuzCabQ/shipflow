/// Los textos de la vista humana de assess, por código estable. Nunca un
/// mensaje del sistema, del parser ni de Git.
const assessmentMessages = <String, String>{
  'invalid_root': 'La carpeta no se puede inspeccionar.',
  'unexpected': 'Error inesperado de Shipflow; no se publicó nada.',
  'io_failure': 'No se pudo leer o escribir un archivo propio.',
  'busy': 'Otra operación de Shipflow está publicando; vuelve a intentarlo.',
  'concurrent_change': 'Algo cambió durante la operación; no se publicó nada.',
  'source_changed':
      'Una fuente cambió entre la observación y la publicación: se conservó '
      'el levantamiento anterior.',
  'assessment_recovery_pending': 'Hay una publicación de assess sin terminar.',
  'context_recovery_pending': 'Hay una operación de init sin terminar.',
  'basis_recovery_pending':
      'Hay una publicación de la base guiada sin terminar: no se observa '
      'hasta recuperarla.',
  'recovery_conflict':
      'Un archivo propio no coincide con ninguna versión esperada: se '
      'conserva todo para reconciliarlo a mano.',
  'assessment_invalid':
      'shipflow/assessment.json no cumple su formato y no se usa ni se '
      'sobrescribe: muévelo fuera de shipflow como respaldo y vuelve a '
      'ejecutar assess.',
  'assessment_context_mismatch':
      'El levantamiento cita este contexto, pero sus unidades o vínculos no '
      'corresponden: no se usa.',
  'project_identity': 'El levantamiento es de otro proyecto: no se usa.',
  'context_invalid': 'El contexto inicial no cumple su formato.',
  'context_incompatible':
      'Otro contrato produjo el contexto inicial: actualízalo primero.',
  'state_occupied':
      'La carpeta shipflow tiene contenido ajeno: no se usa ni se sobrescribe.',
  'state_invalid':
      'Un archivo de shipflow no se puede acreditar como propio: se conserva.',
  'context_absent': 'No hay un contexto inicial: inicializa primero.',
  'context_stale':
      'El contexto inicial ya no corresponde a los manifiestos: actualízalo '
      'antes de observar.',
  'context_unverified':
      'No se pudo comprobar el contexto inicial con el perfil pedido.',
  'choice_required':
      'Falta elegir cómo conservar el contexto en este repositorio.',
  'sharing_conflict': 'La conservación elegida no está aplicada según Git.',
  'git_unavailable':
      'No se pudo consultar Git para comprobar la conservación elegida.',
  'assessment_absent': 'Todavía no hay un levantamiento guardado.',
  'previous_absent': 'No hay una revisión anterior guardada.',
  'assessment_stale':
      'Cambiaron insumos del levantamiento: observar de nuevo crea una '
      'revisión nueva y conserva esta como anterior.',
  'assessment_unverified':
      'No se pudieron volver a leer todos sus insumos: no se afirma que siga '
      'vigente.',
  'coverage_partial':
      'La cobertura es parcial: lo que no se analizó o no se resolvió no '
      'cuenta como ausencia de referencias.',
  'assessment_limit':
      'El levantamiento no cabe entero en el perfil pedido: no se publicó.',
  'git_absent':
      'Sin Git: el levantamiento queda en esta copia y respaldarlo depende de '
      'ti.',
  'comparison_unavailable':
      'Sin comparación con la anterior: no son dos observaciones completas de '
      'la misma base.',
  'context_basis_unavailable':
      'El contexto inicial cambió: el vínculo con el que se observó no se '
      'vuelve a comprobar.',
  'revision_retired':
      'Se dejó de conservar la revisión más antigua: las anteriores requieren '
      'Git o un respaldo.',
  'recovery_aborted':
      'Las fuentes cambiaron: no se publicó el candidato y se conservó lo '
      'anterior.',
};

/// Qué falta en la cobertura, por código del plugin.
const assessmentGaps = <String, String>{
  'source_unreadable': 'fuentes que no se pudieron leer',
  'source_changed': 'fuentes que cambiaron mientras se leían',
  'source_too_large': 'fuentes mayores que el máximo por archivo',
  'source_budget': 'fuentes fuera del presupuesto del perfil',
  'claims_budget': 'archivos con más referencias de las que admite el perfil',
  'parse_failed': 'archivos que el parser no aceptó',
  'parse_deadline': 'archivos que no se terminaron de analizar a tiempo',
  'observation_deadline': 'fuentes que quedaron sin mirar por tiempo',
  'entries_budget': 'directorios fuera del presupuesto de entradas',
  'depth_budget': 'directorios más profundos que el máximo',
  'directory_unreadable': 'directorios que no se pudieron listar',
  'symlink_not_followed': 'enlaces que no se siguen',
  'special_file_skipped': 'entradas especiales que no se abren',
  'outside_units': 'archivos fuera de las unidades reconocidas',
  'path_not_representable': 'nombres que no se pueden representar',
  'reference_unresolved': 'archivos con referencias sin resolver',
};

/// La finalidad de cada acción propuesta.
const assessmentPurposes = <String, String>{
  'inspect_saved': 'consultar el levantamiento guardado',
  'inspect_saved_detail': 'ver el detalle completo en JSON',
  'observe_again': 'observar de nuevo',
  'recover_publication': 'terminar o deshacer la publicación interrumpida',
  'initialize_context': 'inicializar el contexto',
  'refresh_context': 'actualizar el contexto inicial',
  'recover_context': 'terminar la operación de init',
  'recover_basis': 'completar la publicación aceptada de la base',
  'choose_sharing': 'elegir cómo conservar el contexto',
  'widen_budget': 'repetir con el perfil ampliado',
};
