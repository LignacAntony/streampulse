import 'package:flutter/material.dart';

/// État plein écran « message » : une icône, un texte centré, et une action
/// facultative (p. ex. « Réessayer »). Utilisé pour les états vides, invités et
/// erreurs des écrans de liste.
///
/// Rendu dans une `ListView` `AlwaysScrollableScrollPhysics` : reste tirable
/// (pull-to-refresh) même quand le contenu ne remplit pas l'écran, et se place
/// sous une `RefreshIndicator` sans effet de bord.
///
/// Widget partagé, source unique de l'état « message » : utilisé par les
/// listes de flux (`HomeScreen`, `DiscoverScreen`), la bibliothèque
/// (`PlaylistsScreen`) et la revue admin (`AdminBroadcasterRequestsScreen`),
/// qui en avaient chacun une copie. Une seule implémentation à faire évoluer
/// pour le style, l'accessibilité et le comportement de rafraîchissement.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;

  /// Libellé de l'action. Le bouton n'apparaît que si [actionLabel] **et**
  /// [onAction] sont fournis.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
            child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ),
        ],
      ],
    );
  }
}
