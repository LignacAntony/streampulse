import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:provider/provider.dart';

import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/widgets/queue_progress.dart';
import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/presentation/widgets/stream_tile.dart';

import '../test/support/fake_queue_playback_service.dart';

/// Preuve de fluidité à 60 FPS (STR-243).
///
/// Ces mesures **exigent un appareil** : sous `flutter test`, le temps est
/// simulé et rien n'est réellement rastérisé — un budget de trame y serait une
/// fiction. D'où ce répertoire séparé et la cible dédiée :
///
/// ```
/// make frame-budget DEVICE=<id>   # cf. `flutter devices`
/// ```
///
/// ⚠️ `--profile` n'est pas un détail : en mode debug le code Dart est
/// interprété par le JIT sans optimisation, et les temps de construction y sont
/// couramment plusieurs fois ceux du binaire livré. Une mesure debug ne prouve
/// rien — ni dans un sens ni dans l'autre. C'est aussi la raison du détour par
/// `flutter drive` : `flutter test` ne connaît pas `--profile`.
///
/// Ce que cette mesure vérifie, la version sans appareil de
/// `test/performance/rebuild_budget_test.dart` ne peut pas le voir : le coût
/// réel de la rastérisation. Et réciproquement — d'où les deux.

/// Budget d'une trame à 60 images par seconde.
const _frameBudget = Duration(microseconds: 16667);

/// Trames ignorées en tête de scénario : la première rastérisation d'un widget
/// compile ses shaders, coût non représentatif du régime permanent.
const _warmupFrames = 10;

LiveStream _stream(int i) => LiveStream(
      id: 'stream-$i',
      title: 'Radio Neon $i',
      broadcasterName: 'Diffuseur $i',
      status: i.isEven ? 'live' : 'ended',
      listenerCount: i * 7,
      startedAt: DateTime.now().subtract(Duration(minutes: i)),
    );

Track _track(String id, String title) =>
    Track(id: id, title: title, artist: 'Neon Lights', durationS: 214);

/// Statistiques d'une série de trames.
class _FrameStats {
  _FrameStats(List<FrameTiming> timings)
      : build = _percentiles(timings.map((t) => t.buildDuration).toList()),
        raster = _percentiles(timings.map((t) => t.rasterDuration).toList()),
        frames = timings.length,
        missed = timings
            .where((t) =>
                t.buildDuration > _frameBudget || t.rasterDuration > _frameBudget)
            .length;

  final ({Duration p50, Duration p95, Duration worst}) build;
  final ({Duration p50, Duration p95, Duration worst}) raster;
  final int frames;
  final int missed;

  static ({Duration p50, Duration p95, Duration worst}) _percentiles(
      List<Duration> values) {
    if (values.isEmpty) {
      return (p50: Duration.zero, p95: Duration.zero, worst: Duration.zero);
    }
    values.sort();
    Duration at(double p) =>
        values[((values.length * p / 100).ceil() - 1).clamp(0, values.length - 1)];
    return (p50: at(50), p95: at(95), worst: values.last);
  }

  String get report =>
      '$frames trames | build p50=${_ms(build.p50)} p95=${_ms(build.p95)} '
      'max=${_ms(build.worst)} | raster p50=${_ms(raster.p50)} '
      'p95=${_ms(raster.p95)} max=${_ms(raster.worst)} | '
      'hors budget : $missed (${(100 * missed / frames).toStringAsFixed(1)} %)';

  static String _ms(Duration d) =>
      '${(d.inMicroseconds / 1000).toStringAsFixed(2)} ms';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Sans cette politique, la liaison ne produit une trame que sur demande
  // explicite : un défilement n'en engendrerait qu'une poignée et la mesure
  // porterait sur autre chose que ce qu'on croit observer.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  /// Exécute [action] en relevant les trames produites.
  Future<_FrameStats> record(Future<void> Function() action) async {
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> batch) => timings.addAll(batch);
    binding.addTimingsCallback(collect);
    try {
      await action();
    } finally {
      binding.removeTimingsCallback(collect);
    }
    return _FrameStats(
      timings.length > _warmupFrames ? timings.sublist(_warmupFrames) : timings,
    );
  }

  /// Monte une file en lecture et démarre l'émission de positions à ~60 Hz —
  /// la cadence réelle de `positionStream` pendant une lecture.
  Future<({PlaylistQueueController controller, Timer ticker})> startPlayback(
    WidgetTester tester,
  ) async {
    final service = FakeQueuePlaybackService();
    final controller = PlaylistQueueController(
      service: service,
      token: ({bool forceRefresh = false}) async => 'jwt',
    );
    addTearDown(controller.dispose);
    addTearDown(service.dispose);

    await controller.play(
      tracks: [_track('t1', 'Midnight Drive'), _track('t2', 'Sunrise')],
      sourceName: 'My Favorites',
      playlistId: 'p-1',
    );
    service.emitState(PlayerState(true, ProcessingState.ready));
    service.emitDuration(const Duration(seconds: 214));

    var elapsed = Duration.zero;
    final ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      elapsed += const Duration(milliseconds: 16);
      service.emitPosition(elapsed);
    });
    addTearDown(ticker.cancel);
    return (controller: controller, ticker: ticker);
  }

  testWidgets('défilement de Découvrir pendant une lecture', (tester) async {
    // Le cas où le jank apparaîtrait : une liste qui défile pendant qu'un flux
    // haute fréquence alimente le bandeau du lecteur.
    final playback = await startPlayback(tester);
    final streams = List.generate(60, _stream);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlaylistQueueController>.value(
        value: playback.controller,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: streams.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => StreamTile(stream: streams[i]),
                  ),
                ),
                const QueueProgressLine(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stats = await record(() async {
      for (var i = 0; i < 6; i++) {
        await tester.fling(
          find.byType(ListView),
          const Offset(0, -400),
          3000,
        );
        await tester.pumpAndSettle();
      }
    });

    debugPrint('[STR-243] Découvrir + lecture : ${stats.report}');
    expect(stats.frames, greaterThan(30),
        reason: 'trop peu de trames relevées : la mesure ne prouve rien');
    expect(stats.build.p95, lessThan(_frameBudget));
    expect(stats.raster.p95, lessThan(_frameBudget));
  });

  testWidgets('glissement du curseur de la file d\'attente', (tester) async {
    // Le point le plus exposé : le curseur redessine à chaque trame pendant que
    // le doigt est posé, tout en recevant des positions du lecteur.
    final playback = await startPlayback(tester);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlaylistQueueController>.value(
        value: playback.controller,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: QueueProgressSlider())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stats = await record(() async {
      final slider = find.byKey(const Key('queue_progress_slider'));
      for (var i = 0; i < 4; i++) {
        final gesture = await tester.startGesture(tester.getCenter(slider));
        for (var step = 0; step < 20; step++) {
          await gesture.moveBy(const Offset(6, 0));
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }
    });

    debugPrint('[STR-243] Curseur de la file : ${stats.report}');
    expect(stats.frames, greaterThan(30));
    expect(stats.build.p95, lessThan(_frameBudget));
    expect(stats.raster.p95, lessThan(_frameBudget));
  });
}
