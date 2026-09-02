import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../../playlists/domain/repositories/playlist_repository.dart';
import '../../../playlists/presentation/providers/playlist_queue_controller.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../tracks/domain/entities/public_track.dart';
import '../providers/discover_notifier.dart';
import '../stream_categories.dart';
import '../../../../core/widgets/message_view.dart';
import '../widgets/stream_tile.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final DiscoverNotifier _notifier;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notifier = context.read<DiscoverNotifier>();
    _searchController.text = _notifier.searchQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifier.load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DiscoverNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Découvrir')),
      body: SafeArea(
        child: ResponsiveContent(
          child: Column(
            children: [
              _SearchField(
                controller: _searchController,
                onChanged: _notifier.onSearchChanged,
                onClear: () {
                  _searchController.clear();
                  _notifier.onSearchChanged('');
                },
              ),
              _CategoryChips(
                selected: notifier.selectedCategory,
                onSelected: _notifier.selectCategory,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _notifier.load,
                  child: _buildBody(context, notifier),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DiscoverNotifier notifier) {
    final empty = notifier.streams.isEmpty && notifier.publicTracks.isEmpty;

    if (notifier.isLoading && empty) {
      return const Center(child: CircularProgressIndicator());
    }

    // `MessageView` est déjà une `ListView` défilable : on le rend directement
    // sous le `RefreshIndicator` (comme l'accueil), sans l'imbriquer dans un
    // autre scrollable — c'était la cause du corps vide au simulateur.
    if (notifier.hasError && empty) {
      return MessageView(
        icon: Icons.wifi_off_outlined,
        message: 'Impossible de charger les flux',
        actionLabel: 'Réessayer',
        onAction: _notifier.load,
      );
    }

    if (notifier.isEmpty) {
      // Distingue « rien à découvrir » (vue libre) de « aucun résultat » (filtre
      // actif) : le second invite à élargir le filtre, pas à croire au vide.
      return MessageView(
        icon: notifier.isFiltering
            ? Icons.search_off_outlined
            : Icons.podcasts_outlined,
        message: notifier.isFiltering
            ? 'Aucun flux ne correspond à cette recherche'
            : 'Rien à découvrir pour le moment',
      );
    }

    final text = Theme.of(context).textTheme;
    final publicTracks = notifier.publicTracks;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (notifier.streams.isNotEmpty) ...[
          Text('En direct',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final stream in notifier.streams) ...[
            StreamTile(stream: stream),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
        ],
        if (publicTracks.isNotEmpty) ...[
          Text('Pistes publiques',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (var i = 0; i < publicTracks.length; i++)
            _PublicTrackTile(
              track: publicTracks[i],
              onPlay: () => context.read<PlaylistQueueController>().play(
                    tracks: publicTracks.map((t) => t.toTrack()).toList(),
                    sourceName: 'Pistes publiques',
                    startIndex: i,
                  ),
            ),
        ],
      ],
    );
  }
}

/// Barre de recherche des flux (titre ou diffuseur). Débounce et appel réseau
/// gérés par [DiscoverNotifier] ; ici, uniquement la saisie.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Rechercher un flux, un diffuseur…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Effacer la recherche',
                    onPressed: onClear,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Chips de catégories : « Tous » (aucun filtre) + la liste blanche backend.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  /// Clé de la catégorie active, `null` pour « Tous ».
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Tous'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in streamCategories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category.label),
                selected: selected == category.key,
                onSelected: (_) => onSelected(category.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _PublicTrackTile extends StatelessWidget {
  const _PublicTrackTile({required this.track, required this.onPlay});

  final PublicTrack track;
  final VoidCallback onPlay;

  String _formatDuration(int? seconds) {
    if (seconds == null) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isCurrent = context.select<PlaylistQueueController, bool>(
      (queue) => queue.hasQueue && queue.currentTrack?.id == track.id,
    );

    return ListTile(
      key: Key('public_track_tile_${track.id}'),
      onTap: onPlay,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colors.surfaceContainerHighest,
        child: Icon(
          isCurrent ? Icons.graphic_eq : Icons.music_note,
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
        [
          if (track.artist != null) track.artist!,
          track.ownerName,
          if (track.durationS != null) _formatDuration(track.durationS),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) => _onMenuAction(context, value),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'add_to_playlist',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.playlist_add),
              title: Text('Ajouter à une playlist'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenuAction(BuildContext context, String action) async {
    if (action != 'add_to_playlist') return;
    final repo = context.read<PlaylistRepository>();
    final playlistId = await AddToPlaylistSheet.show(
      context,
      loadPlaylists: repo.list,
    );
    if (playlistId == null || !context.mounted) return;
    try {
      await repo.addTrack(playlistId, track.id);
      if (!context.mounted) return;
      showAuthSuccessToast(context, 'Piste ajoutée à la playlist');
    } on ConflictException {
      if (!context.mounted) return;
      showAuthInfoToast(context, 'Cette piste est déjà dans la playlist');
    } catch (e) {
      if (!context.mounted) return;
      showAuthErrorToast(context, 'Impossible d\'ajouter la piste');
    }
  }
}
