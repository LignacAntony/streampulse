import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/domain/repositories/playlist_repository.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/widgets/queue_mini_player.dart';

import '../../../../support/fake_queue_playback_service.dart';
import 'package:streampulse/core/audio/playback_transport.dart';
import 'package:streampulse/core/audio/volume_store.dart';
import 'package:streampulse/core/widgets/accessible_icon_button.dart';

/// Faux repository : seul `removeTrack` est exercé (menu « Retirer de la
/// playlist »), le reste n'est pas sollicité par ces tests.
class _FakePlaylistRepository implements PlaylistRepository {
  final List<({String playlistId, String trackId})> removed = [];
  Object? removeError;

  @override
  Future<void> removeTrack(String playlistId, String trackId) async {
    if (removeError != null) throw removeError!;
    removed.add((playlistId: playlistId, trackId: trackId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

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
  PlaylistRepository? playlistRepository,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaylistQueueController>.value(value: controller),
      Provider<PlaybackTransport>.value(
        value: service ?? FakeQueuePlaybackService(),
      ),
      Provider<VolumeStore>(create: (_) => InMemoryVolumeStore()),
      Provider<PlaylistRepository>.value(
        value: playlistRepository ?? _FakePlaylistRepository(),
      ),
    ],
    child: ToastificationWrapper(
      child: MaterialApp(home: Scaffold(body: child)),
    ),
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
  String? playlistId = 'p-1',
  PlaylistRepository? playlistRepository,
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
    playlistId: playlistId,
    startIndex: startIndex,
  );
  await tester.pumpWidget(_host(
    controller,
    child,
    service: service,
    playlistRepository: playlistRepository,
  ));
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

  group('PlaybackQueueSheet (US-05-04)', () {
    testWidgets('liste la file entière et marque la piste en cours',
        (tester) async {
      await _pumpPlaying(tester, const QueueMiniPlayer(), startIndex: 1);
      await _openQueueSheet(tester);

      expect(find.byKey(const Key('playback_queue_list')), findsOneWidget);
      // Le lecteur en tête annonce la position dans l'ordre de lecture.
      expect(find.text('2 / 3'), findsOneWidget);
      // Titre et artiste de la piste en cours, mis en avant en haut de feuille.
      expect(find.text('Sunrise'), findsWidgets);
      for (final track in _tracks) {
        expect(find.byKey(Key('queue_item_${track.id}')), findsOneWidget);
      }
      // La piste en cours porte l'icône d'équaliseur au lieu de son numéro (une
      // seule fois : la pochette du lecteur utilise une autre onde).
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    });

    testWidgets('un appui sur une piste y saute', (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);

      // Le lecteur en tête est haut : la file défile d'un bloc sous lui, la
      // dernière piste peut donc être hors écran.
      await tester.ensureVisible(find.byKey(const Key('queue_item_t3')));
      await tester.tap(find.byKey(const Key('queue_item_t3')));
      await tester.pumpAndSettle();

      expect(t.service.skips, [2]);
      expect(t.controller.currentIndex, 2);
    });

    testWidgets(
        'les modes de lecture sont réglables depuis le transport (US-05-05)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);

      // Aléatoire et répétition vivent désormais dans les boutons du lecteur.
      expect(find.byKey(const Key('queue_shuffle_button')), findsOneWidget);
      expect(find.byIcon(Icons.repeat), findsOneWidget);

      await tester.tap(find.byKey(const Key('queue_repeat_button')));
      await tester.pumpAndSettle();
      expect(t.service.repeatMode, QueueRepeatMode.all);

      await tester.tap(find.byKey(const Key('queue_repeat_button')));
      await tester.pumpAndSettle();
      // « Répéter la piste » : l'icône passe à repeat_one.
      expect(t.service.repeatMode, QueueRepeatMode.one);
      expect(find.byIcon(Icons.repeat_one), findsOneWidget);
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

    testWidgets('file terminée : la poignée est neutralisée (revue #292)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);
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
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);
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

    testWidgets('le lecteur en tête montre titre, artiste et pochette',
        (tester) async {
      await _pumpPlaying(tester, const QueueMiniPlayer(), startIndex: 1);
      await _openQueueSheet(tester);

      // Titre + artiste de la piste en cours (« Sunrise » de Neon Lights).
      expect(find.text('Sunrise'), findsWidgets);
      expect(find.text('Neon Lights'), findsWidgets);
      // Pochette (onde distincte du marqueur d'égaliseur de la liste).
      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
      expect(find.byKey(const Key('queue_play_pause_button')), findsOneWidget);
    });

    testWidgets('le transport enchaîne les pistes (précédent/suivant)',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());

      await _openQueueSheet(tester);

      // Sur la première piste, « précédent » ne mène nulle part.
      final previous = tester.widget<AccessibleIconButton>(
        find.byKey(const Key('queue_previous_button')),
      );
      expect(previous.onPressed, isNull);

      await tester.tap(find.byKey(const Key('queue_next_button')));
      await tester.pump();

      expect(t.service.skips, [1]);
      expect(t.controller.currentIndex, 1);
    });

    testWidgets('le gros bouton central met en pause puis reprend',
        (tester) async {
      final t = await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);

      // La lecture est en cours : le bouton propose la pause (le mini-player
      // sous la feuille porte la sienne, d'où `findsWidgets`).
      expect(find.byIcon(Icons.pause), findsWidgets);

      await tester.tap(find.byKey(const Key('queue_play_pause_button')));
      await tester.pump();

      expect(t.service.playing, isFalse);
    });

    testWidgets('le chevron réduit le lecteur (ferme la feuille)',
        (tester) async {
      await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);
      expect(find.byKey(const Key('playback_queue_list')), findsOneWidget);

      await tester.tap(find.byKey(const Key('queue_collapse_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playback_queue_list')), findsNothing);
    });

    testWidgets('menu « ⋮ » présent pour une file issue d\'une playlist',
        (tester) async {
      await _pumpPlaying(tester, const QueueMiniPlayer());
      await _openQueueSheet(tester);

      expect(find.byKey(const Key('queue_item_menu_t1')), findsOneWidget);
      expect(find.byKey(const Key('queue_item_menu_t2')), findsOneWidget);
    });

    testWidgets('pas de menu quand la file ne vient pas d\'une playlist',
        (tester) async {
      // File bâtie sur la bibliothèque / une reco / une piste publique : pas de
      // playlist à modifier (STR-231).
      await _pumpPlaying(tester, const QueueMiniPlayer(), playlistId: null);
      await _openQueueSheet(tester);

      expect(find.byKey(const Key('queue_item_menu_t1')), findsNothing);
      expect(find.byKey(const Key('queue_item_menu_t2')), findsNothing);
    });

    testWidgets('retirer une piste : retrait en base ET de la file',
        (tester) async {
      final repo = _FakePlaylistRepository();
      final t = await _pumpPlaying(
        tester,
        const QueueMiniPlayer(),
        playlistRepository: repo,
      );
      await _openQueueSheet(tester);

      // On retire t2 (piste à venir, pas celle en cours) via son menu.
      await tester.ensureVisible(find.byKey(const Key('queue_item_menu_t2')));
      await tester.tap(find.byKey(const Key('queue_item_menu_t2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer de la playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue_item_confirm_remove')));
      // Laisse les futures (retrait base + rechargement) se résoudre.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Retrait en base sur la bonne playlist / piste…
      expect(repo.removed, [(playlistId: 'p-1', trackId: 't2')]);
      // …et la file rechargée sans elle, sans couper la piste en cours (t1).
      expect(t.controller.tracks.map((e) => e.id).toList(), ['t1', 't3']);
      expect(t.service.lastItems.map((e) => e.id).toList(), ['t1', 't3']);
      expect(t.controller.currentIndex, 0);
      expect(find.byKey(const Key('queue_item_t2')), findsNothing);

      // Purge le toast de succès (auto-fermeture 4 s) — même nettoyage que les
      // tests d'auth, sinon un timer resterait en vol à la fin du test.
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('retrait annulé : ni base ni file touchées', (tester) async {
      final repo = _FakePlaylistRepository();
      final t = await _pumpPlaying(
        tester,
        const QueueMiniPlayer(),
        playlistRepository: repo,
      );
      await _openQueueSheet(tester);

      await tester.ensureVisible(find.byKey(const Key('queue_item_menu_t2')));
      await tester.tap(find.byKey(const Key('queue_item_menu_t2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer de la playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(repo.removed, isEmpty);
      expect(t.controller.tracks.length, 3);
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
