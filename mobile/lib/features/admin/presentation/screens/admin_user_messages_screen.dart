import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/repositories/admin_chat_repository_impl.dart';
import '../../domain/entities/admin_chat_message.dart';
import '../../domain/repositories/admin_chat_repository.dart';
import '../providers/admin_chat_provider.dart';

class AdminUserMessagesScreen extends StatelessWidget {
  const AdminUserMessagesScreen({
    super.key,
    required this.userId,
    required this.username,
    this.repository,
  });

  final String userId;
  final String username;
  final AdminChatRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminUserMessagesProvider>(
      create: (ctx) => AdminUserMessagesProvider(
        repository ?? AdminChatRepositoryImpl(ctx.read<DioClient>().adminApi),
        userId,
      ),
      child: _Body(username: username),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.username});

  final String username;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminUserMessagesProvider>().load();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final provider = context.read<AdminUserMessagesProvider>();
    if (!provider.hasMore || provider.loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      provider.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminUserMessagesProvider>();

    return Scaffold(
      appBar: AppBar(title: Text('Messages de ${widget.username}')),
      body: SafeArea(child: _buildContent(context, provider)),
    );
  }

  Widget _buildContent(BuildContext context, AdminUserMessagesProvider provider) {
    if (provider.loading && provider.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.messages.isEmpty) {
      return _EmptyView(
        icon: provider.isNetworkError
            ? Icons.wifi_off_outlined
            : Icons.error_outline,
        message: provider.error!,
        onRetry: () => context.read<AdminUserMessagesProvider>().load(),
      );
    }

    if (provider.messages.isEmpty) {
      return const _EmptyView(
        icon: Icons.chat_bubble_outline,
        message: 'Aucun message',
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: provider.messages.length + (provider.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= provider.messages.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return _MessageTile(message: provider.messages[index]);
      },
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final AdminChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.live_tv, size: 14, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    message.streamTitle,
                    style: text.labelSmall?.copyWith(color: colors.primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatDate(message.createdAt),
                  style: text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message.content, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: colors.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ],
      ),
    );
  }
}
