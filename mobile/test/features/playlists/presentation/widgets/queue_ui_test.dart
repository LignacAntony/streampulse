import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:provider/provider.dart';

import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/screens/queue_player_screen.dart';
import 'package:streampulse/features/playlists/presentation/widgets/queue_mini_player.dart';

import '../../../../support/fake_queue_playback_service.dart';
import 'package:streampulse/core/audio/playback_transport.dart';
import 'package:streampulse/core/audio/volume_store.dart';
import 'package:streampulse/core/widgets/accessible_icon_button.dart';

Track _track(String id, String title) => Track(
      id: id,
      title: title,
      artist: 'Neon Lights',
      durationS: 214,
    );

final _tracks = [
  _track('t1', 'Midnight Drive'),
  _track('t2', 'Sunrise'),
  _track('t3', 'Afterglow'),
];

/// [service] sert aussi de [PlaybackTransport] : c'est le même objet qui porte
/// la file et le volume en production (STR-244), le fake doit donc l'être aussi.
Widget _host(
  PlaylistQueueController controller,
  Widget child, {
  FakeQueuePlaybackService? service,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaylistQueueController>.value(value: controller),
      Provider<PlaybackTransport>.value(
        value: service ?? FakeQueuePlaybackService(),
      ),
      Provider<VolumeStore>(create: (_) => InMemoryVolumeStore()),
    ],
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
    tracks: _tracks,
    sourceName: 'My Favorites',
    playlistId: 'p-1',
    startIndex: startIndex,
  );
  await tester.pumpWidget(_host(controller, child, service: service));
  service.emitState(PlayerState(true, ProcessingState.ready));
  await tester.pump();
  return (controller: controller, service: service);
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
      final previous = tester.widget<AccessibleIconButton>(
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

  group('QueuePlayerScreen (US-05-04)', () {
    testWidgets('affiche les contrôles de transport, dont lecture/pause',
        (tester) async {
      await _pumpPlaying(tester, const QueuePlayerScreen());

      // Le manque corrigé : le lecteur plein écran porte bien un bouton
      // lecture/pause, en plus de précédent/suivant.
      expect(find.byKey(const Key('queue_full_play_pause')), findsOneWidget);
      expect(find.byKey(const Key('queue_full_previous')), findsOneWidget);
      expect(find.byKey(const Key('queue_full_next')), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('le bouton lecture/pause bascule la lecture', (tester) async {
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());

      await tester.tap(find.byKey(const Key('queue_full_play_pause')));
      await tester.pump();
      expect(t.service.playing, isFalse);
    });

    testWidgets('liste la file entière et marque la piste en cours',
        (tester) async {
      await _pumpPlaying(tester, const QueuePlayerScreen(), startIndex: 1);

      expect(find.byKey(const Key('playback_queue_list')), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
      for (final track in _tracks) {
        expect(find.byKey(Key('queue_item_${track.id}')), findsOneWidget);
      }
      // La piste en cours porte l'icône d'équaliseur au lieu de son numéro.
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    });

    testWidgets('un appui sur une piste y saute', (tester) async {
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());

      // La liste peut dépasser le pli (l'écran porte un bloc « en cours » et les
      // contrôles au-dessus) : on amène la piste dans le champ avant de taper.
      final item = find.byKey(const Key('queue_item_t3'));
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();

      expect(t.service.skips, [2]);
      expect(t.controller.currentIndex, 2);
    });

    testWidgets('les modes de lecture sont réglables (US-05-05)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());

      expect(find.byKey(const Key('queue_full_shuffle')), findsOneWidget);
      // Le libellé (tooltip + sémantique) dit l'action, l'icône seule ne suffit
      // pas à distinguer « répéter la piste » de « répéter la file ».
      expect(find.byTooltip('Activer la répétition'), findsOneWidget);

      await tester.tap(find.byKey(const Key('queue_full_repeat')));
      await tester.pumpAndSettle();
      expect(t.service.repeatMode, QueueRepeatMode.all);
      expect(find.byTooltip('Répéter la file'), findsOneWidget);

      await tester.tap(find.byKey(const Key('queue_full_repeat')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Répéter la piste'), findsOneWidget);
    });

    testWidgets('en aléatoire, la file affiche l\'ordre réellement joué',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());
      // Le lecteur jouera t2, t3, t1.
      t.service.shuffledOrder = [1, 2, 0];

      await tester.tap(find.byKey(const Key('queue_full_shuffle')));
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
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());

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
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());
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
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());

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

    testWidgets('file terminée : la poignée est neutralisée (revue #292)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());
      t.service.emitDuration(const Duration(seconds: 200));
      await tester.pump();
      await tester.pump();

      t.service.emitState(PlayerState(false, ProcessingState.completed));
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(
        find.byKey(const Key('queue_progress_slider')),
      );
      // `seek` refuserait de toute façon : une poignée qui glisse sans rien
      // déplacer est pire que pas de poignée.
      expect(slider.onChanged, isNull);
    });

    testWidgets('changement de piste : pas de durée périmée (revue #292)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());
      t.service.emitDuration(const Duration(seconds: 200));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<Slider>(find.byKey(const Key('queue_progress_slider')))
            .max,
        200000,
      );

      // Piste suivante : le lecteur n'a pas encore lu sa durée.
      t.service.emitIndex(1);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Slider>(find.byKey(const Key('queue_progress_slider')))
            .max,
        214000,
        reason: 'la durée déclarée de la nouvelle piste, pas celle d\'avant',
      );
    });

    testWidgets('l\'écran se vide si la file s\'arrête pendant', (
      tester,
    ) async {
      final t = await _pumpPlaying(tester, const QueuePlayerScreen());
      expect(find.byKey(const Key('playback_queue_list')), findsOneWidget);

      // Arrêt depuis la notification système, ou direct qui reprend le lecteur.
      await t.controller.stop();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playback_queue_list')), findsNothing);
    });
  });
}
