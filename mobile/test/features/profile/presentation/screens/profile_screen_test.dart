import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/features/auth/domain/entities/token_pair.dart';
import 'package:streampulse/features/auth/domain/entities/user.dart';
import 'package:streampulse/features/auth/domain/repositories/auth_repository.dart';
import 'package:streampulse/features/broadcaster/domain/entities/broadcaster_request.dart';
import 'package:streampulse/features/broadcaster/domain/repositories/broadcaster_repository.dart';
import 'package:streampulse/features/broadcaster/presentation/providers/broadcaster_controller.dart';
import 'package:streampulse/features/profile/domain/entities/user_profile.dart';
import 'package:streampulse/features/profile/domain/repositories/profile_repository.dart';
import 'package:streampulse/features/profile/presentation/providers/profile_controller.dart';
import 'package:streampulse/features/profile/presentation/screens/profile_screen.dart';

/// `ProfileScreen` ne dépend, hors `ProfileController`, que de ces deux
/// repositories (bouton déconnexion / suppression de compte + reset du
/// contrôleur diffuseur) : fakes minimaux, aucune méthode n'est exercée ici.
class _FakeAuthRepository implements AuthRepository {
  @override
  Future<User> register({
    required String email,
    required String username,
    required String password,
  }) async =>
      throw UnimplementedError();

  @override
  Future<TokenPair> login({
    required String email,
    required String password,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> deleteAccount({required String password}) async {}

  @override
  Future<void> requestPasswordReset({required String email}) async {}

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {}
}

class _FakeBroadcasterRepository implements BroadcasterRepository {
  @override
  Future<BroadcasterRequest?> getMyRequest() async => null;

  @override
  Future<BroadcasterRequest> requestBroadcaster({String message = ''}) async =>
      throw UnimplementedError();
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.profile);

  final UserProfile profile;

  @override
  Future<UserProfile> getMe() async => profile;

  @override
  Future<UserProfile> update(UserProfile profile) async => profile;
}

UserProfile _profile({required String role}) => UserProfile(
      id: '1',
      email: 'user1@streampulse.dev',
      role: role,
      pseudo: 'user1',
      bio: '',
      avatarUrl: null,
      theme: 'dark',
      notificationsEnabled: true,
      audioQuality: 'normal',
      createdAt: DateTime.utc(2026, 1, 1),
    );

class _MarkerScreen extends StatelessWidget {
  const _MarkerScreen(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

Widget _buildHarness(UserProfile profile) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/broadcaster-request',
        builder: (_, __) => const _MarkerScreen('BROADCASTER_REQUEST'),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const _MarkerScreen('LOGIN_PLACEHOLDER'),
      ),
    ],
  );

  return MultiProvider(
    providers: [
      Provider<ProfileRepository>.value(
        value: _FakeProfileRepository(profile),
      ),
      ChangeNotifierProvider<ProfileController>(
        create: (ctx) => ProfileController(ctx.read<ProfileRepository>()),
      ),
      Provider<AuthRepository>.value(value: _FakeAuthRepository()),
      ChangeNotifierProvider<BroadcasterController>(
        create: (_) => BroadcasterController(_FakeBroadcasterRepository()),
      ),
    ],
    child: ToastificationWrapper(
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  group('ProfileScreen — tuile Administration', () {
    testWidgets('absente pour un profil non-admin', (tester) async {
      await tester.pumpWidget(_buildHarness(_profile(role: 'user')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_admin_tile')), findsNothing);
      expect(find.text('Administration'), findsNothing);
    });

    testWidgets('absente pour un profil diffuseur', (tester) async {
      await tester.pumpWidget(_buildHarness(_profile(role: 'broadcaster')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_admin_tile')), findsNothing);
    });

    testWidgets('visible pour un profil admin', (tester) async {
      await tester.pumpWidget(_buildHarness(_profile(role: 'admin')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_admin_tile')), findsOneWidget);
      expect(find.text('Administration'), findsOneWidget);
    });
  });
}
