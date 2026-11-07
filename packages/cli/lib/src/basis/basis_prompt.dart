import 'package:core/core.dart';

import '../context/context_prompt.dart';
import 'basis_catalog.dart';
import 'basis_reply.dart';
import 'basis_service.dart';

/// La guía interactiva de la base: prepara, revisa y acepta con el mismo
/// servicio que `--input` y `--accept`.
Future<BasisResponse> guideBasis(
  BasisService service,
  ContextPromptIO io,
) async =>
    (BasisReply(BasisOperation.guide)
          ..outcome = BasisOutcome.choiceRequired
          ..add('choice_required')
          ..addAction(showAction))
        .build();
