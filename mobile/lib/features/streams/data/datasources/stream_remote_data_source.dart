import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/network/dio_error_mapper.dart';

class StreamRemoteDataSource {
  StreamRemoteDataSource(this._api);

  final StreamingApi _api;

  Future<List<StreamSummaryResponse>> listLive({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _api.listStreams(limit: limit, offset: offset);
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<List<StreamSummaryResponse>> listFavorites() async {
    try {
      final response = await _api.listMyFavorites();
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> addFavorite(String streamId) async {
    try {
      await _api.addFavorite(id: streamId);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> removeFavorite(String streamId) async {
    try {
      await _api.removeFavorite(id: streamId);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Sonde le manifeste HLS **public** du flux pour déterminer s'il est terminé.
  /// 200 → toujours en direct (`false`) ; 404/409 → le manifeste n'est plus
  /// servi, le direct est terminé (`true`) ; toute autre issue (réseau, 5xx…) →
  /// indéterminé (`false`), on laisse la reconnexion réseau opérer (STR-118).
  Future<bool> isStreamEnded(String streamId) async {
    try {
      await _api.streamPlaylist(id: streamId);
      return false;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      return code == 404 || code == 409;
    }
  }
}
