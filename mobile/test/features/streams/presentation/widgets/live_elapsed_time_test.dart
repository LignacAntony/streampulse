import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/streams/presentation/widgets/live_elapsed_time.dart';

/// Horloge murale simulée : `tester.pump(Duration)` n'avance que l'horloge
/// interne de Flutter, pas `DateTime.now()`.
class _FakeWallClock {
  DateTime value = DateTime(2026, 8, 21, 10, 0, 0);
  DateTime call() => value;
}

Future<void> _pump(
  WidgetTester tester,
  DateTime startedAt,
  _FakeWallClock clock,
) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveElapsedTime(startedAt: startedAt, now: clock.call),
        ),
      ),
    );

Future<void> _advance(
  WidgetTester tester,
  _FakeWallClock clock,
  Duration by,
) async {
  clock.value = clock.value.add(by);
  await tester.pump(by);
}

void main() {
  testWidgets('affiche le temps écoulé depuis le début du direct',
      (tester) async {
    final clock = _FakeWallClock();
    final startedAt = clock.value.subtract(const Duration(minutes: 12, seconds: 4));
    await _pump(tester, startedAt, clock);

    // Immédiatement à l'ouverture, sans attendre un tic : le direct court déjà.
    expect(find.text('12:04'), findsOneWidget);
  });

  testWidgets('avance chaque seconde, indépendamment de la lecture locale',
      (tester) async {
    final clock = _FakeWallClock();
    await _pump(tester, clock.value, clock);
    expect(find.text('00:00'), findsOneWidget);

    await _advance(tester, clock, const Duration(seconds: 3));
    expect(find.text('00:03'), findsOneWidget);
  });

  testWidgets('un démarrage dans le futur ne descend pas sous zéro',
      (tester) async {
    final clock = _FakeWallClock();
    await _pump(tester, clock.value.add(const Duration(minutes: 1)), clock);

    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('le temps de diffusion est annoncé en toutes lettres',
      (tester) async {
    final clock = _FakeWallClock();
    final startedAt = clock.value.subtract(const Duration(seconds: 65));
    await _pump(tester, startedAt, clock);

    expect(
      find.bySemanticsLabel('Temps de diffusion : 01:05'),
      findsOneWidget,
    );
  });
}
