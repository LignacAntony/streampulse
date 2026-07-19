import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../data/repositories/admin_repository_impl.dart';
import '../../domain/entities/admin_user.dart';
import '../../domain/repositories/admin_repository.dart';
import '../providers/admin_users_provider.dart';

/// Écran d'administration (US-08-01) : liste/recherche/filtre des comptes,
/// activation/désactivation et suppression définitive. Accessible uniquement
/// depuis la tuile « Administration » de `ProfileScreen` (rôle admin).
///
/// `ChangeNotifierProvider` local (pas de câblage dans `app_providers.dart` :
/// écran rarement visité, réservé aux admins). [repository] est injectable
/// pour les tests ; en production il est construit depuis [DioClient].
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key, this.repository});

  final AdminRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminUsersProvider>(
      create: (ctx) => AdminUsersProvider(
        repository ?? AdminRepositoryImpl(ctx.read<DioClient>().adminApi),
      ),
      child: const _AdminUsersBody(),
    );
  }
}

class _AdminUsersBody extends StatefulWidget {
  const _AdminUsersBody();

  @override
  State<_AdminUsersBody> createState() => _AdminUsersBodyState();
}

class _AdminUsersBodyState extends State<_AdminUsersBody> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminUsersProvider>().load();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final provider = context.read<AdminUsersProvider>();
    if (!provider.hasMore || provider.loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      provider.loadMore();
    }
  }

  Future<void> _onToggle(AdminUser user) async {
    final provider = context.read<AdminUsersProvider>();

    if (user.isActive) {
      final confirmed = await _confirmDialog(
        context,
        title: 'Désactiver ${user.username} ?',
        message: "L'utilisateur ne pourra plus se connecter tant que le "
            "compte n'est pas réactivé.",
        confirmLabel: 'Désactiver',
        confirmKey: const Key('admin_confirm_deactivate_button'),
        destructive: true,
      );
      if (!mounted) return;
      if (!confirmed) return;
    }

    try {
      await provider.toggleActive(user);
      if (!mounted) return;
      showAuthSuccessToast(
        context,
        user.isActive ? 'Compte désactivé' : 'Compte activé',
      );
    } on ConflictException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec de la mise à jour');
    }
  }

  Future<void> _onDelete(AdminUser user) async {
    final provider = context.read<AdminUsersProvider>();

    final confirmed = await _confirmDialog(
      context,
      title: 'Supprimer définitivement ${user.username} ?',
      message: 'Cette action est irréversible : le compte, ses streams et '
          'ses playlists seront supprimés en cascade.',
      confirmLabel: 'Supprimer',
      confirmKey: const Key('admin_confirm_delete_button'),
      destructive: true,
    );
    if (!mounted) return;
    if (!confirmed) return;

    try {
      await provider.delete(user);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Compte supprimé');
    } on ConflictException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec de la suppression');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminUsersProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('admin_users_search_field'),
                controller: _searchController,
                onChanged: (v) => context.read<AdminUsersProvider>().setSearch(v),
                decoration: const InputDecoration(
                  hintText: 'Rechercher (email, pseudo)',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            _FilterChipsRow(
              keyPrefix: 'admin_users_role_chip',
              options: const [
                ('Tous', null),
                ('Utilisateur', 'user'),
                ('Diffuseur', 'broadcaster'),
                ('Admin', 'admin'),
              ],
              selected: provider.roleFilter,
              onSelected: (v) => context.read<AdminUsersProvider>().setRoleFilter(v),
            ),
            const SizedBox(height: 8),
            _FilterChipsRow(
              keyPrefix: 'admin_users_status_chip',
              options: const [
                ('Tous', null),
                ('Actifs', 'active'),
                ('Inactifs', 'inactive'),
              ],
              selected: provider.statusFilter,
              onSelected: (v) =>
                  context.read<AdminUsersProvider>().setStatusFilter(v),
            ),
            const Divider(height: 17),
            Expanded(child: _buildList(context, provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, AdminUsersProvider provider) {
    if (provider.loading && provider.users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.users.isEmpty) {
      return _MessageView(
        icon: Icons.wifi_off_outlined,
        message: provider.error!,
        actionLabel: 'Réessayer',
        onAction: () => context.read<AdminUsersProvider>().load(),
      );
    }

    if (provider.users.isEmpty) {
      return const _MessageView(
        icon: Icons.people_outline,
        message: 'Aucun utilisateur ne correspond à ces critères',
      );
    }

    return ListView.separated(
      key: const Key('admin_users_list'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: provider.users.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index < provider.users.length) {
          final user = provider.users[index];
          return _UserTile(user: user, onToggle: _onToggle, onDelete: _onDelete);
        }
        return _ListFooter(provider: provider);
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
  bool destructive = false,
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
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    required this.keyPrefix,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<(String, String?)> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final option in options) ...[
            FilterChip(
              key: Key('${keyPrefix}_${option.$2 ?? 'all'}'),
              label: Text(option.$1),
              selected: selected == option.$2,
              onSelected: (_) => onSelected(option.$2),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.onToggle,
    required this.onDelete,
  });

  final AdminUser user;
  final ValueChanged<AdminUser> onToggle;
  final ValueChanged<AdminUser> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      key: Key('admin_user_tile_${user.id}'),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text(user.username, style: text.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              user.email,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            _RoleBadge(role: user.role),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              key: Key('admin_user_switch_${user.id}'),
              value: user.isActive,
              onChanged: (_) => onToggle(user),
            ),
            PopupMenuButton<String>(
              key: Key('admin_user_menu_${user.id}'),
              onSelected: (value) {
                if (value == 'delete') onDelete(user);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

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
        _roleLabel(role).toUpperCase(),
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

String _roleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'Administrateur';
    case 'broadcaster':
      return 'Diffuseur';
    case 'user':
      return 'Utilisateur';
    default:
      return role;
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.provider});

  final AdminUsersProvider provider;

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
          key: const Key('admin_users_load_more_button'),
          onPressed: provider.loadMore,
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
