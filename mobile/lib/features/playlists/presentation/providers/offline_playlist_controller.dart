import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/offline/entities/cached_track_status.dart';
import '../../../../core/offline/offline_cache_repository.dart';
import '../../../../core/offline/track_download_service.dart';
import '../../domain/entities/playlist_track.dart';

class OfflinePlaylistController extends ChangeNotifier {
  OfflinePlaylistController({
    required OfflineCacheRepository cacheRepository,
    required TrackDownloadService downloadService,
  })  : _cacheRepository = cacheRepository,
        _downloadService = downloadService;

  final OfflineCacheRepository _cacheRepository;
  final TrackDownloadService _downloadService;

  Set<String> _offlineIds = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, List<CachedTrackStatus>> _trackStatuses = {};
  bool _disposed = false;

  bool isOffline(String playlistId) => _offlineIds.contains(playlistId);

  double? downloadProgress(String playlistId) =>
      _downloadProgress[playlistId];

  List<CachedTrackStatus> trackStatuses(String playlistId) =>
      _trackStatuses[playlistId] ?? const [];

  bool isDownloading(String playlistId) =>
      _downloadProgress.containsKey(playlistId) &&
      _downloadProgress[playlistId]! < 1.0;

  Future<void> init() async {
    _offlineIds = await _cacheRepository.offlinePlaylistIds();

    for (final id in _offlineIds) {
      final statuses = await _cacheRepository.downloadStatuses(id);
      _trackStatuses[id] = statuses;

      final hasPending =
          statuses.any((s) => s.status != TrackCacheStatus.done);
      if (hasPending) {
        final done =
            statuses.where((s) => s.status == TrackCacheStatus.done).length;
        _downloadProgress[id] =
            statuses.isEmpty ? 0.0 : done / statuses.length;
        _resumeDownload(id);
      }
    }

    if (!_disposed) notifyListeners();
  }

  Future<void> toggleOffline(
    String playlistId,
    String playlistName,
    List<PlaylistTrack> tracks,
  ) async {
    if (_offlineIds.contains(playlistId)) {
      _downloadService.cancelPlaylist(playlistId);
      await _cacheRepository.disableOffline(playlistId);
      _offlineIds.remove(playlistId);
      _downloadProgress.remove(playlistId);
      _trackStatuses.remove(playlistId);
      if (!_disposed) notifyListeners();
      return;
    }

    await _cacheRepository.enableOffline(playlistId, playlistName, tracks);
    _offlineIds.add(playlistId);

    final statuses = await _cacheRepository.downloadStatuses(playlistId);
    _trackStatuses[playlistId] = statuses;
    final done =
        statuses.where((s) => s.status == TrackCacheStatus.done).length;
    _downloadProgress[playlistId] =
        statuses.isEmpty ? 1.0 : done / statuses.length;
    if (!_disposed) notifyListeners();

    await _startDownload(playlistId, tracks);
  }

  Future<void> _startDownload(
    String playlistId,
    List<PlaylistTrack> tracks,
  ) async {
    final trackInfos = tracks
        .map((t) => (trackId: t.id, title: t.title))
        .toList();

    await _downloadService.downloadPlaylist(
      playlistId,
      trackInfos,
      onProgress: (trackId, progress) {
        if (_disposed) return;
        _updateTrackProgress(playlistId, trackId, progress);
      },
    );

    if (_disposed) return;
    _downloadProgress.remove(playlistId);
    final finalStatuses =
        await _cacheRepository.downloadStatuses(playlistId);
    _trackStatuses[playlistId] = finalStatuses;
    if (!_disposed) notifyListeners();
  }

  Future<void> _resumeDownload(String playlistId) async {
    final tracks = await _cacheRepository.cachedTracks(playlistId);
    await _startDownload(playlistId, tracks);
  }

  void _updateTrackProgress(
    String playlistId,
    String trackId,
    double progress,
  ) {
    final statuses = _trackStatuses[playlistId];
    if (statuses == null) return;

    final updated = statuses.map((s) {
      if (s.trackId != trackId) return s;
      return CachedTrackStatus(
        trackId: trackId,
        status: progress >= 1.0
            ? TrackCacheStatus.done
            : TrackCacheStatus.downloading,
        progress: progress,
      );
    }).toList();

    _trackStatuses[playlistId] = updated;

    final doneCount =
        updated.where((s) => s.status == TrackCacheStatus.done).length;
    final downloading = updated.where(
      (s) => s.status == TrackCacheStatus.downloading,
    );
    final partialProgress = downloading.isEmpty
        ? 0.0
        : downloading.map((s) => s.progress).reduce((a, b) => a + b);
    _downloadProgress[playlistId] =
        updated.isEmpty ? 1.0 : (doneCount + partialProgress) / updated.length;

    if (!_disposed) notifyListeners();
  }

  Future<int> totalCacheSize() => _cacheRepository.totalCacheSize();

  Future<void> clearCache() async {
    for (final id in _offlineIds) {
      _downloadService.cancelPlaylist(id);
    }
    await _cacheRepository.clearAll();
    _offlineIds.clear();
    _downloadProgress.clear();
    _trackStatuses.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
