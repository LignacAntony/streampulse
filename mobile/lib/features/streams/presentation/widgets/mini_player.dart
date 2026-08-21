import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/mini_player_shell.dart';
import '../providers/audio_player_controller.dart';
import '../../../../core/widgets/accessible_icon_button.dart';

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

    // Sous-titre contextuel : l'état (terminé / indisponible / reconnexion)
    // prime sur le nom du diffuseur, sinon le mini-player resterait muet en fin
    // de direct (icône replay seule).
    final (String? subtitle, Color subtitleColor) = switch (audio.status) {
      PlaybackStatus.ended => ('Le direct est terminé', colors.error),
      PlaybackStatus.error => ('Flux indisponible', colors.error),
      PlaybackStatus.reconnecting => ('Reconnexion…', colors.onSurfaceVariant),
      _ => (now.broadcaster, colors.onSurfaceVariant),
    };

    return MiniPlayerShell(
      icon: Icons.graphic_eq,
      title: now.title,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      onTap: () => context.push('/stream/${now.streamId}'),
      actions: [
        PlaybackToggleButton(
          isBusy: audio.isBusy || audio.isReconnecting,
          showReplay: audio.hasError || audio.isEnded,
          isPlaying: audio.isPlaying,
          onPressed: audio.togglePlayPause,
        ),
        AccessibleIconButton(
          icon: Icons.close,
          label: 'Arrêter l\'écoute',
          onPressed: audio.stop,
        ),
      ],
    );
  }
}
