import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/live_stream.dart';

/// Tuile d'un flux, partagée par l'accueil, les favoris et « Découvrir ».
/// Affiche un badge « EN DIRECT » pour un flux live, sinon son statut.
class StreamTile extends StatelessWidget {
  const StreamTile({super.key, required this.stream});

  final LiveStream stream;

  void _openPlayer(BuildContext context) {
    context.push('/stream/${stream.id}', extra: stream);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

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
          child: _Subtitle(stream: stream),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.stream});

  final LiveStream stream;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (stream.isLive) {
      final duration = stream.liveDurationAt(DateTime.now());
      return Row(
        children: [
          const _LiveBadge(),
          const SizedBox(width: 8),
          Icon(Icons.schedule, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            _formatDuration(duration),
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      );
    }

    return Text(
      _statusLabel(stream.status),
      style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'EN DIRECT',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onError,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

String _statusLabel(String? status) {
  switch (status) {
    case 'ended':
      return 'Terminé';
    case 'idle':
      return 'À venir';
    default:
      return '—';
  }
}

String _formatDuration(Duration? d) {
  if (d == null) return '—';
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  return '${minutes}min';
}
