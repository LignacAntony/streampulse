import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/audio_player_controller.dart';

/// Mini-player persistant (STR-109) : surface de contrôle in-app du flux en
/// cours, affichée au-dessus de la barre de navigation quand quelque chose joue.
/// Tape → plein écran ; play/pause ; croix → arrêt. Masqué à l'état `idle`.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerController>();
    final now = audio.nowPlaying;
    if (now == null || audio.status == PlaybackStatus.idle) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: colors.surfaceContainerHighest,
      child: InkWell(
        onTap: () => context.push('/stream/${now.streamId}'),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.graphic_eq, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      now.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (now.broadcaster != null && now.broadcaster!.isNotEmpty)
                      Text(
                        now.broadcaster!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              _playPause(audio, colors),
              IconButton(
                onPressed: audio.stop,
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

  Widget _playPause(AudioPlayerController audio, ColorScheme colors) {
    if (audio.isBusy || audio.isReconnecting) {
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
    if (audio.hasError || audio.isEnded) {
      icon = Icons.replay;
    } else if (audio.isPlaying) {
      icon = Icons.pause;
    } else {
      icon = Icons.play_arrow;
    }
    return IconButton(
      onPressed: audio.togglePlayPause,
      color: colors.primary,
      iconSize: 30,
      icon: Icon(icon),
      tooltip: audio.isPlaying ? 'Pause' : 'Lecture',
    );
  }
}
