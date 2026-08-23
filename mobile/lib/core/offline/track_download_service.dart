import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/api_constants.dart';
import 'entities/cached_track_status.dart';
import 'offline_cache_repository.dart';

class TrackDownloadService {
  TrackDownloadService(this._dio, this._cacheRepository);

  final Dio _dio;
  final OfflineCacheRepository _cacheRepository;
  final Map<String, CancelToken> _cancelTokens = {};

  Future<void> downloadPlaylist(
    String playlistId,
    List<({String trackId, String title})> tracks, {
    void Function(String trackId, double progress)? onProgress,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[playlistId] = cancelToken;

    try {
      final root = await _getCacheRoot();

      for (final track in tracks) {
        if (cancelToken.isCancelled) break;

        final cached = await _cacheRepository.cachedFilePath(track.trackId);
        if (cached != null) {
          onProgress?.call(track.trackId, 1.0);
          continue;
        }

        await _cacheRepository.updateTrackStatus(
          track.trackId,
          playlistId,
          status: TrackCacheStatus.downloading,
        );

        final tmpPath = p.join(root, '${track.trackId}.tmp');
        final finalPath = p.join(root, '${track.trackId}.audio');

        try {
          await _dio.download(
            '${ApiConstants.baseUrl}${ApiConstants.tracks}/${track.trackId}/stream',
            tmpPath,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              if (total > 0) {
                onProgress?.call(track.trackId, received / total);
              }
            },
          );

          await File(tmpPath).rename(finalPath);
          final fileSize = await File(finalPath).length();

          await _cacheRepository.updateTrackStatus(
            track.trackId,
            playlistId,
            status: TrackCacheStatus.done,
            filePath: '${track.trackId}.audio',
            fileSize: fileSize,
          );
          onProgress?.call(track.trackId, 1.0);
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) break;
          final tmp = File(tmpPath);
          if (await tmp.exists()) await tmp.delete();
          await _cacheRepository.updateTrackStatus(
            track.trackId,
            playlistId,
            status: TrackCacheStatus.error,
          );
        }
      }
    } finally {
      _cancelTokens.remove(playlistId);
    }
  }

  void cancelPlaylist(String playlistId) {
    _cancelTokens[playlistId]?.cancel();
    _cancelTokens.remove(playlistId);
  }

  Future<String> _getCacheRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = p.join(dir.path, 'streampulse_cache', 'tracks');
    await Directory(root).create(recursive: true);
    return root;
  }
}
