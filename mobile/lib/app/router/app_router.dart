import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/secure_storage.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/broadcast/presentation/screens/dashboard_screen.dart';
import '../../features/broadcaster/presentation/screens/broadcaster_request_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/playlists/presentation/screens/playlist_detail_screen.dart';
import '../../features/playlists/presentation/screens/playlists_screen.dart';
import '../../features/playlists/presentation/screens/queue_player_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/streams/domain/entities/live_stream.dart';
import '../../features/tracks/presentation/screens/upload_track_screen.dart';
import '../../features/streams/presentation/screens/discover_screen.dart';
import '../../features/streams/presentation/screens/stream_player_screen.dart';
import '../shell/main_shell.dart';

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

const _publicRoutePrefixes = {
  '/stream/',
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
      final isPublic = _publicRoutes.contains(state.matchedLocation) ||
          _publicRoutePrefixes
              .any((prefix) => state.matchedLocation.startsWith(prefix));

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
      GoRoute(
        path: '/broadcaster-request',
        builder: (context, state) => const BroadcasterRequestScreen(),
      ),
      // Les deux lecteurs se présentent comme une modale « now playing » qui
      // monte du bas (le chevron ⌄ de l'en-tête la fait redescendre), plutôt
      // qu'une page qui glisse latéralement : c'est la présentation attendue
      // d'un lecteur plein écran.
      GoRoute(
        path: '/stream/:id',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          StreamPlayerScreen(
            streamId: state.pathParameters['id']!,
            stream: state.extra as LiveStream?,
          ),
        ),
      ),
      GoRoute(
        path: '/queue',
        pageBuilder: (context, state) =>
            _slideUpPage(state, const QueuePlayerScreen()),
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
                builder: (context, state) => const PlaylistsScreen(),
                routes: [
                  // Sous-route de l'onglet : la barre de navigation reste
                  // visible sur le détail d'une playlist. Non publique (les
                  // routes API sont derrière RequireAuth).
                  GoRoute(
                    path: 'playlist/:id',
                    builder: (context, state) => PlaylistDetailScreen(
                      playlistId: state.pathParameters['id']!,
                      playlistName: state.extra as String?,
                    ),
                  ),
                  // Upload d'une piste dans la bibliothèque (US-05-01). Sous-route
                  // de l'onglet : la barre de navigation reste visible.
                  GoRoute(
                    path: 'upload',
                    builder: (context, state) => const UploadTrackScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
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

/// Page à transition « modale montante » : le contenu glisse du bas vers le
/// haut à l'ouverture (et redescend à la fermeture), plutôt que le glissement
/// latéral par défaut. Utilisée par les lecteurs plein écran (direct + file),
/// dont l'en-tête porte un chevron ⌄ pour redescendre.
CustomTransitionPage<void> _slideUpPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
