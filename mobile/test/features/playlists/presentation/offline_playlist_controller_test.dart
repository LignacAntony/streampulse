import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/offline/entities/cached_track_status.dart';
import 'package:streampulse/core/offline/entities/offline_playlist_summary.dart';
import 'package:streampulse/core/offline/offline_cache_repository.dart';
import 'package:dio/dio.dart';
import 'package:streampulse/core/offline/track_download_service.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/presentation/providers/offline_playlist_controller.dart';

PlaylistTrack _track(String id, int pos) => PlaylistTrack(
      id: id,
      title: 'T $id',
      artist: null,
      durationS: null,
      position: pos,
    );

class _FakeCacheRepository implements OfflineCacheRepository {
  final Set<String> _offlineIds = {};
  final Map<String, List<PlaylistTrack>> _tracks = {};
  final Map<String, Map<String, TrackCacheStatus>> _statuses = {};
  Object? enableError;

  @override
  Future<Set<String>> offlinePlaylistIds() async => Set.of(_offlineIds);

  @override
  Future<List<OfflinePlaylistSummary>> offlinePlaylists() async => [
        for (final id in _offlineIds)
          OfflinePlaylistSummary(
            id: id,
            name: id,
            trackCount: _tracks[id]?.length ?? 0,
          ),
      ];

  @override
  Future<bool> isOffline(String playlistId) async =>
      _offlineIds.contains(playlistId);

  @override
  Future<void> enableOffline(
    String playlistId,
    String name,
    List<PlaylistTrack> tracks,
  ) async {
    if (enableError != null) throw enableError!;
    _offlineIds.add(playlistId);
    _tracks[playlistId] = tracks;
    _statuses[playlistId] = {for (final t in tracks) t.id: TrackCacheStatus.pending};
  }

  @override
  Future<void> disableOffline(String playlistId) async {
    _offlineIds.remove(playlistId);
    _tracks.remove(playlistId);
    _statuses.remove(playlistId);
  }

  @override
  Future<List<PlaylistTrack>> cachedTracks(String playlistId) async =>
      _tracks[playlistId] ?? [];

  @override
  Future<List<CachedTrackStatus>> downloadStatuses(String playlistId) async {
    final map = _statuses[playlistId] ?? {};
    return map.entries
        .map((e) => CachedTrackStatus(
              trackId: e.key,
              status: e.value,
              progress: e.value == TrackCacheStatus.done ? 1.0 : 0.0,
            ))
        .toList();
  }

  @override
  Future<void> updateTrackStatus(
    String trackId,
    String playlistId, {
    required TrackCacheStatus status,
    String? filePath,
    int? fileSize,
  }) async {
    _statuses[playlistId]?[trackId] = status;
  }

  @override
  Future<String?> cachedFilePath(String trackId) async => null;

  @override
  Future<int> totalCacheSize() async => 0;

  @override
  Future<void> clearAll() async {
    _offlineIds.clear();
    _tracks.clear();
    _statuses.clear();
  }
}

class _FakeDownloadService extends TrackDownloadService {
  _FakeDownloadService(_FakeCacheRepository repo) : super(Dio(), repo);

  bool downloadCalled = false;
  bool cancelCalled = false;

  @override
  Future<void> downloadPlaylist(
    String playlistId,
    List<({String trackId, String title})> tracks, {
    void Function(String trackId, double progress)? onProgress,
  }) async {
    downloadCalled = true;
    for (final t in tracks) {
      onProgress?.call(t.trackId, 1.0);
    }
  }

  @override
  void cancelPlaylist(String playlistId) {
    cancelCalled = true;
  }
}

void main() {
  late _FakeCacheRepository repo;
  late _FakeDownloadService downloadService;
  late OfflinePlaylistController controller;

  setUp(() {
    repo = _FakeCacheRepository();
    downloadService = _FakeDownloadService(repo);
    controller = OfflinePlaylistController(
      cacheRepository: repo,
      downloadService: downloadService,
    );
  });

  tearDown(() => controller.dispose());

  group('toggleOffline', () {
    test('active le mode hors ligne et lance le téléchargement', () async {
      final tracks = [_track('t1', 0), _track('t2', 1)];

      await controller.toggleOffline('p1', 'Ma playlist', tracks);

      expect(controller.isOffline('p1'), isTrue);
      expect(downloadService.downloadCalled, isTrue);
    });

    test('désactive le mode hors ligne et annule le téléchargement', () async {
      final tracks = [_track('t1', 0)];
      await controller.toggleOffline('p1', 'Ma playlist', tracks);

      await controller.toggleOffline('p1', 'Ma playlist', tracks);

      expect(controller.isOffline('p1'), isFalse);
      expect(downloadService.cancelCalled, isTrue);
      expect(controller.downloadProgress('p1'), isNull);
    });

    test('erreur enableOffline : revert + expose l\'erreur', () async {
      repo.enableError = Exception('disque plein');
      final tracks = [_track('t1', 0)];

      await controller.toggleOffline('p1', 'Ma playlist', tracks);

      expect(controller.isOffline('p1'), isFalse);
      expect(controller.consumeError(), isNotNull);
    });

    test('consumeError efface l\'erreur après lecture', () async {
      repo.enableError = Exception('fail');
      await controller.toggleOffline('p1', 'P', [_track('t1', 0)]);

      controller.consumeError();
      expect(controller.consumeError(), isNull);
    });

    test('réentrance bloquée : second appel ignoré', () async {
      final tracks = [_track('t1', 0)];

      // Les deux appels démarrent ensemble.
      final f1 = controller.toggleOffline('p1', 'P', tracks);
      final f2 = controller.toggleOffline('p1', 'P', tracks);
      await Future.wait([f1, f2]);

      // Un seul toggle a été appliqué.
      expect(controller.isOffline('p1'), isTrue);
    });
  });

  group('clearCache', () {
    test('vide tout l\'état', () async {
      await controller.toggleOffline('p1', 'P', [_track('t1', 0)]);
      expect(controller.isOffline('p1'), isTrue);

      await controller.clearCache();

      expect(controller.isOffline('p1'), isFalse);
    });
  });
}
