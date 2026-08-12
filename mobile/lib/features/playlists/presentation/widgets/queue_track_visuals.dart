/// Comment une piste « en cours de lecture » se distingue des autres, partagé
/// par la feuille de file d'attente et l'écran de détail d'une playlist.
///
/// Les deux listes montrent la même file au même moment : si l'une marquait la
/// piste courante autrement que l'autre, l'utilisateur verrait deux réponses
/// différentes à « qu'est-ce qui joue ? ».
library;

import 'package:flutter/material.dart';

/// Numéro de la piste, remplacé par l'égaliseur quand c'est elle qui joue.
Widget queueTrackLeading(
  BuildContext context, {
  required int index,
  required bool isCurrent,
}) {
  final colors = Theme.of(context).colorScheme;
  if (isCurrent) {
    return Icon(Icons.graphic_eq, color: colors.primary);
  }
  return Text(
    '${index + 1}',
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(color: colors.onSurfaceVariant),
  );
}

/// Style du titre : mis en avant pour la piste en cours, par défaut sinon.
TextStyle? queueTrackTitleStyle(BuildContext context, {required bool isCurrent}) {
  if (!isCurrent) return null;
  final theme = Theme.of(context);
  return theme.textTheme.titleMedium?.copyWith(
    color: theme.colorScheme.primary,
    fontWeight: FontWeight.w600,
  );
}
