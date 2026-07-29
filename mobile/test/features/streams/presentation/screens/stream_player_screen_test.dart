import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';
import 'package:streampulse/features/streams/presentation/providers/favorites_controller.dart';
import 'package:streampulse/features/streams/presentation/screens/stream_player_screen.dart';

/// Contrôleur de lecture fake (sans just_audio) : pilotable par [status] pour
/// tester le rendu des états (STR-118), méthodes no-op.
class _FakePlaybackController extends PlaybackController {
  _FakePlaybackController([this._status = PlaybackStatus.idle]);

  final PlaybackStatus _status;

  @override
  PlaybackStatus get status => _status;
  @override
  bool get isPlaying => _status == PlaybackStatus.playing;
  @override
  bool get isBusy =>
      _status == PlaybackStatus.loading || _status == PlaybackStatus.buffering;
  @override
  bool get isReconnecting => _status == PlaybackStatus.reconnecting;
  @override
  bool get hasError => _status == PlaybackStatus.error;
  @override
  bool get isEnded => _status == PlaybackStatus.ended;
  @override
  double get volume => 1;
  @override
  Future<void> load(String streamId) async {}
  @override
  Future<void> togglePlayPause() async {}
  @override
  Future<void> setVolume(double value) async {}
}

/// Flux « réel » tel que renvoyé par le serveur (métadonnées complètes),
/// par opposition au placeholder créé en arrivée deep-link.
LiveStream _realStream(String id) => LiveStream(
      id: id,
      title: 'Vrai Titre',
      startedAt: DateTime.utc(2026, 1, 1),
      status: 'live',
    );

/// Fake configurable : `listFavorites` renvoie l'état courant (mutable), ce qui
/// permet de simuler la réconciliation serveur après un ajout.
class _FakeStreamRepository implements StreamRepository {
  _FakeStreamRepository({List<LiveStream> favorites = const []})
      : _favorites = favorites;

  List<LiveStream> _favorites;
  int listFavoritesCalls = 0;
  final List<String> added = [];
  final List<String> removed = [];

  @override
  Future<List<LiveStream>> listFavorites() async {
    listFavoritesCalls++;
    return _favorites;
  }

  @override
  Future<void> addFavorite(String streamId) async {
    added.add(streamId);
    // Le serveur connaît, lui, les vraies métadonnées : la prochaine
    // récupération de la liste renvoie le flux complet.
    _favorites = [_realStream(streamId)];
  }

  @override
  Future<void> removeFavorite(String streamId) async {
    removed.add(streamId);
    _favorites = const [];
  }

  @override
  Future<List<LiveStream>> listLiveStreams({
    int limit = 20,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<bool> isStreamEnded(String streamId) async => false;
}

Widget _harness({
  required String streamId,
  LiveStream? stream,
  required _FakeStreamRepository repo,
  required FavoritesController controller,
  PlaybackStatus playbackStatus = PlaybackStatus.idle,
}) {
  return ChangeNotifierProvider<FavoritesController>.value(
    value: controller,
    child: ToastificationWrapper(
      child: MaterialApp(
        home: StreamPlayerScreen(
          streamId: streamId,
          stream: stream,
          controller: _FakePlaybackController(playbackStatus),
        ),
      ),
    ),
  );
}

void main() {
  group('StreamPlayerScreen — réconciliation deep-link', () {
    testWidgets(
        'ajout en arrivée deep-link (sans métadonnées) : recharge la liste '
        'et remplace le placeholder par les vraies métadonnées', (tester) async {
      final repo = _FakeStreamRepository();
      final controller = FavoritesController(repo);
      await tester.pumpWidget(
        _harness(streamId: 's1', repo: repo, controller: controller),
      );
      await tester.pumpAndSettle(); // ensureLoaded (listFavorites #1 → vide)

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      // Ajout effectué, puis load() de réconciliation (listFavorites #2).
      expect(repo.added, ['s1']);
      expect(repo.listFavoritesCalls, 2);
      // La tuile fantôme 'Flux' a été remplacée par les vraies métadonnées.
      expect(controller.favorites.single.title, 'Vrai Titre');
      expect(controller.favorites.single.status, 'live');
    });

    testWidgets(
        'métadonnées déjà connues (navigation normale) : pas de rechargement '
        'superflu', (tester) async {
      final repo = _FakeStreamRepository();
      final controller = FavoritesController(repo);
      await tester.pumpWidget(
        _harness(
          streamId: 's1',
          stream: _realStream('s1'),
          repo: repo,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle(); // ensureLoaded (listFavorites #1)

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(repo.added, ['s1']);
      // Pas de load() de réconciliation : un seul appel (ensureLoaded initial).
      expect(repo.listFavoritesCalls, 1);
    });

    testWidgets('retrait : pas de rechargement de réconciliation',
        (tester) async {
      final repo = _FakeStreamRepository(favorites: [_realStream('s1')]);
      final controller = FavoritesController(repo);
      await tester.pumpWidget(
        _harness(streamId: 's1', repo: repo, controller: controller),
      );
      await tester.pumpAndSettle(); // ensureLoaded (listFavorites #1)

      // Le cœur est plein (déjà favori) → tap = retrait.
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(repo.removed, ['s1']);
      expect(repo.listFavoritesCalls, 1); // aucune réconciliation sur un retrait
    });
  });

  group('StreamPlayerScreen — états de lecture (STR-118)', () {
    testWidgets('reconnexion : affiche « Reconnexion… »', (tester) async {
      final repo = _FakeStreamRepository();
      await tester.pumpWidget(_harness(
        streamId: 's1',
        repo: repo,
        controller: FavoritesController(repo),
        playbackStatus: PlaybackStatus.reconnecting,
      ));
      await tester.pump();

      expect(find.text('Reconnexion…'), findsOneWidget);
    });

    testWidgets('erreur : « Flux indisponible » + bouton réessayer',
        (tester) async {
      final repo = _FakeStreamRepository();
      await tester.pumpWidget(_harness(
        streamId: 's1',
        repo: repo,
        controller: FavoritesController(repo),
        playbackStatus: PlaybackStatus.error,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Flux indisponible'), findsOneWidget);
      expect(find.byIcon(Icons.replay), findsOneWidget); // le play devient « réessayer »
    });

    testWidgets('flux terminé : « Le direct est terminé »', (tester) async {
      final repo = _FakeStreamRepository();
      await tester.pumpWidget(_harness(
        streamId: 's1',
        repo: repo,
        controller: FavoritesController(repo),
        playbackStatus: PlaybackStatus.ended,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Le direct est terminé'), findsOneWidget);
    });
  });
}
