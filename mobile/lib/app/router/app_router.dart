import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';

const _publicRoutes = {'/login', '/register', '/home'};


final routerProvider = Provider<GoRouter>((ref) {
  final storage = ref.watch(secureStorageProvider);

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
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
    ],
  );
});
