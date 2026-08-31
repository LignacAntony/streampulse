import 'package:flutter/material.dart';

import 'auth_toasts.dart';

class OAuthButtons extends StatelessWidget {
  const OAuthButtons({super.key, this.enabled = true, this.onGoogle});

  final bool enabled;

  /// Action du bouton Google. Si null, affiche un toast « bientôt disponible »
  /// (cas de l'écran d'inscription, non encore câblé).
  final VoidCallback? onGoogle;

  void _showComingSoon(BuildContext context, String provider) {
    showAuthInfoToast(context, '$provider — bientôt disponible');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 16,
      children: [
        _ProviderButton(
          key: const Key('oauth_google_button'),
          tooltip: 'Continuer avec Google',
          icon: const _GoogleLogo(),
          onPressed: enabled
              ? (onGoogle ?? () => _showComingSoon(context, 'Google'))
              : null,
        ),
        _ProviderButton(
          key: const Key('oauth_apple_button'),
          tooltip: "S'inscrire avec Apple",
          icon: Icon(
            Icons.apple,
            size: 28,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: enabled ? () => _showComingSoon(context, 'Apple') : null,
        ),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints.tightFor(width: 56, height: 56),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return Text(
      'G',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
