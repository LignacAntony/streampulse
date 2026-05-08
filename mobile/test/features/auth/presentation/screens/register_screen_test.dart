import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/auth/domain/entities/user.dart';
import 'package:streampulse/features/auth/domain/repositories/auth_repository.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_providers.dart';
import 'package:streampulse/features/auth/presentation/screens/register_screen.dart';
import 'package:toastification/toastification.dart';

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

class _MarkerScreen extends StatelessWidget {
  const _MarkerScreen(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

Widget _buildHarness(_FakeAuthRepository fake) {
  final router = GoRouter(
    initialLocation: '/register',
    routes: [
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/login',
        builder: (_, __) => const _MarkerScreen('LOGIN_PLACEHOLDER'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(fake)],
    child: ToastificationWrapper(
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

User _userStub() => User(
  id: 'abc',
  email: 'alice@example.com',
  username: 'alice',
  role: 'user',
  createdAt: DateTime.utc(2026, 1, 2),
);

Future<void> _fillValid(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('register_username_field')),
    'alice',
  );
  await tester.enterText(
    find.byKey(const Key('register_email_field')),
    'alice@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('register_password_field')),
    'hunter2hunter',
  );
  await tester.enterText(
    find.byKey(const Key('register_confirm_password_field')),
    'hunter2hunter',
  );
}

Future<void> _acceptTerms(WidgetTester tester) async {
  final checkbox = find.byKey(const Key('register_terms_checkbox'));
  await tester.ensureVisible(checkbox);
  await tester.pump();
  await tester.tap(checkbox);
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final btn = find.byKey(const Key('register_submit_button'));
  await tester.ensureVisible(btn);
  await tester.pump();
  await tester.tap(btn);
}

void main() {
  group('RegisterScreen', () {
    testWidgets('rend les 4 champs, la checkbox et le bouton', (tester) async {
      await tester.pumpWidget(_buildHarness(_FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('register_username_field')), findsOneWidget);
      expect(find.byKey(const Key('register_email_field')), findsOneWidget);
      expect(find.byKey(const Key('register_password_field')), findsOneWidget);
      expect(
        find.byKey(const Key('register_confirm_password_field')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('register_terms_checkbox')), findsOneWidget);
      expect(find.byKey(const Key('register_submit_button')), findsOneWidget);
      expect(find.text("NOM D'UTILISATEUR"), findsOneWidget);
      expect(find.text('E-MAIL'), findsOneWidget);
      expect(find.text('MOT DE PASSE'), findsOneWidget);
      expect(find.text('CONFIRMER LE MOT DE PASSE'), findsOneWidget);
    });

    testWidgets('le bouton soumettre est désactivé tant que les CGU ne sont '
        'pas acceptées', (tester) async {
      final fake = _FakeAuthRepository(user: _userStub());
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await _fillValid(tester);
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('register_submit_button')),
      );
      expect(btn.onPressed, isNull);

      await _tapSubmit(tester);
      await tester.pump();
      expect(fake.calls, 0);
    });

    testWidgets('cocher les CGU active le bouton', (tester) async {
      final fake = _FakeAuthRepository(user: _userStub());
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await _fillValid(tester);
      await _acceptTerms(tester);

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('register_submit_button')),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('soumission vide affiche les erreurs requises (CGU cochées)', (
      tester,
    ) async {
      final fake = _FakeAuthRepository();
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await _acceptTerms(tester);
      await _tapSubmit(tester);
      await tester.pump();

      expect(find.text('Email requis'), findsOneWidget);
      expect(find.text('Pseudo requis'), findsOneWidget);
      expect(find.text('Mot de passe requis'), findsOneWidget);
      expect(find.text('Confirmation requise'), findsOneWidget);
      expect(fake.calls, 0);
    });

    testWidgets('confirmation différente bloque la soumission', (tester) async {
      final fake = _FakeAuthRepository(user: _userStub());
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('register_username_field')),
        'alice',
      );
      await tester.enterText(
        find.byKey(const Key('register_email_field')),
        'alice@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'hunter2hunter',
      );
      await tester.enterText(
        find.byKey(const Key('register_confirm_password_field')),
        'something_else',
      );
      await _acceptTerms(tester);

      await _tapSubmit(tester);
      await tester.pump();

      expect(
        find.text('Les mots de passe ne correspondent pas'),
        findsOneWidget,
      );
      expect(fake.calls, 0);
    });

    testWidgets('toggle visibilité mot de passe', (tester) async {
      await tester.pumpWidget(_buildHarness(_FakeAuthRepository()));
      await tester.pumpAndSettle();

      final initial = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('register_password_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(initial.obscureText, isTrue);

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

    testWidgets(
      'soumission valide + CGU appelle le repository et navigue vers /login',
      (tester) async {
        final fake = _FakeAuthRepository(user: _userStub());
        await tester.pumpWidget(_buildHarness(fake));
        await tester.pumpAndSettle();

        await _fillValid(tester);
        await _acceptTerms(tester);

        await _tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(fake.calls, 1);
        expect(fake.lastEmail, 'alice@example.com');
        expect(fake.lastUsername, 'alice');
        expect(fake.lastPassword, 'hunter2hunter');
        expect(find.text('LOGIN_PLACEHOLDER'), findsOneWidget);

        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 700));
      },
    );

    testWidgets('409 affiche un toast avec le message serveur', (tester) async {
      final fake = _FakeAuthRepository(
        error: const DuplicateAccountException(
          'email or username already taken',
        ),
      );
      await tester.pumpWidget(_buildHarness(fake));
      await tester.pumpAndSettle();

      await _fillValid(tester);
      await _acceptTerms(tester);

      await _tapSubmit(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(fake.calls, 1);
      expect(
        find.text('email or username already taken', skipOffstage: false),
        findsOneWidget,
      );

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets("l'onglet Connexion navigue vers /login", (tester) async {
      await tester.pumpWidget(_buildHarness(_FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth_tab_register')), findsOneWidget);
      expect(find.byKey(const Key('auth_tab_login')), findsOneWidget);

      await tester.tap(find.byKey(const Key('auth_tab_login')));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_PLACEHOLDER'), findsOneWidget);
    });
  });
}
