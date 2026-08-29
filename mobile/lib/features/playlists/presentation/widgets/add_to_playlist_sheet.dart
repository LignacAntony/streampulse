import 'package:flutter/material.dart';

import '../../domain/entities/playlist.dart';

class AddToPlaylistSheet extends StatefulWidget {
  const AddToPlaylistSheet({super.key, required this.loadPlaylists});

  final Future<List<Playlist>> Function() loadPlaylists;

  static Future<String?> show(
    BuildContext context, {
    required Future<List<Playlist>> Function() loadPlaylists,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => AddToPlaylistSheet(loadPlaylists: loadPlaylists),
    );
  }

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  late Future<List<Playlist>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadPlaylists();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ajouter à une playlist',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
                minWidth: double.infinity,
              ),
              child: FutureBuilder<List<Playlist>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Align(
                        heightFactor: 1,
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _SheetMessage(
                      key: const Key('add_to_playlist_error'),
                      message: 'Impossible de charger les playlists',
                      color: colors.onSurfaceVariant,
                    );
                  }
                  final playlists = snapshot.data ?? const <Playlist>[];
                  if (playlists.isEmpty) {
                    return _SheetMessage(
                      key: const Key('add_to_playlist_empty'),
                      message: 'Aucune playlist — crée-en une d\'abord',
                      color: colors.onSurfaceVariant,
                    );
                  }
                  return ListView.builder(
                    key: const Key('add_to_playlist_list'),
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ListTile(
                        key: Key('add_to_playlist_item_${playlist.id}'),
                        leading: CircleAvatar(
                          backgroundColor: colors.surfaceContainerHighest,
                          child: Icon(
                            Icons.playlist_play,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${playlist.trackCount} piste${playlist.trackCount > 1 ? 's' : ''}',
                        ),
                        onTap: () => Navigator.of(context).pop(playlist.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({
    super.key,
    required this.message,
    required this.color,
  });

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Align(
        heightFactor: 1,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}
