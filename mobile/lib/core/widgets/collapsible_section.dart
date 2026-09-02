import 'package:flutter/material.dart';

/// En-tête de section repliable : titre + compteur discret + chevron qui pivote.
/// Toute la ligne est tappable. Partagé par « Découvrir » et « Bibliothèque ».
class CollapsibleHeader extends StatelessWidget {
  const CollapsibleHeader({
    super.key,
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '$title, ${expanded ? 'réduire' : 'développer'} la section',
      onTap: onToggle,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text(
                title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contenu d'une section repliable : anime la hauteur entre le contenu complet
/// et zéro, avec un fondu, quand [expanded] change.
class CollapsibleContent extends StatelessWidget {
  const CollapsibleContent({
    super.key,
    required this.expanded,
    required this.child,
  });

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: expanded ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: expanded ? child : const SizedBox(width: double.infinity),
      ),
    );
  }
}
