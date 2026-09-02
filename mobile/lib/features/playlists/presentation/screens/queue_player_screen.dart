import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/accessible_icon_button.dart';
import '../../../../core/widgets/volume_slider.dart';
import '../../domain/entities/track.dart';
import '../providers/playlist_queue_controller.dart';
import '../track_labels.dart';
import '../widgets/queue_progress.dart';
import '../widgets/queue_track_visuals.dart';

/// Lecteur de file d'attente **plein écran** (US-05-04), pendant du lecteur du
/// direct ([StreamPlayerScreen]) : mêmes repères visuels, mêmes contrôles de
/// transport, poussé comme une route et non affiché en feuille partielle.
///
/// Avant, la file s'ouvrait dans une `showModalBottomSheet` bornée à la hauteur
/// de son contenu et **sans bouton lecture/pause** : on pouvait voir la file mais
/// pas la piloter. L'écran plein règle les deux : un vrai bloc « en cours » avec
/// lecture/pause/précédent/suivant/aléatoire/répétition, puis la file dessous.
class QueuePlayerScreen extends StatelessWidget {
  const QueuePlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<PlaylistQueueController>();
    final track = queue.currentTrack;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // La file peut se vider pendant que l'écran est ouvert (arrêt depuis la
    // notification, ou un direct qui reprend le lecteur partagé) : on referme la
    // route plutôt que d'afficher un écran vide sans explication — même conduite
    // que l'ancienne feuille.
    if (!queue.hasQueue || track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(context, colors, text, queue),
            const SizedBox(height: 8),
            _nowPlaying(context, colors, text, queue, track),
            const QueueProgressSlider(),
            _transport(context, colors, queue),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: VolumeSlider(showLabel: false),
            ),
            const Divider(height: 1),
            Expanded(child: _queueList(context, queue)),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme colors,
    TextTheme text,
    PlaylistQueueController queue,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          AccessibleIconButton(
            icon: Icons.keyboard_arrow_down,
            label: 'Réduire le lecteur',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'File d\'attente',
                  style: text.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  queue.sourceName ?? 'Lecture en cours',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Contrepoids symétrique de la flèche : garde le titre centré.
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _nowPlaying(
    BuildContext context,
    ColorScheme colors,
    TextTheme text,
    PlaylistQueueController queue,
    Track track,
  ) {
    final (String subtitle, Color subtitleColor) = switch (queue.status) {
      PlaybackStatus.ended => ('File d\'attente terminée', colors.error),
      PlaybackStatus.error => ('Lecture impossible', colors.error),
      PlaybackStatus.reconnecting => ('Reconnexion…', colors.onSurfaceVariant),
      _ => (
          trackSubtitle(artist: track.artist, durationS: track.durationS),
          colors.onSurfaceVariant,
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primary, colors.primary.withValues(alpha: 0.4)],
              ),
            ),
            child: Icon(Icons.queue_music, size: 44, color: colors.onPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(color: subtitleColor),
          ),
          const SizedBox(height: 4),
          Text(
            // Rang dans l'ordre de lecture, pas dans la playlist : en aléatoire,
            // la 1re piste jouée n'est pas la 1re de la liste.
            '${queue.positionInOrder + 1}/${queue.tracks.length}',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _transport(
    BuildContext context,
    ColorScheme colors,
    PlaylistQueueController queue,
  ) {
    final (IconData repeatIcon, String repeatLabel) = switch (queue.repeatMode) {
      QueueRepeatMode.off => (Icons.repeat, 'Activer la répétition'),
      QueueRepeatMode.all => (Icons.repeat, 'Répéter la file'),
      QueueRepeatMode.one => (Icons.repeat_one, 'Répéter la piste'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          AccessibleIconButton(
            key: const Key('queue_full_shuffle'),
            icon: Icons.shuffle,
            label: queue.shuffleEnabled
                ? 'Désactiver la lecture aléatoire'
                : 'Activer la lecture aléatoire',
            color: queue.shuffleEnabled ? colors.primary : colors.onSurfaceVariant,
            onPressed: () =>
                context.read<PlaylistQueueController>().toggleShuffle(),
          ),
          AccessibleIconButton(
            key: const Key('queue_full_previous'),
            icon: Icons.skip_previous,
            label: 'Piste précédente',
            iconSize: 36,
            onPressed: queue.hasPrevious ? queue.previous : null,
          ),
          _PlayButton(queue: queue),
          AccessibleIconButton(
            key: const Key('queue_full_next'),
            icon: Icons.skip_next,
            label: 'Piste suivante',
            iconSize: 36,
            onPressed: queue.hasNext ? queue.next : null,
          ),
          AccessibleIconButton(
            key: const Key('queue_full_repeat'),
            icon: repeatIcon,
            label: repeatLabel,
            color: queue.repeatMode != QueueRepeatMode.off
                ? colors.primary
                : colors.onSurfaceVariant,
            onPressed: () =>
                context.read<PlaylistQueueController>().cycleRepeat(),
          ),
        ],
      ),
    );
  }

  Widget _queueList(BuildContext context, PlaylistQueueController queue) {
    return ListView.builder(
      key: const Key('playback_queue_list'),
      itemCount: queue.playbackOrder.length,
      itemBuilder: (context, position) {
        // La liste suit l'**ordre de lecture** : en aléatoire, elle annonce donc
        // la suite réelle et non l'ordre de la playlist.
        final index = queue.playbackOrder[position];
        final track = queue.tracks[index];
        final isCurrent = index == queue.currentIndex;
        return ListTile(
          key: Key('queue_item_${track.id}'),
          selected: isCurrent,
          leading: queueTrackLeading(context, index: position, isCurrent: isCurrent),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: queueTrackTitleStyle(context, isCurrent: isCurrent),
          ),
          subtitle: Text(
            trackSubtitle(artist: track.artist, durationS: track.durationS),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => context.read<PlaylistQueueController>().skipTo(index),
        );
      },
    );
  }
}

/// Gros bouton lecture/pause central, aligné sur celui du direct : jeton
/// d'attente en transition, relance sur un état terminal, pause/lecture sinon.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.queue});

  final PlaylistQueueController queue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = queue.isBusy || queue.isReconnecting;
    final replay = queue.hasError || queue.isEnded;

    final Widget icon;
    if (busy) {
      icon = SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 3, color: colors.onPrimary),
      );
    } else if (replay) {
      icon = Icon(Icons.replay, size: 34, color: colors.onPrimary);
    } else if (queue.isPlaying) {
      icon = Icon(Icons.pause, size: 38, color: colors.onPrimary);
    } else {
      icon = Icon(Icons.play_arrow, size: 38, color: colors.onPrimary);
    }

    final String label;
    if (replay) {
      label = 'Réessayer la lecture';
    } else if (queue.isPlaying) {
      label = 'Mettre en pause';
    } else {
      label = 'Lire';
    }

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colors.primary,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('queue_full_play_pause'),
          customBorder: const CircleBorder(),
          onTap: queue.togglePlayPause,
          child: SizedBox(width: 68, height: 68, child: Center(child: icon)),
        ),
      ),
    );
  }
}
