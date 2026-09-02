import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../playlists/presentation/providers/playlist_queue_controller.dart';
import '../../domain/entities/recommended_track.dart';

/// Ligne d'une piste recommandée (section « Pour toi », US-09-04). Un appui lance
/// la lecture de toute la liste recommandée à partir d'elle ; le sous-titre
/// affiche la **raison** fournie par le serveur plutôt que l'artiste/la durée.
///
/// Widget partagé : la section « Pour toi » vit dans « Découvrir » (STR-250), et
/// la tuile souligne la piste en cours en lisant la file d'attente app-level.
class RecommendedTrackTile extends StatelessWidget {
  const RecommendedTrackTile({
    super.key,
    required this.recommended,
    required this.onPlay,
  });

  final RecommendedTrack recommended;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final track = recommended.track;
    final isCurrent = context.select<PlaylistQueueController, bool>(
      (queue) => queue.hasQueue && queue.currentTrack?.id == track.id,
    );

    return ListTile(
      key: Key('reco_tile_${track.id}'),
      onTap: onPlay,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colors.surfaceContainerHighest,
        child: Icon(
          isCurrent ? Icons.graphic_eq : Icons.auto_awesome,
          color: isCurrent ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCurrent ? TextStyle(color: colors.primary) : null,
      ),
      subtitle: Text(
        recommended.reason,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}
