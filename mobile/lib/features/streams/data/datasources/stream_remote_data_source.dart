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
}
