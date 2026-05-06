import 'package:flutter/material.dart';

/// En-tête réutilisé par les écrans /login et /register :
/// petit logo waveform + nom de la marque + tagline.
class BrandedHeader extends StatelessWidget {
  const BrandedHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.graphic_eq,
              size: 28,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'StreamPulse',
              style: text.headlineMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Redéfinissez votre expérience sonore.',
          style: text.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
