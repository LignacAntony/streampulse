import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/auth/domain/entities/user.dart';
import 'package:streampulse/features/auth/domain/repositories/auth_repository.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_providers.dart';
import 'package:streampulse/features/auth/presentation/screens/register_screen.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.user, this.error});

  final User? user;
  final Object? error;
  int calls = 0;
  String? lastEmail;
  String? lastUsername;
  String? lastPassword;

  @override
  Future<User> register({
    required String email,
    required String username,
    required String password,
  }) async {
    calls++;
    lastEmail = email;
    lastUsername = username;
    lastPassword = password;
    if (error != null) throw error!;
    return user!;
  }
}

class _LoginPlaceholder extends StatelessWidget {
  const _LoginPlaceholder();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('LOGIN_PLACEHOLDER')));
}

Widget _buildHarness(_FakeAuthRepository fake) {
  final router = GoRouter(
    initialLocation: '/register',
    routes: [
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const _LoginPlaceholder(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fake),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

User _userStub() => User(
      id: 'abc',
      email: 'alice@example.com',
      username: 'alice',
      role: 'user',
      createdAt: DateTime.utc(2026, 1, 2),
    );

void main() {
  group('RegisterScreen', () {
    testWidgets('rend les 3 champs et le bouton', (tester) async {
      await tester.pumpWidget(_buildHarness(_FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('register_email_field')), findsOneWidget);
      expect(find.byKey(const Key('register_username_field')), findsOneWidget);
      expect(find.byKey(const Key('register_password_field')), findsOneWidget);
      expect(find.byKey(const Key('register_submit_button')), findsOneWidget);
    });

    testWidgets('soumission vide affiche les erreurs requises', (tester) async {
      final fake = _FakeAuthRepository();
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pump();

      expect(find.text('Email requis'), findsOneWidget);
      expect(find.text('Pseudo requis'), findsOneWidget);
      expect(find.text('Mot de passe requis'), findsOneWidget);
      expect(fake.calls, 0);
    });

    testWidgets('email invalide bloque la soumission', (tester) async {
      final fake = _FakeAuthRepository();
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('register_email_field')),
        'not-an-email',
      );
      await tester.enterText(
        find.byKey(const Key('register_username_field')),
        'alice',
      );
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'hunter2hunter',
      );
      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pump();

      expect(find.text('Email invalide'), findsOneWidget);
      expect(fake.calls, 0);
    });

    testWidgets('mot de passe trop court bloque la soumission',
        (tester) async {
      final fake = _FakeAuthRepository();
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('register_email_field')),
        'alice@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('register_username_field')),
        'alice',
      );
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'short',
      );
      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pump();

      expect(find.textContaining('Au moins'), findsWidgets);
      expect(fake.calls, 0);
    });

    testWidgets('toggle visibilité mot de passe', (tester) async {
      final fake = _FakeAuthRepository();
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      final passwordField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('register_password_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(passwordField.obscureText, isTrue);

      await tester.tap(find.byKey(const Key('register_toggle_password')));
      await tester.pump();

      final updated = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('register_password_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(updated.obscureText, isFalse);
    });

    testWidgets('soumission valide appelle le repository et navigue vers /login',
        (tester) async {
      final fake = _FakeAuthRepository(user: _userStub());
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('register_email_field')),
        'alice@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('register_username_field')),
        'alice',
      );
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'hunter2hunter',
      );

      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pumpAndSettle();

      expect(fake.calls, 1);
      expect(fake.lastEmail, 'alice@example.com');
      expect(fake.lastUsername, 'alice');
      expect(fake.lastPassword, 'hunter2hunter');
      expect(find.text('LOGIN_PLACEHOLDER'), findsOneWidget);
    });

    testWidgets('409 affiche un SnackBar avec le message serveur',
        (tester) async {
      final fake = _FakeAuthRepository(
        error: const DuplicateAccountException('email or username already taken'),
      );
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('register_email_field')),
        'alice@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('register_username_field')),
        'alice',
      );
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'hunter2hunter',
      );

      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('email or username already taken'), findsOneWidget);
    });
  });
}
