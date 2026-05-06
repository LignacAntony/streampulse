import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:streampulse/features/auth/presentation/screens/welcome_screen.dart';

class _MarkerScreen extends StatelessWidget {
  const _MarkerScreen(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

Widget _harness() {
  final router = GoRouter(
    initialLocation: '/welcome',
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const _MarkerScreen('LOGIN_PLACEHOLDER'),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const _MarkerScreen('REGISTER_PLACEHOLDER'),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

void main() {
  group('WelcomeScreen', () {
    testWidgets('rend le titre et les deux CTA', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('StreamPulse'), findsOneWidget);
      expect(find.byKey(const Key('welcome_register_button')), findsOneWidget);
      expect(find.byKey(const Key('welcome_login_button')), findsOneWidget);
    });

    testWidgets('le bouton "Créer un compte" navigue vers /register',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('welcome_register_button')));
      await tester.pumpAndSettle();

      expect(find.text('REGISTER_PLACEHOLDER'), findsOneWidget);
    });

    testWidgets('le bouton "Se connecter" navigue vers /login',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('welcome_login_button')));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_PLACEHOLDER'), findsOneWidget);
    });
  });
}
