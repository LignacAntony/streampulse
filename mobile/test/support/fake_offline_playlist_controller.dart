import 'package:dio/dio.dart';
import 'package:streampulse/core/offline/entities/cached_track_status.dart';
import 'package:streampulse/core/offline/offline_cache_repository.dart';
import 'package:streampulse/core/offline/track_download_service.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/presentation/providers/offline_playlist_controller.dart';

class _NoopCacheRepository implements OfflineCacheRepository {
  @override
  Future<Set<String>> offlinePlaylistIds() async => {};
  @override
  Future<bool> isOffline(String playlistId) async => false;
  @override
  Future<void> enableOffline(
    String playlistId,
    String name,
    List<PlaylistTrack> tracks,
  ) async {}
  @override
  Future<void> disableOffline(String playlistId) async {}
  @override
  Future<List<PlaylistTrack>> cachedTracks(String playlistId) async => [];
  @override
  Future<List<CachedTrackStatus>> downloadStatuses(String playlistId) async =>
      [];
  @override
  Future<void> updateTrackStatus(
    String trackId,
    String playlistId, {
    required TrackCacheStatus status,
    String? filePath,
    int? fileSize,
  }) async {}
  @override
  Future<String?> cachedFilePath(String trackId) async => null;
  @override
  Future<int> totalCacheSize() async => 0;
  @override
  Future<void> clearAll() async {}
}

class FakeOfflinePlaylistController extends OfflinePlaylistController {
  FakeOfflinePlaylistController()
    : super(
        cacheRepository: _NoopCacheRepository(),
        downloadService: TrackDownloadService(Dio(), _NoopCacheRepository()),
      );

  @override
  Future<void> init() async {}

  @override
  bool isOffline(String playlistId) => false;

  @override
  double? downloadProgress(String playlistId) => null;

  @override
  List<CachedTrackStatus> trackStatuses(String playlistId) => const [];

  @override
  bool isDownloading(String playlistId) => false;

  @override
  Future<void> toggleOffline(
    String playlistId,
    String playlistName,
    List<PlaylistTrack> tracks,
  ) async {}

  @override
  Future<int> totalCacheSize() async => 0;

  @override
  Future<void> clearCache() async {}
}
