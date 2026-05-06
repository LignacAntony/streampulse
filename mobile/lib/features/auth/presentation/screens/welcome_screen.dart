import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';

/// Écran d'accueil non-authentifié.
///
/// Présente le branding et offre deux choix :
///   - Se connecter   → `/login`
///   - Créer un compte → `/register`
///
/// Sert de point d'entrée par défaut quand l'utilisateur n'a pas de token,
/// au lieu de l'envoyer directement sur le formulaire de login.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo + titre.
                  SizedBox(
                    height: AppConstants.minTouchTarget * 2,
                    child: Icon(
                      Icons.radio,
                      size: AppConstants.minTouchTarget * 1.5,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'StreamPulse',
                    style: text.headlineLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Streaming audio live & on-demand',
                    style: text.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // CTA principal : créer un compte.
                  SizedBox(
                    height: AppConstants.minTouchTarget,
                    child: FilledButton(
                      key: const Key('welcome_register_button'),
                      onPressed: () => context.go('/register'),
                      child: const Text('Créer un compte'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // CTA secondaire : se connecter.
                  SizedBox(
                    height: AppConstants.minTouchTarget,
                    child: OutlinedButton(
                      key: const Key('welcome_login_button'),
                      onPressed: () => context.go('/login'),
                      child: const Text('Se connecter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
