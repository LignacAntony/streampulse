import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/favorites_controller.dart';
import 'package:streampulse/features/streams/presentation/screens/stream_player_screen.dart';

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
}

Widget _harness({
  required String streamId,
  LiveStream? stream,
  required _FakeStreamRepository repo,
  required FavoritesController controller,
}) {
  return ChangeNotifierProvider<FavoritesController>.value(
    value: controller,
    child: ToastificationWrapper(
      child: MaterialApp(
        home: StreamPlayerScreen(streamId: streamId, stream: stream),
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
}
