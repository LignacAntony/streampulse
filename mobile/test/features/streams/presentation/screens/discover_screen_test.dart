import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/recommendations/domain/entities/recommended_track.dart';
import 'package:streampulse/features/recommendations/domain/repositories/recommendation_repository.dart';
import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/entities/manifest_status.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/discover_notifier.dart';
import 'package:streampulse/features/streams/presentation/screens/discover_screen.dart';
import 'package:streampulse/features/tracks/domain/entities/public_track.dart';
import 'package:streampulse/features/tracks/domain/repositories/track_repository.dart';

import '../../../../support/fake_queue_playback_service.dart';

class _FakeStreamRepository implements StreamRepository {
  @override
  Future<List<LiveStream>> listLiveStreams({int limit = 50, int offset = 0}) async =>
      const [];

  @override
  Future<List<LiveStream>> listFavorites() async => const [];

  @override
  Future<void> addFavorite(String streamId) async {}

  @override
  Future<void> removeFavorite(String streamId) async {}

  @override
  Future<ManifestStatus> manifestStatus(String streamId) =>
      throw UnimplementedError();
}

class _FakeTrackRepository implements TrackRepository {
  _FakeTrackRepository({this.publicTracks = const []});

  final List<PublicTrack> publicTracks;

  @override
  Future<Track> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    bool isPublic = false,
    void Function(double progress)? onProgress,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<PublicTrack>> listPublicTracks({int? limit}) async => publicTracks;

  @override
  Future<void> deleteTrack(String id) async {}

  @override
  Future<void> updateVisibility(String id, {required bool isPublic}) async {}
}

class _FakeRecommendationRepository implements RecommendationRepository {
  _FakeRecommendationRepository({this.items = const []});

  final List<RecommendedTrack> items;

  @override
  Future<List<RecommendedTrack>> fetch() async => items;
}

PlaylistQueueController _queueController(FakeQueuePlaybackService service) {
  return PlaylistQueueController(
    service: service,
    token: ({bool forceRefresh = false}) async => 'jwt',
  );
}

Widget _harness({
  List<RecommendedTrack> recommendations = const [],
  List<PublicTrack> publicTracks = const [],
  PlaylistQueueController? queue,
  bool isAuthenticated = true,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DiscoverNotifier>.value(
        value: DiscoverNotifier(
          _FakeStreamRepository(),
          _FakeTrackRepository(publicTracks: publicTracks),
        ),
      ),
      ChangeNotifierProvider<PlaylistQueueController>.value(
        value: queue ?? _queueController(FakeQueuePlaybackService()),
      ),
    ],
    child: MaterialApp(
      home: DiscoverScreen(
        recommendationRepository:
            _FakeRecommendationRepository(items: recommendations),
        isAuthenticated: isAuthenticated,
      ),
    ),
  );
}

RecommendedTrack _reco(String id, {String reason = 'Raison'}) => RecommendedTrack(
      track: Track(id: id, title: 'Titre $id', artist: 'A', durationS: 100),
      reason: reason,
    );

void main() {
  group('DiscoverScreen — Pour toi', () {
    testWidgets('affiche « Pour toi » avec la raison de chaque recommandation',
        (tester) async {
      await tester.pumpWidget(_harness(
        recommendations: [_reco('r-1', reason: 'Parce que vous écoutez A')],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pour toi'), findsOneWidget);
      expect(find.byKey(const Key('reco_tile_r-1')), findsOneWidget);
      expect(find.text('Parce que vous écoutez A'), findsOneWidget);
    });

    testWidgets('plafonne « Pour toi » aux 8 premières recommandations',
        (tester) async {
      // Surface haute : les 8 tuiles tiennent à l'écran, l'absence de r-9/r-10
      // prouve le plafond (et non un simple hors-champ de la liste paresseuse).
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(
        recommendations: [for (var i = 1; i <= 10; i++) _reco('r-$i')],
      ));
      await tester.pumpAndSettle();

      // Les 8 premières (en haut de la liste) sont là.
      for (var i = 1; i <= 8; i++) {
        expect(find.byKey(Key('reco_tile_r-$i')), findsOneWidget,
            reason: 'r-$i devrait être affichée');
      }
      // Les suivantes sont écartées.
      expect(find.byKey(const Key('reco_tile_r-9')), findsNothing);
      expect(find.byKey(const Key('reco_tile_r-10')), findsNothing);
    });

    testWidgets('un appui sur « Pour toi » lance la liste plafonnée',
        (tester) async {
      final service = FakeQueuePlaybackService();
      final queue = _queueController(service);
      addTearDown(queue.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_harness(
        queue: queue,
        recommendations: [for (var i = 1; i <= 10; i++) _reco('r-$i')],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reco_tile_r-2')));
      await tester.pumpAndSettle();

      // Seules les 8 premières partent en file, à partir de l'item touché.
      expect(service.lastItems.length, 8);
      expect(service.lastItems.first.id, 'r-1');
      expect(service.lastItems.last.id, 'r-8');
      expect(service.lastInitialIndex, 1);
      expect(queue.sourceName, 'Pour toi');
      expect(queue.playlistId, isNull,
          reason: '« Pour toi » n\'est pas une playlist');
    });

    testWidgets('invité : « Pour toi » n\'est pas chargée', (tester) async {
      await tester.pumpWidget(_harness(
        isAuthenticated: false,
        recommendations: [_reco('r-1')],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pour toi'), findsNothing);
      expect(find.byKey(const Key('reco_tile_r-1')), findsNothing);
    });

    testWidgets('sans recommandation ni contenu public : rien à découvrir',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('Rien à découvrir pour le moment'), findsOneWidget);
      expect(find.text('Pour toi'), findsNothing);
    });

    testWidgets('replier « Pour toi » masque ses tuiles, redéplier les remontre',
        (tester) async {
      await tester.pumpWidget(_harness(
        recommendations: [_reco('r-1')],
      ));
      await tester.pumpAndSettle();

      // Déplié par défaut.
      expect(find.byKey(const Key('reco_tile_r-1')), findsOneWidget);

      // Replier via le titre de section.
      await tester.tap(find.text('Pour toi'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reco_tile_r-1')), findsNothing);
      expect(find.text('Pour toi'), findsOneWidget); // l'en-tête reste

      // Redéplier.
      await tester.tap(find.text('Pour toi'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reco_tile_r-1')), findsOneWidget);
    });
  });

  group('DiscoverScreen — recherche', () {
    testWidgets('filtre « Pour toi » par titre, et affiche « Aucun résultat »',
        (tester) async {
      await tester.pumpWidget(_harness(
        recommendations: [_reco('r-1'), _reco('r-2')],
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reco_tile_r-1')), findsOneWidget);
      expect(find.byKey(const Key('reco_tile_r-2')), findsOneWidget);

      // Une requête ne laisse que la piste dont le titre correspond.
      await tester.enterText(find.byType(TextField), 'r-2');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reco_tile_r-1')), findsNothing);
      expect(find.byKey(const Key('reco_tile_r-2')), findsOneWidget);

      // Une requête sans correspondance affiche l'état vide.
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Aucun résultat'), findsOneWidget);
    });

    testWidgets(
        'choisir une catégorie masque les pistes et affiche l\'état vide '
        'sans flux correspondant', (tester) async {
      await tester.pumpWidget(_harness(
        recommendations: [_reco('r-1')],
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reco_tile_r-1')), findsOneWidget);

      // Aucun flux dans le harness → sélectionner une catégorie ne laisse rien.
      await tester.tap(find.text('Musique'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reco_tile_r-1')), findsNothing);
      expect(find.text('Aucun résultat'), findsOneWidget);
    });
  });
}
