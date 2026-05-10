import 'package:go_router/go_router.dart';

import '../../core/storage/secure_storage.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';

const _publicRoutes = {'/login', '/register', '/home'};

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final storage = SecureStorage();
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
