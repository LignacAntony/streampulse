import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/entities/manifest_status.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/discover_notifier.dart';
import 'package:streampulse/features/tracks/domain/entities/public_track.dart';
import 'package:streampulse/features/tracks/domain/repositories/track_repository.dart';

/// Faux dépôt de flux : enregistre les filtres reçus, renvoie une liste fixe.
class _FakeStreamRepo implements StreamRepository {
  String? gotCategory;
  String? gotSearch;
  int listCalls = 0;
  List<LiveStream> toReturn = const [];
  bool shouldThrow = false;

  @override
  Future<List<LiveStream>> listLiveStreams({
    int limit = 20,
    int offset = 0,
    String? category,
    String? search,
  }) async {
    listCalls++;
    gotCategory = category;
    gotSearch = search;
    if (shouldThrow) throw Exception('boom');
    return toReturn;
  }

  @override
  Future<int?> streamListenerCount(String id) async => 0;
  @override
  Future<List<LiveStream>> listFavorites() async => const [];
  @override
  Future<void> addFavorite(String streamId) async {}
  @override
  Future<void> removeFavorite(String streamId) async {}
  @override
  Future<ManifestStatus> manifestStatus(String streamId) async =>
      ManifestStatus.available;
}

/// Faux dépôt de pistes : compte les appels, renvoie une liste fixe.
class _FakeTrackRepo implements TrackRepository {
  int publicCalls = 0;
  List<PublicTrack> toReturn = const [];

  @override
  Future<List<PublicTrack>> listPublicTracks({int? limit}) async {
    publicCalls++;
    return toReturn;
  }

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
  Future<void> deleteTrack(String id) async {}
  @override
  Future<void> updateVisibility(String id, {required bool isPublic}) async {}
}

LiveStream _live(String id) =>
    LiveStream(id: id, title: 'Flux $id', startedAt: DateTime(2026), status: 'live');

PublicTrack _track(String id) =>
    PublicTrack(id: id, title: 'Piste $id', artist: null, durationS: null, ownerName: 'kai');

void main() {
  group('DiscoverNotifier — filtres Découvrir', () {
    test('vue libre : charge flux ET pistes publiques, sans filtre', () async {
      final streams = _FakeStreamRepo()..toReturn = [_live('a')];
      final tracks = _FakeTrackRepo()..toReturn = [_track('t1')];
      final notifier = DiscoverNotifier(streams, tracks);

      await notifier.load();

      expect(streams.gotCategory, isNull);
      expect(streams.gotSearch, '');
      expect(tracks.publicCalls, 1);
      expect(notifier.streams, hasLength(1));
      expect(notifier.publicTracks, hasLength(1));
      expect(notifier.isFiltering, isFalse);
    });

    test('catégorie : transmise au dépôt, pistes publiques masquées', () async {
      final streams = _FakeStreamRepo()..toReturn = [_live('a')];
      final tracks = _FakeTrackRepo()..toReturn = [_track('t1')];
      final notifier = DiscoverNotifier(streams, tracks);

      await notifier.selectCategory('music');

      expect(streams.gotCategory, 'music');
      expect(notifier.isFiltering, isTrue);
      // L'endpoint des pistes n'a pas de filtre : on ne les charge pas en vue
      // filtrée pour ne pas laisser croire qu'elles y échappent.
      expect(tracks.publicCalls, 0);
      expect(notifier.publicTracks, isEmpty);
    });

    test('recherche : débouncée puis transmise au dépôt', () async {
      final streams = _FakeStreamRepo()..toReturn = [_live('a')];
      final tracks = _FakeTrackRepo();
      final notifier = DiscoverNotifier(streams, tracks);

      // Immédiat : l'état reflète la saisie, mais aucun appel réseau encore.
      notifier.onSearchChanged('aurora');
      expect(notifier.searchQuery, 'aurora');
      expect(streams.listCalls, 0);

      // Après le débounce, la recherche part vers le dépôt.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(streams.listCalls, 1);
      expect(streams.gotSearch, 'aurora');
      expect(notifier.isFiltering, isTrue);
    });

    test('erreur en vue filtrée : hasError vrai (les pistes ne comptent pas)',
        () async {
      final streams = _FakeStreamRepo()..shouldThrow = true;
      final tracks = _FakeTrackRepo();
      final notifier = DiscoverNotifier(streams, tracks);

      await notifier.selectCategory('talk');

      expect(notifier.hasError, isTrue);
      expect(tracks.publicCalls, 0);
    });
  });
}
