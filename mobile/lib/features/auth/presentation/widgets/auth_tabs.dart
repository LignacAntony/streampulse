import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Sélecteur Connexion / Inscription présent en tête des écrans `/login` et
/// `/register`. Permet de basculer entre les deux formulaires.
///
/// Visuel : container pill arrondi, deux segments de largeur égale,
/// segment actif rempli surface variant + libellé en gras blanc, segment
/// inactif transparent + libellé gris.
enum AuthTab { login, register }

class AuthTabs extends StatelessWidget {
  const AuthTabs({super.key, required this.active});

  static const double _height = 48;
  static const double _radius = 12;

  final AuthTab active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: _height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              key: const Key('auth_tab_login'),
              label: 'Connexion',
              active: active == AuthTab.login,
              onTap: active == AuthTab.login
                  ? null
                  : () => context.go('/login'),
            ),
          ),
          Expanded(
            child: _Segment(
              key: const Key('auth_tab_register'),
              label: 'Inscription',
              active: active == AuthTab.register,
              onTap: active == AuthTab.register
                  ? null
                  : () => context.go('/register'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: active ? colors.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: active ? colors.onSurface : colors.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}
