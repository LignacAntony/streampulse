import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:provider/provider.dart';

import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/widgets/queue_progress.dart';

import '../support/fake_queue_playback_service.dart';

/// Budget de reconstruction sous flux haute fréquence (STR-243).
///
/// La fluidité à 60 FPS se mesure sur un appareil (cf. `integration_test/`),
/// mais sa **cause** se vérifie ici, sans appareil et à chaque PR : un flux qui
/// émet plusieurs fois par seconde ne doit reconstruire que le widget qui
/// l'affiche, jamais l'arbre au-dessus.
///
/// C'est la règle posée par CLAUDE.md (« un flux haute fréquence ne traverse
/// jamais un `ChangeNotifier` app-level ») et la raison d'être de
/// `queue_progress.dart`. Sans garde automatique, un futur `notifyListeners()`
/// posé sur `positionStream` la casserait sans qu'aucun test ne rougisse — et
/// le jank n'apparaîtrait qu'à la main, sur un appareil, longtemps après.

Track _track(String id, String title) =>
    Track(id: id, title: title, artist: 'Neon Lights', durationS: 214);

final _tracks = [
  _track('t1', 'Midnight Drive'),
  _track('t2', 'Sunrise'),
  _track('t3', 'Afterglow'),
];

/// Sonde : un widget qui **observe** le contrôleur app-level, donc qui se
/// reconstruit à chaque `notifyListeners()`.
///
/// Elle tient la place de tout ce qui, dans l'application, observe réellement ce
/// contrôleur — `PlayerBar`, `QueueMiniPlayer`, l'écran de détail d'une
/// playlist — et, par ricochet, de tout ce qui se reconstruirait avec eux : une
/// liste Découvrir en cours de défilement se trouve sous le même `MaterialApp`.
class _Watcher extends StatelessWidget {
  const _Watcher({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    context.watch<PlaylistQueueController>();
    onBuild();
    return const SizedBox.shrink();
  }
}

Future<({PlaylistQueueController controller, FakeQueuePlaybackService service, List<int> builds})>
    _pumpQueue(WidgetTester tester, Widget progressWidget) async {
  final service = FakeQueuePlaybackService();
  final controller = PlaylistQueueController(
    service: service,
    token: ({bool forceRefresh = false}) async => 'jwt',
  );
  addTearDown(controller.dispose);
  addTearDown(service.dispose);

  await controller.play(tracks: _tracks, sourceName: 'My Favorites', playlistId: 'p-1');

  final builds = <int>[0];
  await tester.pumpWidget(
    ChangeNotifierProvider<PlaylistQueueController>.value(
      value: controller,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              _Watcher(onBuild: () => builds[0]++),
              progressWidget,
            ],
          ),
        ),
      ),
    ),
  );
  service.emitState(PlayerState(true, ProcessingState.ready));
  service.emitDuration(const Duration(seconds: 214));
  await tester.pump();
  return (controller: controller, service: service, builds: builds);
}

void main() {
  testWidgets('60 positions ne reconstruisent aucun observateur du contrôleur', (tester) async {
    final ctx = await _pumpQueue(tester, const QueueProgressLine());
    final baseline = ctx.builds[0];

    // Une seconde de lecture à la cadence réelle du lecteur (just_audio émet
    // toutes les ~16 ms sur `positionStream` en lecture).
    for (var i = 1; i <= 60; i++) {
      ctx.service.emitPosition(Duration(milliseconds: i * 16));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      ctx.builds[0] - baseline,
      0,
      reason: 'la position a traversé notifyListeners() : tout l\'arbre sous le '
          'contrôleur se reconstruit 60 fois par seconde',
    );
  });

  testWidgets('…mais la barre d\'avancement, elle, a bien avancé', (tester) async {
    // Sans cette assertion, le test ci-dessus passerait aussi si les positions
    // n'étaient jamais délivrées — un zéro vide au lieu d'un zéro mérité.
    final ctx = await _pumpQueue(tester, const QueueProgressLine());

    double valueOf() => tester
        .widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .last
        .value!;

    ctx.service.emitPosition(const Duration(seconds: 10));
    await tester.pump();
    final early = valueOf();

    ctx.service.emitPosition(const Duration(seconds: 100));
    await tester.pump();

    expect(early, lessThan(valueOf()));
  });

  testWidgets('la sonde détecte bien une reconstruction quand il y en a une', (tester) async {
    // Test de contrôle. Sans lui, on ne saurait pas si `_Watcher` compte
    // quelque chose ou reste muet quoi qu'il arrive.
    final ctx = await _pumpQueue(tester, const QueueProgressLine());
    final baseline = ctx.builds[0];

    ctx.service.emitIndex(1); // changement de piste : celui-là DOIT notifier
    // Deux `pump` : l'événement de flux est délivré dans un tour de boucle
    // d'événements, la trame qui en découle est donc la SUIVANTE.
    await tester.pump();
    await tester.pump();

    expect(ctx.builds[0], greaterThan(baseline));
  });

  testWidgets('le curseur manipulable de la file suit la même règle', (tester) async {
    // Le `Slider` du `QueuePlayerScreen` est le point le plus exposé : il
    // affiche la position ET accepte un glissement, donc il redessine à chaque
    // trame pendant que le doigt est posé.
    final ctx = await _pumpQueue(tester, const QueueProgressSlider());
    final baseline = ctx.builds[0];

    for (var i = 1; i <= 60; i++) {
      ctx.service.emitPosition(Duration(milliseconds: i * 16));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(ctx.builds[0] - baseline, 0);
    expect(find.byKey(const Key('queue_progress_slider')), findsOneWidget);
  });
}
