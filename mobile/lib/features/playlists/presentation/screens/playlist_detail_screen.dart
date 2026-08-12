import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../data/datasources/playlist_remote_data_source.dart';
import '../../data/repositories/playlist_repository_impl.dart';
import '../../domain/entities/playlist_track.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../providers/playlist_detail_controller.dart';
import '../providers/playlist_queue_controller.dart';
import '../track_labels.dart';
import '../widgets/queue_track_visuals.dart';
import '../widgets/track_picker_sheet.dart';

/// Écran de détail d'une playlist (US-05-03) : pistes ordonnées, ajout depuis la
/// bibliothèque, retrait, et réorganisation par drag-and-drop.
///
/// `ChangeNotifierProvider` local à l'écran (même raison que `PlaylistsScreen`,
/// cf. ADR 026 §8) : à la déconnexion/reconnexion l'écran est reconstruit et le
/// contrôleur repart vierge. Toutes les routes sous-jacentes sont derrière
/// `RequireAuth` ; la route elle-même n'est pas publique.
class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    this.playlistName,
    this.repository,
  });

  final String playlistId;

  /// Nom affiché immédiatement quand la navigation vient de la grille (`extra`),
  /// ce qui évite un titre vide le temps du chargement.
  final String? playlistName;

  /// Injectable pour les tests ; en production construit depuis [DioClient].
  final PlaylistRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PlaylistDetailController>(
      create: (ctx) => PlaylistDetailController(
        repository ??
            PlaylistRepositoryImpl(
              PlaylistRemoteDataSource(
                ctx.read<DioClient>().playlistApi,
                ctx.read<DioClient>().trackApi,
              ),
            ),
        playlistId,
      )..load(),
      child: _PlaylistDetailBody(title: playlistName ?? 'Playlist'),
    );
  }
}

class _PlaylistDetailBody extends StatefulWidget {
  const _PlaylistDetailBody({required this.title});

  final String title;

  @override
  State<_PlaylistDetailBody> createState() => _PlaylistDetailBodyState();
}

class _PlaylistDetailBodyState extends State<_PlaylistDetailBody> {
  /// Recharge la liste et signale l'échec par un toast **quand des pistes sont
  /// déjà affichées** : dans ce cas la vue d'erreur plein écran ne s'affiche pas
  /// (elle ne remplace jamais une liste non vide), et sans toast le
  /// `RefreshIndicator` se contenterait de s'arrêter — l'utilisateur croirait la
  /// liste à jour alors qu'elle est périmée.
  Future<void> _onRefresh() async {
    final controller = context.read<PlaylistDetailController>();
    final hadTracks = controller.tracks.isNotEmpty;
    await controller.refresh();
    if (!mounted || !hadTracks) return;

    final error = controller.error;
    if (error != null) showAuthErrorToast(context, error);
  }

  Future<void> _onAdd() async {
    final controller = context.read<PlaylistDetailController>();
    final trackId = await TrackPickerSheet.show(
      context,
      loadTracks: controller.availableTracks,
    );
    if (!mounted || trackId == null) return;

    try {
      await controller.addTrack(trackId);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Piste ajoutée');
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  Future<void> _onRemove(PlaylistTrack track) async {
    final confirmed = await _confirmRemoveDialog(context, track.title);
    if (!mounted || !confirmed) return;

    final controller = context.read<PlaylistDetailController>();
    try {
      await controller.removeTrack(track.id);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Piste retirée');
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  /// Lance la playlist à partir de [startIndex] (US-05-04). La file d'attente
  /// est une **photo** des pistes affichées : le contrôleur de file vit au
  /// niveau application, il ne peut pas suivre les mutations d'un écran qu'on
  /// quitte. Réordonner ou retirer une piste ne change donc pas ce qui joue
  /// tant que l'utilisateur n'a pas relancé la lecture.
  Future<void> _onPlay({int startIndex = 0}) async {
    final controller = context.read<PlaylistDetailController>();
    if (controller.tracks.isEmpty) return;

    await context.read<PlaylistQueueController>().play(
          playlistId: controller.playlistId,
          playlistName: widget.title,
          tracks: controller.tracks,
          startIndex: startIndex,
        );
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final controller = context.read<PlaylistDetailController>();
    try {
      await controller.reorder(oldIndex, newIndex);
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  String _mutationMessage(Object error) {
    if (error is ConflictException) return error.message;
    if (error is NetworkException) return 'Pas de connexion réseau';
    if (error is ValidationException) return error.message;
    return 'Une erreur est survenue';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaylistDetailController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('playlist_add_track_button'),
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Ajouter une piste',
            onPressed: _onAdd,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: _buildBody(controller),
        ),
      ),
      // Point d'entrée principal de la lecture : sans lui, seul un appui sur une
      // ligne lancerait la playlist — trouvable seulement par tâtonnement.
      floatingActionButton: controller.tracks.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('playlist_play_button'),
              onPressed: _onPlay,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Lire'),
            ),
    );
  }

  Widget _buildBody(PlaylistDetailController controller) {
    if (controller.loading && controller.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.error != null && controller.tracks.isEmpty) {
      return _MessageView(
        icon: controller.isNetworkError
            ? Icons.wifi_off_outlined
            : Icons.error_outline,
        message: controller.error!,
        actionLabel: 'Réessayer',
        onAction: () => context.read<PlaylistDetailController>().load(),
      );
    }

    if (controller.tracks.isEmpty) {
      // Le « + » de l'AppBar est le seul point d'entrée : sur une playlist
      // vide, un appel à l'action au centre rend le premier ajout trouvable.
      return _MessageView(
        key: const Key('playlist_tracks_empty'),
        icon: Icons.queue_music_outlined,
        message: 'Aucune piste dans cette playlist',
        actionLabel: 'Ajouter une piste',
        onAction: _onAdd,
      );
    }

    return ReorderableListView.builder(
      key: const Key('playlist_tracks_list'),
      // Sans ce false, ReorderableListView ajoute ses propres déclencheurs :
      // une seconde poignée à droite de chaque ligne sur desktop/web, et
      // l'appui-long-n'importe-où sur mobile — soit exactement le conflit avec
      // le défilement que la poignée explicite ci-dessous cherche à éviter.
      buildDefaultDragHandles: false,
      physics: const AlwaysScrollableScrollPhysics(),
      // Assez de marge pour que la dernière ligne ne se cache pas sous le FAB.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: controller.tracks.length,
      onReorder: _onReorder,
      itemBuilder: (context, index) {
        final track = controller.tracks[index];
        return _TrackTile(
          // La clé porte l'id de la piste : c'est elle qui permet à
          // ReorderableListView de suivre la ligne pendant le drag.
          key: Key('playlist_track_${track.id}'),
          track: track,
          index: index,
          playlistId: controller.playlistId,
          onRemove: _onRemove,
          onPlay: () => _onPlay(startIndex: index),
        );
      },
    );
  }
}

/// Confirmation avant de retirer une piste. Le retrait ne détruit pas la piste
/// (elle reste dans la bibliothèque) mais **perd sa position** : la ré-ajouter
/// la remet en fin de playlist. Le libellé le dit plutôt que d'annoncer une
/// suppression définitive, qui serait faux.
Future<bool> _confirmRemoveDialog(BuildContext context, String title) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Retirer « $title » de la playlist ?'),
      content: const Text(
        'La piste reste dans ta bibliothèque, mais sa place dans la playlist '
        'est perdue.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('playlist_track_confirm_remove'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Retirer'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    super.key,
    required this.track,
    required this.index,
    required this.playlistId,
    required this.onRemove,
    required this.onPlay,
  });

  final PlaylistTrack track;
  final int index;
  final String playlistId;
  final ValueChanged<PlaylistTrack> onRemove;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    // Comparaison par id et non par index : l'ordre local peut différer de
    // celui figé dans la file (réordonnancement après le lancement).
    final isCurrent = context.select<PlaylistQueueController, bool>(
      (queue) =>
          queue.hasQueue &&
          queue.playlistId == playlistId &&
          queue.currentTrack?.id == track.id,
    );

    return ListTile(
      onTap: onPlay,
      leading: queueTrackLeading(context, index: index, isCurrent: isCurrent),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('playlist_track_remove_${track.id}'),
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Retirer de la playlist',
            onPressed: () => onRemove(track),
          ),
          // Poignée explicite : sur mobile, un appui long sur toute la ligne
          // entrerait en conflit avec le défilement.
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  }

}

class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(icon, size: 64, color: colors.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ),
        ],
      ],
    );
  }
}
