import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/entities/manifest_status.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/stream_notifier.dart';

LiveStream _stream(String id) => LiveStream(
      id: id,
      title: 'Flux $id',
      startedAt: DateTime.utc(2026, 1, 1),
    );

class _FakeRepository implements StreamRepository {
  _FakeRepository({this.result = const [], this.error});

  List<LiveStream> result;
  Object? error;
  int calls = 0;

  @override
  Future<List<LiveStream>> listLiveStreams({
    int limit = 20,
    int offset = 0,
    String? category,
    String? search,
  }) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<List<LiveStream>> listFavorites() async => const [];

  @override
  Future<void> addFavorite(String streamId) async {}

  @override
  Future<void> removeFavorite(String streamId) async {}

  @override
  Future<int?> streamListenerCount(String id) async => 0;

  @override
  Future<ManifestStatus> manifestStatus(String streamId) async =>
      ManifestStatus.available;
}

class _PagingRepository implements StreamRepository {
  _PagingRepository(this.total);

  final int total;

  @override
  Future<List<LiveStream>> listLiveStreams({
    int limit = 20,
    int offset = 0,
    String? category,
    String? search,
  }) async {
    if (offset >= total) return const [];
    final end = (offset + limit).clamp(0, total);
    return [for (var i = offset; i < end; i++) _stream('$i')];
  }

  @override
  Future<List<LiveStream>> listFavorites() async => const [];

  @override
  Future<void> addFavorite(String streamId) async {}

  @override
  Future<void> removeFavorite(String streamId) async {}

  @override
  Future<int?> streamListenerCount(String id) async => 0;

  @override
  Future<ManifestStatus> manifestStatus(String streamId) async =>
      ManifestStatus.available;
}

void main() {
  group('StreamNotifier.load', () {
    test('succès avec flux : expose la liste, isEmpty faux', () async {
      final notifier = StreamNotifier(
        _FakeRepository(result: [_stream('a'), _stream('b')]),
      );

      await notifier.load();

      expect(notifier.streams, hasLength(2));
      expect(notifier.isLoading, isFalse);
      expect(notifier.hasError, isFalse);
      expect(notifier.isEmpty, isFalse);
    });

    test('succès sans flux : isEmpty vrai (état vide)', () async {
      final notifier = StreamNotifier(_FakeRepository(result: const []));

      await notifier.load();

      expect(notifier.streams, isEmpty);
      expect(notifier.isEmpty, isTrue);
      expect(notifier.hasError, isFalse);
    });

    test('échec réseau sans donnée : hasError vrai, ne relance pas', () async {
      final notifier = StreamNotifier(
        _FakeRepository(error: const NetworkException()),
      );

      await expectLater(notifier.load(), completes);

      expect(notifier.hasError, isTrue);
      expect(notifier.streams, isEmpty);
      expect(notifier.isEmpty, isFalse);
    });
  });

  group('StreamNotifier.refresh', () {
    test('conserve les flux déjà chargés si un rafraîchissement échoue', () async {
      final repo = _FakeRepository(result: [_stream('a')]);
      final notifier = StreamNotifier(repo);
      await notifier.load();
      expect(notifier.streams, hasLength(1));

      repo.error = const NetworkException();
      await notifier.refresh();

      expect(notifier.streams, hasLength(1));
      expect(notifier.hasError, isTrue);
    });
  });

  group('StreamNotifier.loadMore', () {
    test('page pleine au chargement : hasMore vrai', () async {
      final notifier = StreamNotifier(_PagingRepository(25));

      await notifier.load();

      expect(notifier.streams, hasLength(StreamNotifier.pageSize));
      expect(notifier.hasMore, isTrue);
    });

    test('moins d\'une page : hasMore faux', () async {
      final notifier = StreamNotifier(_PagingRepository(5));

      await notifier.load();

      expect(notifier.streams, hasLength(5));
      expect(notifier.hasMore, isFalse);
    });

    test('loadMore ajoute la page suivante puis signale la fin', () async {
      final notifier = StreamNotifier(_PagingRepository(25));
      await notifier.load();

      await notifier.loadMore();

      expect(notifier.streams, hasLength(25));
      expect(notifier.hasMore, isFalse);
    });

    test('loadMore sans page suivante ne fait rien', () async {
      final notifier = StreamNotifier(_PagingRepository(5));
      await notifier.load();

      await notifier.loadMore();

      expect(notifier.streams, hasLength(5));
      expect(notifier.isLoadingMore, isFalse);
    });
  });

  group('StreamNotifier — armement du polling', () {
    test('startPolling rafraîchit immédiatement', () async {
      // Sans ce rafraîchissement, revenir sur l'onglet Accueil laisse la liste
      // périmée jusqu'au premier tick du timer (10 s).
      final repository = _FakeRepository(result: [_stream('a')]);
      final notifier = StreamNotifier(repository);
      await notifier.load();
      final callsAfterLoad = repository.calls;

      notifier.startPolling();
      await Future<void>.delayed(Duration.zero);

      expect(repository.calls, callsAfterLoad + 1);
      notifier.stopPolling();
    });

    test('pas de rafraîchissement immédiat si un chargement est en vol',
        () async {
      // Cas du démarrage de l'app : `load()` part juste avant `startPolling()`
      // dans le postFrameCallback de HomeScreen — doubler la requête initiale
      // serait du gaspillage.
      final repository = _FakeRepository(result: [_stream('a')]);
      final notifier = StreamNotifier(repository);

      final loading = notifier.load(); // non attendu : reste en vol
      notifier.startPolling();
      await loading;

      expect(repository.calls, 1);
      notifier.stopPolling();
    });

    test('startPolling répété n\'empile ni timer ni requête', () async {
      final repository = _FakeRepository(result: [_stream('a')]);
      final notifier = StreamNotifier(repository);
      await notifier.load();
      final callsAfterLoad = repository.calls;

      notifier.startPolling();
      await Future<void>.delayed(Duration.zero);
      // `_syncPolling` est rappelé à chaque changement de route : les appels
      // suivants doivent être des no-op tant que le timer tourne.
      notifier.startPolling();
      notifier.startPolling();
      await Future<void>.delayed(Duration.zero);

      expect(repository.calls, callsAfterLoad + 1);
      notifier.stopPolling();
    });
  });
}
