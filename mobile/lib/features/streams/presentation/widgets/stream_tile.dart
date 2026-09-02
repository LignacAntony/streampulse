import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/cover_gradients.dart';
import '../../domain/entities/live_stream.dart';

/// Tuile d'un flux, partagée par l'accueil, les favoris et « Découvrir ».
class StreamTile extends StatelessWidget {
  const StreamTile({super.key, required this.stream});

  final LiveStream stream;

  void _openPlayer(BuildContext context) {
    context.push('/stream/${stream.id}', extra: stream);
  }

  /// Libellé unique pour les lecteurs d'écran (durée exclue : elle bat à la
  /// seconde et serait relue en boucle).
  String _semanticLabel() {
    final parts = <String>[stream.title];
    final broadcaster = stream.broadcasterName;
    if (broadcaster != null && broadcaster.isNotEmpty) {
      parts.add('par $broadcaster');
    }
    if (stream.isLive) {
      parts.add('en direct');
      final listeners = stream.listenerCount;
      if (listeners != null) {
        parts.add('$listeners ${listeners > 1 ? 'auditeurs' : 'auditeur'}');
      }
    } else {
      parts.add(_statusLabel(stream.status));
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      button: true,
      label: _semanticLabel(),
      onTap: () => _openPlayer(context),
      child: ExcludeSemantics(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openPlayer(context),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _Thumbnail(stream: stream),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          stream.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
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
                        _MetaRow(stream: stream),
                      ],
                    ),
                  ),
                  if (stream.isLive) ...[
                    const SizedBox(width: 8),
                    const _PlayButton(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vignette carrée avec micro. Couleur de fond dérivée de l'`id` (hash → palette),
/// stable pour un flux donné. L'API ne fournit pas d'image.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.stream});

  final LiveStream stream;

  static const double _side = 60;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (!stream.isLive) {
      return Container(
        width: _side,
        height: _side,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.mic_none, size: 28, color: colors.onSurfaceVariant),
      );
    }

    final gradient = _coverGradient(stream.id);
    return Container(
      width: _side,
      height: _side,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.mic, size: 28, color: Colors.white),
    );
  }
}

/// Badge live + auditeurs + temps de diffusion pour un live ; statut sinon.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.stream});

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

    final listeners = stream.listenerCount;
    final startedAt = stream.startedAt;

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const _LiveBadge(),
        if (listeners != null)
          _IconStat(
            icon: Icons.headphones,
            label: '$listeners',
            color: colors.secondary,
          ),
        if (startedAt != null) _LiveDuration(startedAt: startedAt),
      ],
    );
  }
}

/// Icône + valeur (casque + nombre d'auditeurs, horloge + durée).
class _IconStat extends StatelessWidget {
  const _IconStat({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Temps de diffusion depuis `startedAt`, qui bat à la seconde (tic local).
class _LiveDuration extends StatefulWidget {
  const _LiveDuration({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_LiveDuration> createState() => _LiveDurationState();
}

class _LiveDurationState extends State<_LiveDuration> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var elapsed = DateTime.now().difference(widget.startedAt);
    if (elapsed.isNegative) elapsed = Duration.zero;
    return _IconStat(icon: Icons.schedule, label: _formatDuration(elapsed));
  }
}

/// Bouton lecture rond. Décoratif pour l'accessibilité (même action que le tap
/// sur la carte, déjà couverte par le [Semantics] parent).
class _PlayButton extends StatelessWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_arrow_rounded, color: colors.onPrimary, size: 28),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
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
                ),
          ),
        ],
      ),
    );
  }
}

/// Palette de dégradés de vignette, indexée de façon déterministe par l'`id`.
const List<List<Color>> _coverPalette = [
  [Color(0xFF2BD9C4), Color(0xFF1BA98F)], // teal / vert d'eau
  [Color(0xFF9D7BF5), Color(0xFF7C4DFF)], // violet
  [Color(0xFFFF8A9B), Color(0xFFFF6B6B)], // corail
  [Color(0xFFFFC26E), Color(0xFFFF9F45)], // ambre
  [Color(0xFF6FA8FF), Color(0xFF4A7DFF)], // bleu
  [Color(0xFFC86DD7), Color(0xFF9B4DCA)], // magenta
];

LinearGradient _coverGradient(String id) {
  return LinearGradient(
    colors: _coverPalette[stableColorIndex(id, _coverPalette.length)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
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

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  return '${minutes}min';
}
