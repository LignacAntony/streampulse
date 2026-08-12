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
              queue.playlistName ?? 'Playlist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              '${queue.currentIndex + 1}/${queue.tracks.length}',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              key: const Key('playback_queue_list'),
              shrinkWrap: true,
              itemCount: queue.tracks.length,
              itemBuilder: (context, index) {
                final track = queue.tracks[index];
                final isCurrent = index == queue.currentIndex;
                return ListTile(
                  key: Key('queue_item_${track.id}'),
                  selected: isCurrent,
                  leading: queueTrackLeading(
                    context,
                    index: index,
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
