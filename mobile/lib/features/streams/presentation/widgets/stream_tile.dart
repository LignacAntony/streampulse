import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/live_stream.dart';

/// Tuile d'un flux, partagée par l'accueil, les favoris et « Découvrir ».
///
/// Carte enrichie (STR-XXX, redesign) : pochette dégradée, titre, diffuseur, et
/// une ligne d'état — badge « EN DIRECT » + auditeurs + durée pour un live,
/// libellé de statut sinon. La pochette est décorative : le modèle n'a pas
/// d'image, le dégradé (dérivé de l'id) donne juste une identité stable au flux.
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
      child: InkWell(
        onTap: () => _openPlayer(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Cover(seed: stream.id, live: stream.isLive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stream.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    if (stream.broadcasterName != null &&
                        stream.broadcasterName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        stream.broadcasterName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _MetaLine(stream: stream),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PlayAffordance(live: stream.isLive),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pochette carrée dégradée. Le dégradé est stable pour un flux donné (dérivé de
/// l'id) : deux visites montrent la même couleur, sans stocker d'image.
class _Cover extends StatelessWidget {
  const _Cover({required this.seed, required this.live});

  final String seed;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pair = _gradientFor(seed, colors);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: live
              ? pair
              : [colors.surfaceContainerHighest, colors.surfaceContainerHighest],
        ),
      ),
      child: Icon(
        Icons.graphic_eq,
        color: live ? Colors.white : colors.onSurfaceVariant,
      ),
    );
  }

  /// Choisit une paire de couleurs de la charte à partir de l'id, pour varier
  /// les pochettes sans hasard d'un rendu à l'autre.
  static List<Color> _gradientFor(String seed, ColorScheme colors) {
    final palettes = <List<Color>>[
      [colors.primary, colors.secondary],
      [colors.secondary, colors.tertiary],
      [colors.tertiary, colors.primary],
      [colors.primary, colors.primary.withValues(alpha: 0.5)],
    ];
    final index = seed.isEmpty ? 0 : seed.codeUnitAt(0) % palettes.length;
    return palettes[index];
  }
}

/// Ligne d'état sous le titre : badge live + auditeurs + durée, ou statut.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.stream});

  final LiveStream stream;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (!stream.isLive) {
      return Text(
        _statusLabel(stream.status),
        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      );
    }

    final duration = stream.liveDurationAt(DateTime.now());
    return Row(
      children: [
        const _LiveBadge(),
        if (stream.listenerCount != null) ...[
          const SizedBox(width: 10),
          Icon(Icons.headphones, size: 14, color: colors.secondary),
          const SizedBox(width: 4),
          Text(
            '${stream.listenerCount}',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(width: 10),
        Icon(Icons.schedule, size: 13, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            _formatDuration(duration),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _PlayAffordance extends StatelessWidget {
  const _PlayAffordance({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!live) {
      return Icon(Icons.chevron_right, color: colors.onSurfaceVariant);
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.primary),
      child: Icon(Icons.play_arrow, color: colors.onPrimary),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colors.onError,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'EN DIRECT',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onError,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
          ),
        ],
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
