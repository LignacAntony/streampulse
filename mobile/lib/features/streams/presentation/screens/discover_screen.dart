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
import '../widgets/message_view.dart';
import '../widgets/stream_tile.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final DiscoverNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = context.read<DiscoverNotifier>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifier.load());
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DiscoverNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Découvrir')),
      body: SafeArea(
        child: ResponsiveContent(
          child: RefreshIndicator(
            onRefresh: _notifier.load,
            child: _buildBody(context, notifier),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DiscoverNotifier notifier) {
    if (notifier.isLoading &&
        notifier.streams.isEmpty &&
        notifier.publicTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifier.hasError &&
        notifier.streams.isEmpty &&
        notifier.publicTracks.isEmpty) {
      return MessageView(
        icon: Icons.wifi_off_outlined,
        message: 'Impossible de charger les flux',
        actionLabel: 'Réessayer',
        onAction: _notifier.load,
      );
    }

    if (notifier.isEmpty) {
      return const MessageView(
        icon: Icons.podcasts_outlined,
        message: 'Rien à découvrir pour le moment',
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
