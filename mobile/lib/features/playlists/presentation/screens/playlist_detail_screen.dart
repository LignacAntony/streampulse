import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/offline/entities/cached_track_status.dart';
import '../../../../core/offline/offline_cache_repository.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../data/datasources/playlist_remote_data_source.dart';
import '../../data/repositories/playlist_repository_impl.dart';
import '../../domain/entities/playlist_track.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../providers/offline_playlist_controller.dart';
import '../providers/playlist_detail_controller.dart';
import '../providers/playlist_queue_controller.dart';
import '../track_labels.dart';
import '../widgets/playlist_form_sheet.dart';
import '../widgets/queue_track_visuals.dart';
import '../widgets/track_picker_sheet.dart';
import '../../../../core/widgets/accessible_icon_button.dart';

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
        offlineFallback: ctx.read<OfflineCacheRepository>().cachedTracks,
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
  /// File d'attente app-level, écoutée pour resynchroniser le détail après un
  /// retrait fait **depuis la file** (« Retirer de la playlist », STR-250).
  PlaylistQueueController? _queue;

  /// Ids que la file contenait pour CETTE playlist, au dernier point connu.
  /// Sans ce repère, retirer une piste depuis la vue d'écoute laissait le détail
  /// périmé : l'utilisateur devait tirer pour rafraîchir en revenant dessus.
  Set<String> _knownQueueTrackIds = const {};

  @override
  void initState() {
    super.initState();
    // État favori chargé une fois (pas à chaque refresh de pistes) : STR-250.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlaylistDetailController>().loadFavorite();
    });
  }

  Future<void> _onToggleFavorite() async {
    try {
      await context.read<PlaylistDetailController>().toggleFavorite();
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final queue = context.read<PlaylistQueueController>();
    if (identical(queue, _queue)) return;
    _queue?.removeListener(_onQueueChanged);
    _queue = queue..addListener(_onQueueChanged);
    _knownQueueTrackIds = _currentQueueTrackIds();
  }

  /// Ids de la file **si** elle joue cette playlist, sinon vide : une file bâtie
  /// sur une autre source ne concerne pas ce détail.
  Set<String> _currentQueueTrackIds() {
    final queue = _queue;
    final playlistId = context.read<PlaylistDetailController>().playlistId;
    if (queue == null || queue.playlistId != playlistId) return const {};
    return {for (final track in queue.tracks) track.id};
  }

  /// La file de cette playlist a-t-elle perdu une piste ? Alors la playlist en
  /// base a changé (retrait depuis la file) et le détail se recharge tout seul.
  void _onQueueChanged() {
    if (!mounted) return;
    final queue = _queue;
    if (queue == null) return;
    final controller = context.read<PlaylistDetailController>();

    // La file joue-t-elle (encore) cette playlist ? Cas particulier : retirer la
    // **dernière** piste arrête la file, ce qui remet son `playlistId` à null —
    // on reconnaît alors « notre » file au fait qu'on suivait déjà ses pistes et
    // qu'elle vient de se vider. Sans ça, le retrait de la dernière piste ne
    // rafraîchissait pas le détail (piste fantôme jusqu'au pull-to-refresh).
    final isOurs = queue.playlistId == controller.playlistId ||
        (queue.tracks.isEmpty && _knownQueueTrackIds.isNotEmpty);
    if (!isOurs) return;

    final current = {for (final track in queue.tracks) track.id};
    // Strictement moins de pistes qu'avant, toutes déjà connues : c'est un
    // retrait, pas un nouveau lancement (qui, lui, ajoute des pistes).
    final removed = current.length < _knownQueueTrackIds.length &&
        _knownQueueTrackIds.containsAll(current);
    // Mise à jour immédiate : les `notifyListeners` en rafale d'un même retrait
    // ne déclenchent ainsi qu'un seul rechargement.
    _knownQueueTrackIds = current;
    if (removed) controller.refresh();
  }

  @override
  void dispose() {
    _queue?.removeListener(_onQueueChanged);
    super.dispose();
  }

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
  ///
  /// [shuffle] non nul force le mode de lecture (« Lire en aléatoire »
  /// US-05-05) ; omis, le mode courant est conservé.
  Future<void> _onPlay({int startIndex = 0, bool? shuffle}) async {
    final controller = context.read<PlaylistDetailController>();
    if (controller.tracks.isEmpty) return;

    await context.read<PlaylistQueueController>().play(
          // La file joue des pistes : l'ordre de la playlist est déjà celui de
          // la liste, la position de chacune n'a plus d'usage une fois partie.
          tracks: [for (final track in controller.tracks) track.toTrack()],
          sourceName: widget.title,
          playlistId: controller.playlistId,
          startIndex: startIndex,
          shuffle: shuffle,
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
          AccessibleIconButton(
            key: const Key('playlist_favorite_button'),
            icon: controller.isFavorite
                ? Icons.favorite
                : Icons.favorite_border,
            label: controller.isFavorite
                ? 'Retirer la playlist des favoris'
                : 'Ajouter la playlist aux favoris',
            onPressed: _onToggleFavorite,
          ),
          AccessibleIconButton(
            key: const Key('playlist_shuffle_play_button'),
            icon: Icons.shuffle,
            label: 'Lire la playlist en aléatoire',
            onPressed: controller.tracks.isEmpty
                ? null
                : () => _onPlay(
                      startIndex: Random().nextInt(controller.tracks.length),
                      shuffle: true,
                    ),
          ),
          AccessibleIconButton(
            key: const Key('playlist_add_track_button'),
            icon: Icons.playlist_add,
            label: 'Ajouter une piste à la playlist',
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

    return Column(
      children: [
        if (controller.isOfflineFallback)
          _OfflineBanner()
        else
          _OfflineSection(
            playlistId: controller.playlistId,
            playlistName: widget.title,
            tracks: controller.tracks,
          ),
        Expanded(
          child: ReorderableListView.builder(
            key: const Key('playlist_tracks_list'),
            buildDefaultDragHandles: false,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: controller.tracks.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final track = controller.tracks[index];
              return _TrackTile(
                key: Key('playlist_track_${track.id}'),
                track: track,
                index: index,
                playlistId: controller.playlistId,
                onRemove: _onRemove,
                onPlay: () => _onPlay(startIndex: index),
              );
            },
          ),
        ),
      ],
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

class _OfflineSection extends StatelessWidget {
  const _OfflineSection({
    required this.playlistId,
    required this.playlistName,
    required this.tracks,
  });

  final String playlistId;
  final String playlistName;
  final List<PlaylistTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final offlineController = context.watch<OfflinePlaylistController>();
    final isOffline = offlineController.isOffline(playlistId);
    final progress = offlineController.downloadProgress(playlistId);

    final error = offlineController.consumeError();
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) showAuthErrorToast(context, error);
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: OfflineToggleCard(
        isOffline: isOffline,
        progress: progress,
        onChanged: tracks.isEmpty
            ? null
            : (_) => offlineController.toggleOffline(
                  playlistId,
                  playlistName,
                  tracks,
                ),
      ),
    );
  }
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
    final isCurrent = context.select<PlaylistQueueController, bool>(
      (queue) =>
          queue.hasQueue &&
          queue.playlistId == playlistId &&
          queue.currentTrack?.id == track.id,
    );

    final cacheStatus = context.select<OfflinePlaylistController, TrackCacheStatus?>(
      (c) {
        final statuses = c.trackStatuses(playlistId);
        for (final s in statuses) {
          if (s.trackId == track.id) return s.status;
        }
        return null;
      },
    );

    // Une ligne se lit visuellement d'un coup : numéro, titre, artiste, et un
    // point coloré pour la piste en cours. Un lecteur d'écran parcourt les
    // fragments un par un et ne voit pas le point. Le conteneur porte donc la
    // phrase entière et masque ses enfants — sinon TalkBack annoncerait « 3 »,
    // puis « Sunrise », puis « Neon Lights, 3:34 », sans jamais dire laquelle
    // est en train de jouer.
    return Semantics(
      container: true,
      label: [
        'Piste ${index + 1}',
        track.title,
        if (track.artist != null && track.artist!.isNotEmpty) track.artist!,
        if (isCurrent) 'en cours de lecture',
      ].join(', '),
      button: true,
      selected: isCurrent,
      // `onTap` sur le Semantics et non seulement sur la ListTile : sans lui, le
      // nœud porte le rôle « bouton » sans exposer d'action, et l'activation
      // retombe sur un tap synthétisé par la plateforme (revue PR #332).
      onTap: onPlay,
      child: _row(context, isCurrent, cacheStatus),
    );
  }

  Widget _row(
    BuildContext context,
    bool isCurrent,
    TrackCacheStatus? cacheStatus,
  ) {
    return ListTile(
      onTap: onPlay,
      // TOUT le contenu descriptif est exclu, pas seulement l'entête.
      //
      // Le `Semantics` parent ne masquait rien : la ListTile étant tapable, ses
      // `title`/`subtitle` formaient leur propre nœud À CÔTÉ du libellé composé.
      // Un lecteur d'écran annonçait donc la phrase entière, puis « Sunrise,
      // Neon Lights 3:34 » — exactement la lecture fragmentée que ce changement
      // prétendait supprimer, plus un doublon (revue PR #332).
      //
      // Le bouton « Retirer » du `trailing` reste hors de l'exclusion : il a sa
      // propre action et son propre libellé.
      leading: ExcludeSemantics(
        child: queueTrackLeading(context, index: index, isCurrent: isCurrent),
      ),
      title: ExcludeSemantics(
        child: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: queueTrackTitleStyle(context, isCurrent: isCurrent),
        ),
      ),
      subtitle: ExcludeSemantics(
        child: Text(
          trackSubtitle(artist: track.artist, durationS: track.durationS),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cacheStatus != null) _cacheIcon(context, cacheStatus),
          AccessibleIconButton(
            key: Key('playlist_track_remove_${track.id}'),
            icon: Icons.remove_circle_outline,
            // Nomme la piste : dans une liste, tous ces boutons se ressemblent.
            label: 'Retirer ${track.title} de la playlist',
            tooltip: 'Retirer de la playlist',
            onPressed: () => onRemove(track),
          ),
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

  Widget _cacheIcon(BuildContext context, TrackCacheStatus status) {
    final colors = Theme.of(context).colorScheme;
    return switch (status) {
      TrackCacheStatus.done => Icon(
          Icons.check_circle,
          size: 16,
          color: colors.primary,
        ),
      TrackCacheStatus.downloading => SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.primary,
          ),
        ),
      TrackCacheStatus.error => Icon(
          Icons.error_outline,
          size: 16,
          color: colors.error,
        ),
      TrackCacheStatus.pending => Icon(
          Icons.schedule,
          size: 16,
          color: colors.onSurfaceVariant,
        ),
    };
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_done, size: 20, color: colors.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Mode hors ligne',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
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
