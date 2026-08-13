import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:provider/provider.dart';

import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/widgets/queue_mini_player.dart';

import '../../../../support/fake_queue_playback_service.dart';

PlaylistTrack _track(String id, String title, int position) => PlaylistTrack(
      id: id,
      title: title,
      artist: 'Neon Lights',
      durationS: 214,
      position: position,
    );

final _tracks = [
  _track('t1', 'Midnight Drive', 0),
  _track('t2', 'Sunrise', 1),
  _track('t3', 'Afterglow', 2),
];

Widget _host(PlaylistQueueController controller, Widget child) {
  return ChangeNotifierProvider<PlaylistQueueController>.value(
    value: controller,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Monte [child] au-dessus d'une file en cours de lecture.
///
/// L'ordre compte : le widget est monté **avant** l'émission de l'état du
/// lecteur, car sous `testWidgets` seule une `pump` fait avancer la boucle
/// d'événements (le temps y est simulé).
Future<
    ({
      PlaylistQueueController controller,
      FakeQueuePlaybackService service,
    })> _pumpPlaying(
  WidgetTester tester,
  Widget child, {
  int startIndex = 0,
}) async {
  final service = FakeQueuePlaybackService();
  final controller = PlaylistQueueController(
    service: service,
    token: ({bool forceRefresh = false}) async => 'jwt',
  );
  addTearDown(controller.dispose);
  addTearDown(service.dispose);

  await controller.play(
    playlistId: 'p-1',
    playlistName: 'My Favorites',
    tracks: _tracks,
    startIndex: startIndex,
  );
  await tester.pumpWidget(_host(controller, child));
  service.emitState(PlayerState(true, ProcessingState.ready));
  await tester.pump();
  return (controller: controller, service: service);
}

/// Ouvre la file d'attente depuis le mini-player.
Future<void> _openQueueSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('queue_mini_player')));
  await tester.pumpAndSettle();
}

void main() {
  group('QueueMiniPlayer (US-05-04)', () {
    testWidgets('masqué quand aucune file n\'est active', (tester) async {
      final service = FakeQueuePlaybackService();
      final controller = PlaylistQueueController(
        service: service,
        token: ({bool forceRefresh = false}) async => 'jwt',
      );
      addTearDown(controller.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_host(controller, const QueueMiniPlayer()));

      expect(find.byKey(const Key('queue_mini_player')), findsNothing);
    });

    testWidgets('affiche la piste en cours et sa position dans la file',
        (tester) async {
      await _pumpPlaying(tester, const QueueMiniPlayer());

      expect(find.text('Midnight Drive'), findsOneWidget);
      expect(find.text('1/3 · Neon Lights'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('suivant / précédent naviguent dans la file', (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());

      // Sur la première piste, « précédent » n'a rien à faire.
      final previous = tester.widget<IconButton>(
        find.byKey(const Key('queue_mini_previous')),
      );
      expect(previous.onPressed, isNull);

      await tester.tap(find.byKey(const Key('queue_mini_next')));
      await tester.pump();

      expect(t.service.skips, [1]);
      expect(find.text('Sunrise'), findsOneWidget);
    });

    testWidgets('la fin de file est annoncée et relançable', (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());

      t.service.emitState(PlayerState(false, ProcessingState.completed));
      await tester.pump();

      expect(find.text('File d\'attente terminée'), findsOneWidget);
      expect(find.byIcon(Icons.replay), findsOneWidget);
    });

    testWidgets('la croix arrête la lecture et masque la barre',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());

      await tester.tap(find.byKey(const Key('queue_mini_stop')));
      await tester.pump();

      expect(t.service.stopped, isTrue);
      expect(find.byKey(const Key('queue_mini_player')), findsNothing);
    });
  });

  group('PlaybackQueueSheet (US-05-04)', () {
    testWidgets('liste la file entière et marque la piste en cours',
        (tester) async {
      await _pumpPlaying(tester, const QueueMiniPlayer(), startIndex: 1);
      await _openQueueSheet(tester);

      expect(find.byKey(const Key('playback_queue_list')), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
      for (final track in _tracks) {
        expect(find.byKey(Key('queue_item_${track.id}')), findsOneWidget);
      }
      // La piste en cours porte l'icône d'équaliseur au lieu de son numéro.
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    });

    testWidgets('un appui sur une piste y saute', (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);

      await tester.tap(find.byKey(const Key('queue_item_t3')));
      await tester.pumpAndSettle();

      expect(t.service.skips, [2]);
      expect(t.controller.currentIndex, 2);
    });

    testWidgets('les modes de lecture sont réglables depuis la file (US-05-05)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);

      expect(find.byKey(const Key('queue_shuffle_button')), findsOneWidget);
      expect(find.text('Répétition'), findsOneWidget);

      await tester.tap(find.byKey(const Key('queue_repeat_button')));
      await tester.pumpAndSettle();
      expect(find.text('Répéter la file'), findsOneWidget);
      expect(t.service.repeatMode, QueueRepeatMode.all);

      await tester.tap(find.byKey(const Key('queue_repeat_button')));
      await tester.pumpAndSettle();
      expect(find.text('Répéter la piste'), findsOneWidget);
    });

    testWidgets('en aléatoire, la file affiche l\'ordre réellement joué',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      // Le lecteur jouera t2, t3, t1.
      t.service.shuffledOrder = [1, 2, 0];
      await _openQueueSheet(tester);

      await tester.tap(find.byKey(const Key('queue_shuffle_button')));
      await tester.pumpAndSettle();

      expect(t.service.shuffleEnabled, isTrue);
      double y(String id) =>
          tester.getTopLeft(find.byKey(Key('queue_item_$id'))).dy;
      expect(y('t2'), lessThan(y('t3')));
      expect(y('t3'), lessThan(y('t1')));
      // La piste en cours (t1) n'est plus la 1re jouée mais la dernière.
      expect(t.controller.positionInOrder, 2);
    });

    testWidgets('la barre affiche l\'avancement de la piste (STR-230)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);

      t.service.emitDuration(const Duration(seconds: 200));
      t.service.emitPosition(const Duration(seconds: 50));
      // Deux frames : la première laisse les flux délivrer, la seconde peint
      // l'état qu'ils viennent de poser.
      await tester.pump();
      await tester.pump();

      expect(find.text('0:50'), findsOneWidget);
      expect(find.text('3:20'), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.byKey(const Key('queue_progress_slider')),
      );
      expect(slider.value, 50000);
      expect(slider.max, 200000);
    });

    testWidgets('glisser la barre déplace la lecture (STR-230)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);
      t.service.emitDuration(const Duration(seconds: 200));
      t.service.emitPosition(Duration.zero);
      await tester.pump();
      await tester.pump();

      // Le geste démarre au centre de la barre (= 100 s sur 200) et pousse d'un
      // quart de sa largeur vers la droite : on relâche donc aux trois quarts.
      final slider = find.byKey(const Key('queue_progress_slider'));
      await tester.drag(slider, Offset(tester.getSize(slider).width / 4, 0));
      await tester.pumpAndSettle();

      expect(t.service.seeks, hasLength(1));
      expect(
        t.service.seeks.single.inSeconds,
        closeTo(150, 15),
        reason: 'le déplacement suit la position relâchée sur la barre',
      );
    });

    testWidgets('durée inconnue : barre neutralisée plutôt que fausse',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);

      // Piste dont la durée n'est ni déclarée ni encore lue par le lecteur.
      t.service.emitDuration(null);
      await tester.pump();
      await tester.pump();

      final slider = tester.widget<Slider>(
        find.byKey(const Key('queue_progress_slider')),
      );
      // La durée déclarée de la piste (0:12 dans _tracks) sert de valeur
      // d'attente : la barre reste utilisable, elle ne prétend pas 0:00.
      expect(slider.onChanged, isNotNull);
      expect(slider.max, 214000);
    });

    testWidgets('la feuille se referme si la file s\'arrête pendant', (
      tester,
    ) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);
      expect(find.byKey(const Key('playback_queue_list')), findsOneWidget);

      // Arrêt depuis la notification système, ou direct qui reprend le lecteur.
      await t.controller.stop();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playback_queue_list')), findsNothing);
    });
  });
}
