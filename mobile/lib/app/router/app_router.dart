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
      GoRoute(
        path: '/stream/:id',
        builder: (context, state) => StreamPlayerScreen(
          streamId: state.pathParameters['id']!,
          stream: state.extra as LiveStream?,
        ),
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
