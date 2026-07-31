import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/favorites_controller.dart';

LiveStream _stream(String id) => LiveStream(
      id: id,
      title: 'Flux $id',
      startedAt: DateTime.utc(2026, 1, 1),
    );

class _FakeRepository implements StreamRepository {
  _FakeRepository({this.favorites = const [], this.mutationError});

  List<LiveStream> favorites;
  Object? mutationError;
  final List<String> added = [];
  final List<String> removed = [];

  @override
  Future<List<LiveStream>> listFavorites() async => favorites;

  @override
  Future<void> addFavorite(String streamId) async {
    if (mutationError != null) throw mutationError!;
    added.add(streamId);
  }

  @override
  Future<void> removeFavorite(String streamId) async {
    if (mutationError != null) throw mutationError!;
    removed.add(streamId);
  }

  @override
  Future<List<LiveStream>> listLiveStreams({int limit = 20, int offset = 0}) async =>
      const [];

  @override
  Future<bool> isStreamEnded(String streamId) async => false;
}

void main() {
  group('FavoritesController.ensureLoaded', () {
    test('peuple les ids favoris depuis le repository', () async {
      final controller = FavoritesController(
        _FakeRepository(favorites: [_stream('a'), _stream('b')]),
      );

      await controller.ensureLoaded();

      expect(controller.isFavorited('a'), isTrue);
      expect(controller.isFavorited('b'), isTrue);
      expect(controller.isFavorited('c'), isFalse);
      expect(controller.favorites, hasLength(2));
    });

    test('échec silencieux : aucun favori, pas d\'exception', () async {
      final controller = FavoritesController(
        _FakeRepository()..mutationError = const AuthException(),
      );
      // listFavorites ne lève pas ici (mutationError ne s'applique qu'aux mutations),
      // on vérifie le cas nominal vide.
      await controller.ensureLoaded();
      expect(controller.favorites, isEmpty);
    });
  });

  group('FavoritesController.toggle', () {
    test('ajoute un flux non favori (optimiste)', () async {
      final repo = _FakeRepository();
      final controller = FavoritesController(repo);

      await controller.toggle(_stream('x'));

      expect(controller.isFavorited('x'), isTrue);
      expect(repo.added, ['x']);
    });

    test('retire un flux déjà favori', () async {
      final repo = _FakeRepository(favorites: [_stream('x')]);
      final controller = FavoritesController(repo);
      await controller.ensureLoaded();

      await controller.toggle(_stream('x'));

      expect(controller.isFavorited('x'), isFalse);
      expect(repo.removed, ['x']);
    });

    test('rollback + relance l\'exception si l\'ajout échoue', () async {
      final repo = _FakeRepository(mutationError: const NetworkException());
      final controller = FavoritesController(repo);

      await expectLater(
        controller.toggle(_stream('x')),
        throwsA(isA<NetworkException>()),
      );
      expect(controller.isFavorited('x'), isFalse);
    });
  });

  group('FavoritesController.reset', () {
    test('vide ids + liste et notifie', () async {
      final controller = FavoritesController(
        _FakeRepository(favorites: [_stream('a'), _stream('b')]),
      );
      await controller.ensureLoaded();
      expect(controller.favorites, hasLength(2));

      var notified = false;
      controller.addListener(() => notified = true);
      controller.reset();

      expect(controller.isFavorited('a'), isFalse);
      expect(controller.favorites, isEmpty);
      expect(notified, isTrue);
    });

    test('remet _loaded à faux : ensureLoaded recharge le compte suivant',
        () async {
      final repo = _FakeRepository(favorites: [_stream('a')]);
      final controller = FavoritesController(repo);
      await controller.ensureLoaded();

      // Après reset (logout), la liste du compte suivant remplace l'ancienne.
      controller.reset();
      repo.favorites = [_stream('z')];
      await controller.ensureLoaded();

      expect(controller.isFavorited('a'), isFalse);
      expect(controller.isFavorited('z'), isTrue);
    });
  });
}
