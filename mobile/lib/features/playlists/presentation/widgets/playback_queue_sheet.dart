import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/accessible_icon_button.dart';
import '../../../../core/widgets/volume_slider.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../providers/playlist_queue_controller.dart';
import '../track_labels.dart';
import 'queue_progress.dart';
import 'queue_track_visuals.dart';

/// File d'attente en cours de lecture (US-05-04), en feuille modale.
///
/// En tête, un vrai lecteur « en cours de lecture » (STR-250) : pochette,
/// titre/artiste, avancement, contrôles de transport et volume — ce que le
/// mini-player réduit n'a pas la place de montrer. En dessous, la file
/// elle-même : les pistes à venir, celles déjà passées, et laquelle joue ; un
/// appui sur n'importe quelle ligne y saute.
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

    // Toute la feuille défile d'un bloc : le lecteur en tête est haut, et sur un
    // petit écran il déborderait un `Column` figé qui réserverait sa place avant
    // la liste. La file, elle, ne scrolle pas pour son compte (physique
    // neutralisée) — sinon deux zones de défilement se disputeraient le geste.
    return const SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NowPlayingHeader(),
            _QueueList(),
          ],
        ),
      ),
    );
  }
}

/// Lecteur « en cours de lecture » en tête de la feuille (maquette STR-250) :
/// pochette, titre/artiste, position, avancement, transport et volume.
class _NowPlayingHeader extends StatelessWidget {
  const _NowPlayingHeader();

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<PlaylistQueueController>();
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final track = queue.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetTitleBar(sourceName: queue.sourceName),
          const SizedBox(height: 8),
          const _AlbumArt(),
          const SizedBox(height: 20),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            track.artist ?? 'Artiste inconnu',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            // Rang dans l'ordre de lecture, pas dans la playlist : en aléatoire,
            // la 1re piste jouée n'est pas la 1re de la liste.
            '${queue.positionInOrder + 1} / ${queue.tracks.length}',
            style: text.labelLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // Avancement manipulable (STR-230) : la feuille a la place d'accueillir
          // un pouce, contrairement au bandeau de 60 px.
          const QueueProgressSlider(),
          const SizedBox(height: 4),
          const _TransportControls(),
          const SizedBox(height: 8),
          // Volume ici pour la même raison que la barre d'avancement, et parce
          // qu'il pilote le même transport que pendant un direct (STR-244).
          const VolumeSlider(showLabel: false),
        ],
      ),
    );
  }
}

/// Barre de titre de la feuille : chevron de réduction à gauche, « FILE
/// D'ATTENTE » et le nom de la source centrés.
class _SheetTitleBar extends StatelessWidget {
  const _SheetTitleBar({required this.sourceName});

  final String? sourceName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        AccessibleIconButton(
          key: const Key('queue_collapse_button'),
          icon: Icons.keyboard_arrow_down,
          label: 'Réduire le lecteur',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'FILE D\'ATTENTE',
                style: text.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                sourceName ?? 'Lecture en cours',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        // Contrepoids du chevron : garde le bloc central réellement centré.
        const SizedBox(width: AppConstants.minTouchTarget),
      ],
    );
  }
}

/// Pochette de la piste : dégradé + onde audio, faute de vraie couverture.
class _AlbumArt extends StatelessWidget {
  const _AlbumArt();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primary,
                  Color.lerp(colors.primary, colors.tertiary, 0.6) ??
                      colors.tertiary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            // Onde différente de l'égaliseur qui marque la piste en cours dans
            // la liste (`graphic_eq`) : la pochette n'est pas un indicateur
            // d'état, elle ne doit pas se compter avec lui.
            child: Icon(
              Icons.equalizer_rounded,
              size: 96,
              color: colors.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Contrôles de transport (maquette STR-250) : aléatoire, précédent, lecture/
/// pause, suivant, répétition. Les modes (aléatoire/répétition) vivent ici, au
/// lecteur, plutôt que dans une seconde barre : deux jeux de boutons pour la
/// même action se contrediraient à l'œil.
class _TransportControls extends StatelessWidget {
  const _TransportControls();

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<PlaylistQueueController>();
    final colors = Theme.of(context).colorScheme;

    final (IconData repeatIcon, String repeatLabel) = switch (queue.repeatMode) {
      QueueRepeatMode.off => (Icons.repeat, 'Répétition : désactivée'),
      QueueRepeatMode.all => (Icons.repeat, 'Répétition : toute la file'),
      QueueRepeatMode.one => (Icons.repeat_one, 'Répétition : la piste'),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AccessibleIconButton(
          key: const Key('queue_shuffle_button'),
          icon: Icons.shuffle,
          label: queue.shuffleEnabled
              ? 'Désactiver la lecture aléatoire'
              : 'Activer la lecture aléatoire',
          color: queue.shuffleEnabled ? colors.primary : colors.onSurfaceVariant,
          onPressed: () =>
              context.read<PlaylistQueueController>().toggleShuffle(),
        ),
        AccessibleIconButton(
          key: const Key('queue_previous_button'),
          icon: Icons.skip_previous,
          label: 'Piste précédente',
          iconSize: 34,
          onPressed: queue.hasPrevious
              ? () => context.read<PlaylistQueueController>().previous()
              : null,
        ),
        _PlayPauseButton(queue: queue),
        AccessibleIconButton(
          key: const Key('queue_next_button'),
          icon: Icons.skip_next,
          label: 'Piste suivante',
          iconSize: 34,
          onPressed: queue.hasNext
              ? () => context.read<PlaylistQueueController>().next()
              : null,
        ),
        AccessibleIconButton(
          key: const Key('queue_repeat_button'),
          icon: repeatIcon,
          label: '$repeatLabel. Changer',
          color: queue.repeatMode == QueueRepeatMode.off
              ? colors.onSurfaceVariant
              : colors.primary,
          onPressed: () =>
              context.read<PlaylistQueueController>().cycleRepeat(),
        ),
      ],
    );
  }
}

/// Gros bouton lecture/pause central, plein et circulaire (maquette STR-250).
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.queue});

  final PlaylistQueueController queue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = queue.isBusy || queue.isReconnecting;
    final replay = queue.hasError || queue.isEnded;

    final Widget icon;
    final String label;
    if (busy) {
      icon = SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
      );
      label = 'Chargement';
    } else if (replay) {
      icon = Icon(Icons.replay, size: 34, color: colors.onPrimary);
      label = 'Réessayer la lecture';
    } else if (queue.isPlaying) {
      icon = Icon(Icons.pause, size: 36, color: colors.onPrimary);
      label = 'Mettre en pause';
    } else {
      icon = Icon(Icons.play_arrow, size: 36, color: colors.onPrimary);
      label = 'Lire';
    }

    return Semantics(
      button: true,
      enabled: !busy,
      label: label,
      onTap: busy ? null : queue.togglePlayPause,
      excludeSemantics: true,
      child: Material(
        color: colors.primary,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('queue_play_pause_button'),
          customBorder: const CircleBorder(),
          onTap: busy ? null : queue.togglePlayPause,
          child: SizedBox(
            width: 68,
            height: 68,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

/// La file elle-même : suit l'ordre de lecture, marque la piste en cours, et
/// saute à la ligne touchée. Inchangée depuis US-05-04, hors le fait qu'elle ne
/// scrolle plus pour son compte (la feuille défile d'un bloc).
class _QueueList extends StatelessWidget {
  const _QueueList();

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<PlaylistQueueController>();
    // Menu « Retirer de la playlist » réservé aux files issues d'une playlist :
    // une file bâtie sur la bibliothèque, une recommandation ou une piste
    // publique (STR-231) n'a pas de playlist à modifier.
    final playlistId = queue.playlistId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        ListView.builder(
          key: const Key('playback_queue_list'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: queue.playbackOrder.length,
          itemBuilder: (context, position) {
            // La liste suit l'**ordre de lecture** : en aléatoire, elle annonce
            // donc la suite réelle et non l'ordre de la playlist.
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
              trailing: playlistId == null
                  ? null
                  : _QueueItemMenu(
                      playlistId: playlistId,
                      track: track,
                      index: index,
                    ),
              onTap: () =>
                  context.read<PlaylistQueueController>().skipTo(index),
            );
          },
        ),
      ],
    );
  }
}

/// Menu « ⋮ » d'une ligne de file issue d'une playlist (STR-250) : une seule
/// action, retirer la piste de la playlist. Le retrait vaut pour la playlist
/// **et** pour la file en cours.
class _QueueItemMenu extends StatelessWidget {
  const _QueueItemMenu({
    required this.playlistId,
    required this.track,
    required this.index,
  });

  final String playlistId;
  final Track track;

  /// Indice de la piste dans [PlaylistQueueController.tracks] (ordre naturel),
  /// tel qu'attendu par `removeFromQueue` — le même que celui du `skipTo`.
  final int index;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: Key('queue_item_menu_${track.id}'),
      icon: const Icon(Icons.more_vert),
      tooltip: 'Options de la piste',
      onSelected: (value) {
        if (value == 'remove') _removeFromPlaylist(context);
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'remove',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.playlist_remove),
            title: Text('Retirer de la playlist'),
          ),
        ),
      ],
    );
  }

  Future<void> _removeFromPlaylist(BuildContext context) async {
    final confirmed = await _confirmRemoveDialog(context, track.title);
    if (!confirmed || !context.mounted) return;

    final repository = context.read<PlaylistRepository>();
    final queue = context.read<PlaylistQueueController>();
    try {
      // La base fait foi : on la modifie d'abord, puis on met la file en accord.
      await repository.removeTrack(playlistId, track.id);
      if (!context.mounted) return;
      await queue.removeFromQueue(index);
      if (!context.mounted) return;
      showAuthSuccessToast(context, 'Piste retirée de la playlist');
    } catch (_) {
      if (!context.mounted) return;
      showAuthErrorToast(context, 'Impossible de retirer la piste');
    }
  }
}

/// Confirmation avant retrait. Le retrait ne détruit pas la piste (elle reste
/// dans la bibliothèque) : le libellé le dit plutôt qu'une suppression, qui
/// serait fausse — même formulation que le détail d'une playlist.
Future<bool> _confirmRemoveDialog(BuildContext context, String title) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Retirer « $title » de la playlist ?'),
      content: const Text(
        'La piste reste dans ta bibliothèque, mais sa place dans la playlist '
        'est perdue et elle quitte la file d\'attente.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('queue_item_confirm_remove'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Retirer'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
