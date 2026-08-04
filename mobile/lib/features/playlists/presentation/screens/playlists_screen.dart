import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../data/datasources/playlist_remote_data_source.dart';
import '../../data/repositories/playlist_repository_impl.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../providers/playlists_controller.dart';
import '../widgets/playlist_form_sheet.dart';

/// Écran « Bibliothèque » : liste des playlists de l'utilisateur avec création,
/// renommage et suppression (US-05-02). Remplace le `PlaceholderScreen` de
/// `/library`.
///
/// L'onglet reste accessible à un invité (découverte publique), mais seul un
/// utilisateur connecté peut posséder des playlists : le bouton « + » et le
/// chargement de la liste sont masqués tant qu'aucun token n'est présent (le
/// backend impose déjà `RequireAuth` sur toutes les routes).
///
/// `ChangeNotifierProvider` local (pas de câblage global) : [repository] est
/// injectable pour les tests ; en production il est construit depuis
/// [DioClient].
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key, this.repository, this.isAuthenticated});

  final PlaylistRepository? repository;

  /// Force l'état d'authentification (tests). En production, résolu depuis
  /// [SecureStorage].
  final bool? isAuthenticated;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PlaylistsController>(
      create: (ctx) => PlaylistsController(
        repository ??
            PlaylistRepositoryImpl(
              PlaylistRemoteDataSource(ctx.read<DioClient>().playlistApi),
            ),
      ),
      child: _PlaylistsBody(forcedAuth: isAuthenticated),
    );
  }
}

class _PlaylistsBody extends StatefulWidget {
  const _PlaylistsBody({this.forcedAuth});

  final bool? forcedAuth;

  @override
  State<_PlaylistsBody> createState() => _PlaylistsBodyState();
}

class _PlaylistsBodyState extends State<_PlaylistsBody> {
  /// `null` tant que l'état d'authentification n'est pas résolu (spinner).
  bool? _isAuthenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveAuth());
  }

  Future<void> _resolveAuth() async {
    final forced = widget.forcedAuth;
    final authenticated =
        forced ?? (await context.read<SecureStorage>().getAccessToken()) != null;
    if (!mounted) return;
    setState(() => _isAuthenticated = authenticated);
    if (authenticated) {
      await context.read<PlaylistsController>().load();
    }
  }

  Future<void> _onRefresh() => context.read<PlaylistsController>().refresh();

  Future<void> _onCreate() async {
    final result = await PlaylistFormSheet.show(
      context,
      title: 'Nouvelle playlist',
      submitLabel: 'Créer',
    );
    if (!mounted || result == null) return;

    final controller = context.read<PlaylistsController>();
    try {
      await controller.create(result.name, result.description);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Playlist créée');
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  Future<void> _onRename(Playlist playlist) async {
    final result = await PlaylistFormSheet.show(
      context,
      title: 'Renommer la playlist',
      submitLabel: 'Enregistrer',
      initialName: playlist.name,
      initialDescription: playlist.description,
    );
    if (!mounted || result == null) return;

    final controller = context.read<PlaylistsController>();
    try {
      await controller.rename(playlist.id, result.name, result.description);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Playlist mise à jour');
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  Future<void> _onDelete(Playlist playlist) async {
    final confirmed = await _confirmDeleteDialog(context, playlist.name);
    if (!mounted || !confirmed) return;

    final controller = context.read<PlaylistsController>();
    try {
      await controller.delete(playlist.id);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Playlist supprimée');
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  /// Message adapté au type d'exception pour un toast de mutation.
  String _mutationMessage(Object error) {
    if (error is ConflictException) return error.message;
    if (error is NetworkException) return 'Pas de connexion réseau';
    if (error is ValidationException) return error.message;
    return 'Une erreur est survenue';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaylistsController>();
    final authenticated = _isAuthenticated == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bibliothèque'),
        actions: [
          // Le « + » n'existe que pour un utilisateur connecté : un invité ne
          // peut pas posséder de playlist.
          if (authenticated)
            IconButton(
              key: const Key('playlist_create_button'),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Nouvelle playlist',
              onPressed: _onCreate,
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: authenticated ? _onRefresh : () async {},
          child: _buildBody(context, controller),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PlaylistsController controller) {
    // État d'authentification pas encore résolu.
    if (_isAuthenticated == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Invité : pas de playlists, invitation à se connecter.
    if (_isAuthenticated == false) {
      return _MessageView(
        key: const Key('playlists_guest_view'),
        icon: Icons.lock_outline,
        message: 'Connecte-toi pour créer et gérer tes playlists',
        actionLabel: 'Se connecter',
        onAction: () => context.go('/login'),
      );
    }

    if (controller.loading && controller.playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.error != null && controller.playlists.isEmpty) {
      return _MessageView(
        icon: controller.isNetworkError
            ? Icons.wifi_off_outlined
            : Icons.error_outline,
        message: controller.error!,
        actionLabel: 'Réessayer',
        onAction: () => context.read<PlaylistsController>().load(),
      );
    }

    if (controller.playlists.isEmpty) {
      return const _MessageView(
        icon: Icons.library_music_outlined,
        message: 'Aucune playlist pour le moment',
      );
    }

    return GridView.builder(
      key: const Key('playlists_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
        childAspectRatio: 0.80,
      ),
      itemCount: controller.playlists.length,
      itemBuilder: (context, index) {
        final playlist = controller.playlists[index];
        return _PlaylistCard(
          playlist: playlist,
          index: index,
          onRename: _onRename,
          onDelete: _onDelete,
        );
      },
    );
  }
}

Future<bool> _confirmDeleteDialog(BuildContext context, String name) async {
  final colors = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Supprimer la playlist « $name » ?'),
      content: const Text('Cette action est définitive.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('playlist_confirm_delete'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Dégradés et icônes de cover, choisis de façon déterministe selon la position
/// de la playlist (variété visuelle sans donnée de couverture réelle).
const _coverGradients = <List<Color>>[
  [Color(0xFF9D7BF5), Color(0xFF7C4DFF)],
  [Color(0xFF2BD9C4), Color(0xFF14B8A6)],
  [Color(0xFF5B4B8A), Color(0xFF37305C)],
  [Color(0xFF2E6E7E), Color(0xFF1E4A57)],
  [Color(0xFFF5A97B), Color(0xFFEF7C4D)],
  [Color(0xFF7B95F5), Color(0xFF4D6BFF)],
];

const _coverIcons = <IconData>[
  Icons.music_note,
  Icons.speed,
  Icons.psychology_outlined,
  Icons.water_drop_outlined,
  Icons.headphones,
  Icons.graphic_eq,
];

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.index,
    required this.onRename,
    required this.onDelete,
  });

  final Playlist playlist;
  final int index;
  final ValueChanged<Playlist> onRename;
  final ValueChanged<Playlist> onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final gradient = _coverGradients[index % _coverGradients.length];
    final icon = _coverIcons[index % _coverIcons.length];

    return Column(
      key: Key('playlist_card_${playlist.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // La cover occupe l'espace vertical restant (Expanded) : le texte en
        // dessous garde toujours sa place, aucun overflow selon la hauteur de
        // cellule ou l'échelle de police.
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    icon,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _CardMenu(
                    playlist: playlist,
                    onRename: onRename,
                    onDelete: onDelete,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          _trackCountLabel(playlist.trackCount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  String _trackCountLabel(int count) {
    if (count == 0) return 'Aucun titre';
    return '$count ${count == 1 ? 'titre' : 'titres'}';
  }
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({
    required this.playlist,
    required this.onRename,
    required this.onDelete,
  });

  final Playlist playlist;
  final ValueChanged<Playlist> onRename;
  final ValueChanged<Playlist> onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PlaylistAction>(
      key: Key('playlist_menu_${playlist.id}'),
      icon: const Icon(Icons.more_vert, color: Colors.white),
      iconSize: 20,
      tooltip: 'Options',
      onSelected: (action) {
        switch (action) {
          case _PlaylistAction.rename:
            onRename(playlist);
          case _PlaylistAction.delete:
            onDelete(playlist);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<_PlaylistAction>(
          key: Key('playlist_action_rename'),
          value: _PlaylistAction.rename,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Renommer'),
          ),
        ),
        PopupMenuItem<_PlaylistAction>(
          key: Key('playlist_action_delete'),
          value: _PlaylistAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Supprimer'),
          ),
        ),
      ],
    );
  }
}

enum _PlaylistAction { rename, delete }

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
