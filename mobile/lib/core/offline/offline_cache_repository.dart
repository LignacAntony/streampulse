import '../../features/playlists/domain/entities/playlist_track.dart';
import 'entities/cached_track_status.dart';

abstract class OfflineCacheRepository {
  Future<Set<String>> offlinePlaylistIds();

  Future<bool> isOffline(String playlistId);

  Future<void> enableOffline(
    String playlistId,
    String name,
    List<PlaylistTrack> tracks,
  );

  Future<void> disableOffline(String playlistId);

  Future<List<PlaylistTrack>> cachedTracks(String playlistId);

  Future<List<CachedTrackStatus>> downloadStatuses(String playlistId);

  Future<void> updateTrackStatus(
    String trackId,
    String playlistId, {
    required TrackCacheStatus status,
    String? filePath,
    int? fileSize,
  });

  Future<String?> cachedFilePath(String trackId);

  Future<int> totalCacheSize();

  Future<void> clearAll();
}
