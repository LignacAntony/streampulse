import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/audio/listening_clock.dart';
import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';
import 'package:streampulse/features/streams/presentation/widgets/listening_time.dart';

/// Contrôleur pilotable à la main. Il porte une vraie [ListeningClock], comme
/// `AudioPlayerController` en production : le temps d'écoute est une propriété
/// du contrôleur app-level, pas du widget qui l'affiche.
class _FakeController extends PlaybackController {
  _FakeController(this._clockNow);

  final DateTime Function() _clockNow;
  final _clock = ListeningClock();

  @override
  PlaybackStatus status = PlaybackStatus.idle;
  NowPlaying? _now;

  void emit(PlaybackStatus next, {NowPlaying? playing}) {
    if (playing != null && playing.streamId != _now?.streamId) {
      _clock.reset();
    }
    if (playing != null) _now = playing;
    status = next;
    if (next == PlaybackStatus.playing) {
      _clock.start(_clockNow());
    } else {
      _clock.pause(_clockNow());
    }
    notifyListeners();
  }

  @override
  Duration listeningElapsed(DateTime now) => _clock.elapsedAt(now);

  @override
  NowPlaying? get nowPlaying => _now;
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
  Future<void> load(NowPlaying n) async => emit(PlaybackStatus.loading, playing: n);
  @override
  Future<void> togglePlayPause() async {}
  @override
  Future<void> stop() async {}
}

const _live = NowPlaying(streamId: 's1', title: 'Radio Neon');

/// Horloge murale simulée : `tester.pump(Duration)` n'avance que l'horloge
/// interne de Flutter, pas `DateTime.now()`.
class _FakeWallClock {
  DateTime value = DateTime(2026, 8, 21, 10, 0, 0);
  DateTime call() => value;
}

Future<void> _pumpWidget(
  WidgetTester tester,
  _FakeController controller,
  _FakeWallClock clock,
) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListeningTime(controller: controller, now: clock.call),
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
  testWidgets('rien tant que rien n\'a été écouté', (tester) async {
    final clock = _FakeWallClock();
    await _pumpWidget(tester, _FakeController(clock.call), clock);
    // Un « 00:00 » figé pendant le chargement laisse croire que c'est bloqué.
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('compte pendant la lecture', (tester) async {
    final clock = _FakeWallClock();
    final controller = _FakeController(clock.call);
    await _pumpWidget(tester, controller, clock);

    controller.emit(PlaybackStatus.playing, playing: _live);
    await _advance(tester, clock, const Duration(seconds: 3));

    expect(find.text('00:03'), findsOneWidget);
  });

  testWidgets('se fige à la pause et reprend au même point', (tester) async {
    final clock = _FakeWallClock();
    final controller = _FakeController(clock.call);
    await _pumpWidget(tester, controller, clock);

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
  testWidgets('une reconnexion suspend le décompte sans le perdre',
      (tester) async {
    final clock = _FakeWallClock();
    final controller = _FakeController(clock.call);
    await _pumpWidget(tester, controller, clock);

    controller.emit(PlaybackStatus.playing, playing: _live);
    await _advance(tester, clock, const Duration(seconds: 10));

    controller.emit(PlaybackStatus.reconnecting);
    await _advance(tester, clock, const Duration(seconds: 4));
    expect(find.text('00:10'), findsOneWidget);

    controller.emit(PlaybackStatus.playing);
    await _advance(tester, clock, const Duration(seconds: 1));
    expect(find.text('00:11'), findsOneWidget);
  });

  // Le défaut relevé en revue (#331) : l'horloge vivait dans le `State` de ce
  // widget. Réduire le lecteur puis le rouvrir détruit ce `State` — le compteur
  // repartait de 00:00 alors que le direct jouait depuis dix minutes, ce qui
  // contredisait la promesse du libellé. Le cumul appartient au contrôleur.
  testWidgets('survit à la destruction et au remontage du widget',
      (tester) async {
    final clock = _FakeWallClock();
    final controller = _FakeController(clock.call);
    await _pumpWidget(tester, controller, clock);

    controller.emit(PlaybackStatus.playing, playing: _live);
    await _advance(tester, clock, const Duration(minutes: 10));
    expect(find.text('10:00'), findsOneWidget);

    // On quitte l'écran : la lecture continue via le mini-player app-level.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    clock.value = clock.value.add(const Duration(minutes: 2));

    // On rouvre le plein écran.
    await _pumpWidget(tester, controller, clock);
    await tester.pump();

    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
  });

  testWidgets('changer de flux redémarre le décompte', (tester) async {
    final clock = _FakeWallClock();
    final controller = _FakeController(clock.call);
    await _pumpWidget(tester, controller, clock);

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
    final clock = _FakeWallClock();
    final controller = _FakeController(clock.call);
    await _pumpWidget(tester, controller, clock);
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
      expect(formatListeningTime(const Duration(hours: 3, seconds: 24)), '3:00:24');
    });
  });
}
