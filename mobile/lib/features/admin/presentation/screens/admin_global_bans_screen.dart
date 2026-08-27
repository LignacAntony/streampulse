import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../data/repositories/admin_chat_repository_impl.dart';
import '../../domain/entities/admin_global_ban.dart';
import '../../domain/repositories/admin_chat_repository.dart';
import '../providers/admin_chat_provider.dart';

class AdminGlobalBansScreen extends StatelessWidget {
  const AdminGlobalBansScreen({super.key, this.repository});

  final AdminChatRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminGlobalBansProvider>(
      create: (ctx) => AdminGlobalBansProvider(
        repository ?? AdminChatRepositoryImpl(ctx.read<DioClient>().adminApi),
      ),
      child: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminGlobalBansProvider>().load();
    });
  }

  Future<void> _onUnban(AdminGlobalBan ban) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Débannir ${ban.username} ?'),
        content: const Text(
          'Cet utilisateur pourra de nouveau écrire dans tous les chats.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Débannir'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await context.read<AdminGlobalBansProvider>().unban(ban.userId);
      if (!mounted) return;
      showAuthSuccessToast(context, '${ban.username} débanni');
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec du débannissement');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminGlobalBansProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Bans globaux du chat')),
      body: SafeArea(child: _buildContent(context, provider)),
    );
  }

  Widget _buildContent(BuildContext context, AdminGlobalBansProvider provider) {
    if (provider.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.bans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              provider.isNetworkError
                  ? Icons.wifi_off_outlined
                  : Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              provider.error!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.read<AdminGlobalBansProvider>().load(),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    if (provider.bans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Aucun utilisateur banni globalement',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: provider.bans.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ban = provider.bans[index];
        return _BanTile(ban: ban, onUnban: _onUnban);
      },
    );
  }
}

class _BanTile extends StatelessWidget {
  const _BanTile({required this.ban, required this.onUnban});

  final AdminGlobalBan ban;
  final ValueChanged<AdminGlobalBan> onUnban;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.errorContainer,
          child: Icon(Icons.block, color: colors.error),
        ),
        title: Text(ban.username, style: text.titleMedium),
        subtitle: ban.reason != null
            ? Text(ban.reason!, style: text.bodySmall)
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Débannir',
          onPressed: () => onUnban(ban),
        ),
      ),
    );
  }
}
