import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';

/// Sélecteur Connexion / Inscription présent en tête des écrans `/login` et
/// `/register`. Permet de basculer entre les deux formulaires sans revenir
/// à `/welcome`.
///
/// L'onglet actif est déterminé par [active] (`AuthTab.login` ou
/// `AuthTab.register`). Tapper l'onglet inactif déclenche `context.go()`
/// vers la route correspondante.
enum AuthTab { login, register }

class AuthTabs extends StatelessWidget {
  const AuthTabs({super.key, required this.active});

  final AuthTab active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
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
        child: SizedBox(
          height: AppConstants.minTouchTarget,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: active ? colors.onSurface : colors.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
