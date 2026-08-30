import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/recommendations/domain/entities/recommended_track.dart';
import 'package:streampulse/features/recommendations/domain/repositories/recommendation_repository.dart';
import 'package:streampulse/features/recommendations/presentation/providers/recommendations_controller.dart';

class _FakeRepo implements RecommendationRepository {
  _FakeRepo({this.items = const [], this.error});

  final List<RecommendedTrack> items;
  final Object? error;
  int calls = 0;

  @override
  Future<List<RecommendedTrack>> fetch() async {
    calls++;
    if (error != null) throw error!;
    return items;
  }
}

RecommendedTrack _reco(String id) => RecommendedTrack(
      track: Track(id: id, title: 'T$id', artist: 'A', durationS: 100),
      reason: 'raison',
    );

void main() {
  test('load remplit items et hasItems', () async {
    final controller = RecommendationsController(
      _FakeRepo(items: [_reco('1'), _reco('2')]),
    );

    expect(controller.hasItems, isFalse);
    await controller.load();

    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
    expect(controller.items, hasLength(2));
    expect(controller.hasItems, isTrue);
  });

  test('load sur liste vide : pas d\'items, pas d\'erreur', () async {
    final controller = RecommendationsController(_FakeRepo(items: const []));
    await controller.load();

    expect(controller.hasItems, isFalse);
    expect(controller.error, isNull);
  });

  test('erreur réseau → error + isNetworkError', () async {
    final controller = RecommendationsController(
      _FakeRepo(error: const NetworkException()),
    );
    await controller.load();

    expect(controller.error, 'Pas de connexion réseau');
    expect(controller.isNetworkError, isTrue);
    expect(controller.hasItems, isFalse);
  });

  test('erreur serveur → message générique, pas isNetworkError', () async {
    final controller = RecommendationsController(
      _FakeRepo(error: const ServerException('boom')),
    );
    await controller.load();

    expect(controller.error, 'Impossible de charger les recommandations');
    expect(controller.isNetworkError, isFalse);
  });

  test('refresh rappelle le repository', () async {
    final repo = _FakeRepo(items: [_reco('1')]);
    final controller = RecommendationsController(repo);
    await controller.load();
    await controller.refresh();
    expect(repo.calls, 2);
  });
}
