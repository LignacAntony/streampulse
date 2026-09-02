import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/mini_player_shell.dart';
import '../providers/playlist_queue_controller.dart';
import 'queue_progress.dart';
import '../../../../core/widgets/accessible_icon_button.dart';

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

    // L'état prime sur le nom de l'artiste : sinon la fin de file ou une erreur
    // passeraient inaperçues (seule l'icône changerait).
    final (String subtitle, Color subtitleColor) = switch (queue.status) {
      PlaybackStatus.ended => ('File d\'attente terminée', colors.error),
      PlaybackStatus.error => ('Lecture impossible', colors.error),
      PlaybackStatus.reconnecting => ('Reconnexion…', colors.onSurfaceVariant),
      // Rang dans l'ordre de lecture, pas dans la playlist : en aléatoire, la
      // 1re piste jouée n'est pas la 1re de la liste.
      _ => (
          '${queue.positionInOrder + 1}/${queue.tracks.length} · '
              '${track.artist ?? 'Artiste inconnu'}',
          colors.onSurfaceVariant,
        ),
    };

    return MiniPlayerShell(
      key: const Key('queue_mini_player'),
      icon: Icons.queue_music,
      title: track.title,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      // Avancement de la piste (STR-230) : un trait, pas de manipulation — le
      // bandeau fait 60 px, viser un pouce dessus serait une loterie. La barre
      // manipulable vit dans la file d'attente, à un appui d'ici.
      progress: const QueueProgressLine(),
      onTap: () => context.push('/queue'),
      actions: [
        AccessibleIconButton(
          key: const Key('queue_mini_previous'),
          icon: Icons.skip_previous,
          label: 'Piste précédente',
          onPressed: queue.hasPrevious ? queue.previous : null,
        ),
        PlaybackToggleButton(
          key: const Key('queue_mini_play_pause'),
          isBusy: queue.isBusy || queue.isReconnecting,
          showReplay: queue.hasError || queue.isEnded,
          isPlaying: queue.isPlaying,
          onPressed: queue.togglePlayPause,
        ),
        AccessibleIconButton(
          key: const Key('queue_mini_next'),
          icon: Icons.skip_next,
          label: 'Piste suivante',
          onPressed: queue.hasNext ? queue.next : null,
        ),
        AccessibleIconButton(
          key: const Key('queue_mini_stop'),
          icon: Icons.close,
          label: 'Arrêter la lecture',
          onPressed: queue.stop,
        ),
      ],
    );
  }
}
