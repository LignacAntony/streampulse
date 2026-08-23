import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../data/repositories/admin_streams_repository_impl.dart';
import '../../domain/entities/admin_stream.dart';
import '../../domain/repositories/admin_streams_repository.dart';
import '../providers/admin_streams_provider.dart';
import '../../../../core/widgets/accessible_icon_button.dart';

/// Écran de supervision des flux en direct (US-08-02) : liste paginée des
/// flux publics/privés avec l'identité du diffuseur, interruption forcée
/// (modération). Accessible uniquement depuis la tuile « Supervision des
/// flux » de `ProfileScreen` (rôle admin).
///
/// `ChangeNotifierProvider` local (pas de câblage dans `app_providers.dart` :
/// écran rarement visité, réservé aux admins — même choix que
/// `AdminUsersScreen`). [repository] est injectable pour les tests ; en
/// production il est construit depuis [DioClient].
class AdminStreamsScreen extends StatelessWidget {
  const AdminStreamsScreen({super.key, this.repository});

  final AdminStreamsRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminStreamsProvider>(
      create: (ctx) => AdminStreamsProvider(
        repository ?? AdminStreamsRepositoryImpl(ctx.read<DioClient>().adminApi),
      ),
      child: const _AdminStreamsBody(),
    );
  }
}

class _AdminStreamsBody extends StatefulWidget {
  const _AdminStreamsBody();

  @override
  State<_AdminStreamsBody> createState() => _AdminStreamsBodyState();
}

class _AdminStreamsBodyState extends State<_AdminStreamsBody> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminStreamsProvider>().load();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final provider = context.read<AdminStreamsProvider>();
    if (!provider.hasMore || provider.loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _onLoadMore();
    }
  }

  /// Charge la page suivante et affiche un toast d'erreur en cas d'échec.
  ///
  /// `provider.error` n'est rendu en vue plein écran que lorsque la liste est
  /// vide (cf. `_buildBody`) : un échec de `loadMore` (page ≥ 2) laisse la
  /// liste déjà affichée non vide, donc invisible sans ce toast — seul point
  /// d'appel de `loadMore` (scroll auto + bouton « Charger plus »), même
  /// pattern que `AdminUsersScreen`.
  Future<void> _onLoadMore() async {
    final provider = context.read<AdminStreamsProvider>();
    await provider.loadMore();
    if (!mounted) return;
    final error = provider.error;
    if (error != null) {
      showAuthErrorToast(context, error);
    }
  }

  Future<void> _onRefresh() async {
    await context.read<AdminStreamsProvider>().refresh();
  }

  Future<void> _onStop(AdminStream stream) async {
    final provider = context.read<AdminStreamsProvider>();

    final confirmed = await _confirmDialog(
      context,
      title: 'Interrompre le flux "${stream.title}" de ${stream.username} ?',
      message: 'Les auditeurs seront déconnectés.',
      confirmLabel: 'Interrompre',
      confirmKey: const Key('admin_confirm_stop_button'),
    );
    if (!mounted) return;
    if (!confirmed) return;

    try {
      final stopped = await provider.stop(stream);
      if (!mounted) return;
      // `stopped` est faux sur un no-op (flux déjà retiré de la liste
      // entre-temps, ex. arrêté par un autre admin) : le backend a confirmé
      // la mutation, mais il n'y a rien de nouveau à annoncer ici — pas de
      // toast succès trompeur.
      if (stopped) {
        showAuthSuccessToast(context, 'Flux interrompu');
      }
    } on ConflictException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, "Échec de l'interruption");
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminStreamsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Supervision des flux')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: _buildBody(context, provider),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AdminStreamsProvider provider) {
    if (provider.loading && provider.streams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.streams.isEmpty) {
      return _MessageView(
        // Icône adaptée au type d'erreur : une icône réseau sur une panne
        // serveur (ou autre) serait trompeuse pour l'utilisateur.
        icon: provider.isNetworkError
            ? Icons.wifi_off_outlined
            : Icons.error_outline,
        message: provider.error!,
        actionLabel: 'Réessayer',
        onAction: () => context.read<AdminStreamsProvider>().load(),
      );
    }

    if (provider.streams.isEmpty) {
      return const _MessageView(
        icon: Icons.podcasts_outlined,
        message: 'Aucun flux en direct',
      );
    }

    return ListView.separated(
      key: const Key('admin_streams_list'),
      controller: _scrollController,
      // Garantit que le geste de pull-to-refresh (`RefreshIndicator` parent)
      // fonctionne même quand la page chargée ne remplit pas le viewport
      // (peu de flux en direct) : sans ce `physics`, une liste plus courte
      // que l'écran n'est pas "scrollable" et ne relaie aucun overscroll.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: provider.streams.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index < provider.streams.length) {
          final stream = provider.streams[index];
          return _StreamTile(stream: stream, onStop: _onStop);
        }
        return _ListFooter(provider: provider, onLoadMore: _onLoadMore);
      },
    );
  }
}

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Key confirmKey,
}) async {
  final colors = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _StreamTile extends StatelessWidget {
  const _StreamTile({required this.stream, required this.onStop});

  final AdminStream stream;
  final ValueChanged<AdminStream> onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final startedAt = stream.startedAt;

    return Card(
      key: Key('admin_stream_tile_${stream.id}'),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text(stream.title, style: text.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              stream.username,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VisibilityBadge(isPublic: stream.isPublic),
                if (startedAt != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _timeAgo(startedAt),
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: AccessibleIconButton(
          key: Key('admin_stream_stop_${stream.id}'),
          icon: Icons.stop_circle_outlined,
          // Nomme la cible : dans une liste, dix boutons « Interrompre » se
          // suivent et rien ne dit lequel on a sous le doigt.
          label: 'Interrompre le flux ${stream.title}',
          tooltip: 'Interrompre',
          onPressed: () => onStop(stream),
        ),
      ),
    );
  }
}

class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.isPublic});

  final bool isPublic;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isPublic ? 'PUBLIC' : 'PRIVÉ',
        style: TextStyle(
          color: colors.secondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Durée écoulée depuis [startedAt], format court (« il y a 12 min »).
/// N'est appelé que lorsque `startedAt` est non nul (cf. `_StreamTile`) : un
/// flux tout juste créé mais pas encore démarré n'affiche aucune durée.
String _timeAgo(DateTime startedAt) {
  final elapsed = DateTime.now().difference(startedAt);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'à l\'instant';
  if (elapsed.inHours < 1) return 'il y a ${elapsed.inMinutes} min';
  if (elapsed.inDays < 1) return 'il y a ${elapsed.inHours} h';
  return 'il y a ${elapsed.inDays} j';
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.provider, required this.onLoadMore});

  final AdminStreamsProvider provider;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (provider.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (provider.hasMore) {
      return Center(
        child: OutlinedButton(
          key: const Key('admin_streams_load_more_button'),
          onPressed: onLoadMore,
          child: const Text('Charger plus'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
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
      // Idem `admin_streams_list` : garde le pull-to-refresh actif même sur
      // les vues d'erreur/vide, dont le contenu ne remplit pas le viewport.
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
