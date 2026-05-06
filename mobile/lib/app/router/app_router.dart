import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/secure_storage.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';

// Placeholder supprimé en US-02-02 quand les vrais écrans seront implémentés.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}

// Routes publiques accessibles sans token (auth flow).
const _publicRoutes = {'/welcome', '/login', '/register'};

// La logique de redirect sera complétée en US-02-02 (refresh token, rôles).
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final storage = SecureStorage();
    final token = await storage.getAccessToken();
    final isOnSplash = state.matchedLocation == '/';
    final isPublic = _publicRoutes.contains(state.matchedLocation);

    if (isOnSplash) return null;
    if (isPublic) return null;
    if (token == null) return '/welcome';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) =>
          const _PlaceholderScreen(title: 'Accueil'),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) =>
          const _PlaceholderScreen(title: 'Connexion'),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
  ],
);
