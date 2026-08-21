import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';
import 'package:streampulse/features/streams/presentation/widgets/listening_time.dart';

/// Contrôleur pilotable à la main : le temps d'écoute ne dépend que de l'état
/// de lecture, pas d'un lecteur natif.
class _FakeController extends PlaybackController {
  @override
  PlaybackStatus status = PlaybackStatus.idle;

  NowPlaying? now;

  void emit(PlaybackStatus next, {NowPlaying? playing}) {
    status = next;
    if (playing != null) now = playing;
    notifyListeners();
  }

  @override
  NowPlaying? get nowPlaying => now;
  @override
  bool get isPlaying => status == PlaybackStatus.playing;
  @override
  bool get isBusy =>
      status == PlaybackStatus.loading || status == PlaybackStatus.buffering;
  @override
  bool get isReconnecting => status == PlaybackStatus.reconnecting;
  @override
  bool get hasError => status == PlaybackStatus.error;
  @override
  bool get isEnded => status == PlaybackStatus.ended;

  @override
  Future<void> load(NowPlaying n) async => now = n;
  @override
  Future<void> togglePlayPause() async {}
  @override
  Future<void> stop() async {}
}

const _live = NowPlaying(streamId: 's1', title: 'Radio Neon');

/// Horloge murale simulée. `tester.pump(Duration)` n'avance que l'horloge
/// interne de Flutter : sans cette source injectée, le widget lirait l'heure
/// réelle et le temps d'écoute resterait à zéro pendant tout le test.
class _FakeWallClock {
  DateTime value = DateTime(2026, 8, 20, 10, 0, 0);
  DateTime call() => value;
}

Future<_FakeWallClock> _pump(
  WidgetTester tester,
  _FakeController controller,
) async {
  final clock = _FakeWallClock();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListeningTime(controller: controller, now: clock.call),
      ),
    ),
  );
  return clock;
}

/// Fait avancer les deux horloges ensemble — celle de Flutter (qui déclenche le
/// tic) et l'horloge murale (que lit le compteur).
Future<void> _advance(
  WidgetTester tester,
  _FakeWallClock clock,
  Duration by,
) async {
  clock.value = clock.value.add(by);
  await tester.pump(by);
}

void main() {
  testWidgets('rien tant que rien n\'a été écouté', (tester) async {
    await _pump(tester, _FakeController());
    // Un « 00:00 » figé pendant le chargement laisse croire que c'est bloqué.
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('compte pendant la lecture', (tester) async {
    final controller = _FakeController();
    final clock = await _pump(tester, controller);

    controller.emit(PlaybackStatus.playing, playing: _live);
    await _advance(tester, clock, const Duration(seconds: 3));

    expect(find.text('00:03'), findsOneWidget);
  });

  testWidgets('se fige à la pause et reprend au même point', (tester) async {
    final controller = _FakeController();
    final clock = await _pump(tester, controller);

    controller.emit(PlaybackStatus.playing, playing: _live);
    await _advance(tester, clock, const Duration(seconds: 5));

    controller.emit(PlaybackStatus.paused);
    await _advance(tester, clock, const Duration(seconds: 30));
    expect(find.text('00:05'), findsOneWidget);

    controller.emit(PlaybackStatus.playing);
    await _advance(tester, clock, const Duration(seconds: 2));
    expect(find.text('00:07'), findsOneWidget);
  });

  // La raison d'être de l'horloge : le contrôleur recharge l'URL à chaque
  // reprise (STR-118), ce qui remettrait la position du lecteur à zéro.
  testWidgets('une reconnexion suspend le décompte sans le perdre', (
    tester,
  ) async {
    final controller = _FakeController();
    final clock = await _pump(tester, controller);

    controller.emit(PlaybackStatus.playing, playing: _live);
    await _advance(tester, clock, const Duration(seconds: 10));

    controller.emit(PlaybackStatus.reconnecting);
    await _advance(tester, clock, const Duration(seconds: 4));
    expect(find.text('00:10'), findsOneWidget);

    controller.emit(PlaybackStatus.playing);
    await _advance(tester, clock, const Duration(seconds: 1));
    expect(find.text('00:11'), findsOneWidget);
  });

  testWidgets('changer de flux redémarre le décompte', (tester) async {
    final controller = _FakeController();
    final clock = await _pump(tester, controller);

    controller.emit(PlaybackStatus.playing, playing: _live);
    await _advance(tester, clock, const Duration(seconds: 8));
    expect(find.text('00:08'), findsOneWidget);

    controller.emit(
      PlaybackStatus.playing,
      playing: const NowPlaying(streamId: 's2', title: 'Autre radio'),
    );
    await _advance(tester, clock, const Duration(seconds: 2));

    expect(find.text('00:02'), findsOneWidget);
    expect(find.text('00:10'), findsNothing);
  });

  testWidgets('le temps est annoncé en toutes lettres', (tester) async {
    final controller = _FakeController();
    final clock = await _pump(tester, controller);
    controller.emit(PlaybackStatus.playing, playing: _live);
    await _advance(tester, clock, const Duration(seconds: 65));

    expect(find.bySemanticsLabel('Temps d\'écoute : 01:05'), findsOneWidget);
  });

  group('formatListeningTime', () {
    test('mm:ss en deçà d\'une heure', () {
      expect(formatListeningTime(const Duration(seconds: 9)), '00:09');
      expect(
        formatListeningTime(const Duration(minutes: 12, seconds: 3)),
        '12:03',
      );
    });

    test('h:mm:ss au-delà — « 180:24 » se lit mal', () {
      expect(
        formatListeningTime(const Duration(hours: 3, seconds: 24)),
        '3:00:24',
      );
    });
  });
}
