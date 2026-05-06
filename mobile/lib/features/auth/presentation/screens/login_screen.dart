import 'package:flutter/material.dart';

import '../widgets/auth_tabs.dart';
import '../widgets/branded_header.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

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
                children: [
                  const BrandedHeader(),
                  const SizedBox(height: 32),
                  const AuthTabs(active: AuthTab.login),
                  const SizedBox(height: 48),
                  Text(
                    'Connexion',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Le formulaire de connexion sera disponible dans une prochaine version. Pour le moment, crée un compte via l'onglet Inscription.",
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
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
