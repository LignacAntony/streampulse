import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/playlist_queue_controller.dart';
import 'playback_queue_sheet.dart';

/// Mini-player de la file d'attente (US-05-04) : pendant du mini-player du
/// direct, avec les contrôles que seule une file justifie (précédent/suivant).
/// Un appui ouvre la file d'attente, la croix l'abandonne.
class QueueMiniPlayer extends StatelessWidget {
  const QueueMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<PlaylistQueueController>();
    final track = queue.currentTrack;
    if (!queue.hasQueue || track == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // L'état prime sur le nom de l'artiste : sinon la fin de file ou une erreur
    // passeraient inaperçues (seule l'icône changerait).
    final (String subtitle, Color subtitleColor) = switch (queue.status) {
      PlaybackStatus.ended => ('File d\'attente terminée', colors.error),
      PlaybackStatus.error => ('Lecture impossible', colors.error),
      _ => (
          '${queue.currentIndex + 1}/${queue.tracks.length} · '
              '${track.artist ?? 'Artiste inconnu'}',
          colors.onSurfaceVariant,
        ),
    };

    return Material(
      color: colors.surfaceContainerHighest,
      child: InkWell(
        key: const Key('queue_mini_player'),
        onTap: () => PlaybackQueueSheet.show(context),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.queue_music, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: subtitleColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('queue_mini_previous'),
                onPressed: queue.hasPrevious ? queue.previous : null,
                icon: const Icon(Icons.skip_previous),
                tooltip: 'Piste précédente',
              ),
              _playPause(queue, colors),
              IconButton(
                key: const Key('queue_mini_next'),
                onPressed: queue.hasNext ? queue.next : null,
                icon: const Icon(Icons.skip_next),
                tooltip: 'Piste suivante',
              ),
              IconButton(
                key: const Key('queue_mini_stop'),
                onPressed: queue.stop,
                icon: const Icon(Icons.close),
                tooltip: 'Arrêter',
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playPause(PlaylistQueueController queue, ColorScheme colors) {
    if (queue.isBusy) {
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
    if (queue.hasError || queue.isEnded) {
      icon = Icons.replay;
    } else if (queue.isPlaying) {
      icon = Icons.pause;
    } else {
      icon = Icons.play_arrow;
    }
    return IconButton(
      key: const Key('queue_mini_play_pause'),
      onPressed: queue.togglePlayPause,
      color: colors.primary,
      iconSize: 30,
      icon: Icon(icon),
      tooltip: queue.isPlaying ? 'Pause' : 'Lecture',
    );
  }
}
