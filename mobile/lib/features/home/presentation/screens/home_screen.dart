import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../streams/domain/entities/live_stream.dart';
import '../../../streams/presentation/providers/stream_notifier.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final notifier = context.read<StreamNotifier>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifier.load();
      notifier.startPolling();
    });
  }

  @override
  void dispose() {
    context.read<StreamNotifier>().stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<StreamNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('En direct')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: notifier.refresh,
          child: _buildBody(context, notifier),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, StreamNotifier notifier) {
    final streams = notifier.streams;

    if (notifier.isLoading && streams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifier.hasError && streams.isEmpty) {
      return _MessageView(
        icon: Icons.wifi_off_outlined,
        message: 'Impossible de charger les flux',
        actionLabel: 'Réessayer',
        onAction: notifier.load,
      );
    }

    if (notifier.isEmpty) {
      return const _MessageView(
        icon: Icons.podcasts_outlined,
        message: 'Aucun flux actif pour le moment',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: streams.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _StreamTile(stream: streams[index]),
    );
  }
}

class _StreamTile extends StatelessWidget {
  const _StreamTile({required this.stream});

  final LiveStream stream;

  void _openPlayer(BuildContext context) {
    context.push('/stream/${stream.id}', extra: stream);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final duration = stream.liveDurationAt(DateTime.now());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _openPlayer(context),
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Icon(Icons.graphic_eq, color: colors.onPrimaryContainer),
        ),
        title: Text(
          stream.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.people_outline, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                _formatListeners(stream.listenerCount),
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Icon(Icons.schedule, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                _formatDuration(duration),
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

String _formatListeners(int? count) => count == null ? '—' : '$count';

String _formatDuration(Duration? d) {
  if (d == null) return '—';
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  return '${minutes}min';
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
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
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
            child: FilledButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}
