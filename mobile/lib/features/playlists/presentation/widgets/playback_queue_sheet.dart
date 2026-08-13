import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/playlist_queue_controller.dart';
import '../track_labels.dart';
import 'queue_track_visuals.dart';

/// File d'attente en cours de lecture (US-05-04), en feuille modale.
///
/// Rend visible ce que le mini-player ne peut pas montrer : les pistes à venir,
/// celles déjà passées, et laquelle joue. Un appui sur n'importe quelle ligne y
/// saute directement.
class PlaybackQueueSheet extends StatelessWidget {
  const PlaybackQueueSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => const PlaybackQueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<PlaylistQueueController>();
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    // La file peut se vider pendant que la feuille est ouverte (arrêt depuis la
    // notification, ou un direct qui reprend le lecteur) : on la referme plutôt
    // que d'afficher une liste vide sans explication.
    if (!queue.hasQueue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        // On vise **cette** route et pas le sommet de la pile : une autre route
        // a pu être poussée par-dessus entre-temps, et un `maybePop()` nu la
        // fermerait à la place de la feuille. Quand la feuille est au sommet on
        // passe quand même par `maybePop` pour garder l'animation de sortie.
        final route = ModalRoute.of(context);
        final navigator = Navigator.of(context);
        if (route == null || route.isCurrent) {
          navigator.maybePop();
        } else {
          navigator.removeRoute(route);
        }
      });
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('File d\'attente'),
            subtitle: Text(
              queue.sourceName ?? 'Lecture en cours',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              '${queue.positionInOrder + 1}/${queue.tracks.length}',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          // Les modes vivent ici plutôt que sur le mini-player : celui-ci n'a
          // que 60 px de haut et porte déjà quatre boutons, et c'est la file
          // affichée juste dessous qui rend leur effet lisible.
          const _QueueModeBar(),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              key: const Key('playback_queue_list'),
              shrinkWrap: true,
              itemCount: queue.playbackOrder.length,
              itemBuilder: (context, position) {
                // La liste suit l'**ordre de lecture** : en aléatoire, elle
                // annonce donc la suite réelle et non l'ordre de la playlist.
                final index = queue.playbackOrder[position];
                final track = queue.tracks[index];
                final isCurrent = index == queue.currentIndex;
                return ListTile(
                  key: Key('queue_item_${track.id}'),
                  selected: isCurrent,
                  leading: queueTrackLeading(
                    context,
                    index: position,
                    isCurrent: isCurrent,
                  ),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: queueTrackTitleStyle(context, isCurrent: isCurrent),
                  ),
                  subtitle: Text(
                    trackSubtitle(
                      artist: track.artist,
                      durationS: track.durationS,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () =>
                      context.read<PlaylistQueueController>().skipTo(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Modes de lecture de la file (US-05-05) : aléatoire et répétition.
///
/// Deux boutons **libellés** plutôt que deux icônes nues : un mode actif se
/// distingue déjà par sa couleur, mais « répéter la piste » et « répéter la
/// file » ne se devinent pas d'une icône barrée d'un « 1 ».
class _QueueModeBar extends StatelessWidget {
  const _QueueModeBar();

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<PlaylistQueueController>();

    final (IconData repeatIcon, String repeatLabel) = switch (queue.repeatMode) {
      QueueRepeatMode.off => (Icons.repeat, 'Répétition'),
      QueueRepeatMode.all => (Icons.repeat, 'Répéter la file'),
      QueueRepeatMode.one => (Icons.repeat_one, 'Répéter la piste'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              buttonKey: const Key('queue_shuffle_button'),
              icon: Icons.shuffle,
              label: 'Aléatoire',
              active: queue.shuffleEnabled,
              tooltip: queue.shuffleEnabled
                  ? 'Désactiver la lecture aléatoire'
                  : 'Activer la lecture aléatoire',
              onPressed: () =>
                  context.read<PlaylistQueueController>().toggleShuffle(),
            ),
          ),
          Expanded(
            child: _ModeButton(
              buttonKey: const Key('queue_repeat_button'),
              icon: repeatIcon,
              label: repeatLabel,
              active: queue.repeatMode != QueueRepeatMode.off,
              tooltip: 'Changer le mode de répétition',
              onPressed: () =>
                  context.read<PlaylistQueueController>().cycleRepeat(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: active ? colors.primary : colors.onSurfaceVariant,
        ),
        icon: Icon(icon),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
