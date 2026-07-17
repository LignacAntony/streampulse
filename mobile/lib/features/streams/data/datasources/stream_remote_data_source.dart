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
}
