import 'package:flutter/material.dart';
import 'accessible_icon_button.dart';

/// Coquille commune aux mini-players (direct STR-109 et file d'attente
/// US-05-04) : bandeau de 60 px au-dessus de la navigation, icône, titre et
/// sous-titre d'état, puis les actions propres à la source.
///
/// Les deux surfaces n'ont ni les mêmes contrôles (le direct n'a pas de
/// précédent/suivant) ni la même destination au tap, mais exactement la même
/// enveloppe. La partager évite de faire évoluer deux bandeaux en parallèle et
/// de les laisser diverger visuellement.
class MiniPlayerShell extends StatelessWidget {
  const MiniPlayerShell({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    required this.actions,
    this.subtitle,
    this.subtitleColor,
    this.progress,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// Boutons de transport, dans l'ordre d'affichage. Fournis par l'appelant :
  /// ils dépendent de ce qui joue.
  final List<Widget> actions;

  /// État en cours (« Reconnexion… », « File d'attente terminée ») ou métadonnée
  /// (diffuseur, position dans la file). Masqué si vide.
  final String? subtitle;
  final Color? subtitleColor;

  /// Trait d'avancement collé sous le bandeau (STR-230). Fourni par la file
  /// d'attente ; le direct le laisse nul — un flux live n'a pas de position à
  /// montrer, c'est déjà pour ça que sa notification masque sa barre.
  final Widget? progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = subtitle;
    final line = progress;

    return Material(
      color: colors.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(icon, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (status != null && status.isNotEmpty)
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: subtitleColor ?? colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                  const SizedBox(width: 4),
                ],
              ),
            ),
            ?line,
          ],
        ),
      ),
    );
  }
}

/// Bouton lecture/pause des mini-players : jeton d'attente pendant une
/// transition, flèche de relance sur un état terminal, pause/lecture sinon.
///
/// Les trois cas se décidaient à l'identique dans les deux mini-players ; les
/// séparer laissait la porte ouverte à un état traité d'un côté et pas de
/// l'autre (c'est arrivé pour « reconnexion »).
class PlaybackToggleButton extends StatelessWidget {
  const PlaybackToggleButton({
    super.key,
    required this.isBusy,
    required this.showReplay,
    required this.isPlaying,
    required this.onPressed,
  });

  /// Transition en cours (chargement, mise en mémoire tampon, reconnexion).
  final bool isBusy;

  /// État terminal (fin de direct, fin de file, erreur) : l'appui relance.
  final bool showReplay;
  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final IconData icon;
    if (showReplay) {
      icon = Icons.replay;
    } else if (isPlaying) {
      icon = Icons.pause;
    } else {
      icon = Icons.play_arrow;
    }
    // Le libellé décrit l'ACTION, pas l'état ni l'icône : annoncer « Pause »
    // sur un flux à l'arrêt laisse croire que l'appui met en pause.
    final String label;
    if (showReplay) {
      label = 'Réessayer la lecture';
    } else if (isPlaying) {
      label = 'Mettre en pause';
    } else {
      label = 'Lire';
    }
    return AccessibleIconButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      color: Theme.of(context).colorScheme.primary,
      iconSize: 30,
    );
  }
}
