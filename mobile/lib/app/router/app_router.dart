import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/secure_storage.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../shell/main_shell.dart';
import '../shell/placeholder_screen.dart';

const _publicRoutes = {
  '/login',
  '/register',
  '/home',
  '/library',
  '/discover',
  '/dashboard',
  '/forgot-password',
  '/reset-password',
};

/// Construit le routeur GoRouter de l'application.
///
/// [storage] alimente la redirection d'authentification : présence d'un
/// access token => accès autorisé, sinon redirection vers `/login`.
/// Les onglets principaux vivent dans un [StatefulShellRoute] (barre de
/// navigation inférieure persistante).
GoRouter createAppRouter(SecureStorage storage) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final token = await storage.getAccessToken();
      final isOnSplash = state.matchedLocation == '/';
      final isPublic = _publicRoutes.contains(state.matchedLocation);

      if (isOnSplash) return null;
      if (isPublic) return null;
      if (token == null) return '/login';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return ResetPasswordScreen(token: token);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const PlaceholderScreen(
                  title: 'Bibliothèque',
                  icon: Icons.library_music_outlined,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                builder: (context, state) => const PlaceholderScreen(
                  title: 'Découvrir',
                  icon: Icons.explore_outlined,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const PlaceholderScreen(
                  title: 'Tableau',
                  icon: Icons.grid_view_outlined,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
