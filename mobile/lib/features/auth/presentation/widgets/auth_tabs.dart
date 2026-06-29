import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum AuthTab { login, register }

class AuthTabs extends StatelessWidget {
  const AuthTabs({super.key, required this.active, this.onChanged});

  static const double _height = 48;
  static const double _radius = 12;

  final AuthTab active;
  final ValueChanged<AuthTab>? onChanged;

  void _select(BuildContext context, AuthTab tab) {
    final cb = onChanged;
    if (cb != null) {
      cb(tab);
    } else {
      context.go(tab == AuthTab.login ? '/login' : '/register');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: _height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: colors.outline),
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
                  : () => _select(context, AuthTab.login),
            ),
          ),
          Expanded(
            child: _Segment(
              key: const Key('auth_tab_register'),
              label: 'Inscription',
              active: active == AuthTab.register,
              onTap: active == AuthTab.register
                  ? null
                  : () => _select(context, AuthTab.register),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active ? colors.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: active
            ? [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
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
      ),
    );
  }
}
