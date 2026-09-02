//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

// ignore: unused_import
import 'dart:convert';
import 'package:streampulse_api/src/deserialize.dart';
import 'package:dio/dio.dart';

import 'package:streampulse_api/src/model/error_response.dart';
import 'package:streampulse_api/src/model/recommended_track_response.dart';

class RecommendationApi {
  final Dio _dio;

  const RecommendationApi(this._dio);

  /// Recommend tracks based on the user&#39;s listening history.
  /// Returns tracks the authenticated user can play (their own tracks and other users&#39; public tracks), ranked by a simple content-based algorithm (US-09-04): never-played tracks first, then by affinity with the artists the user listens to most, then least-recently played. With no listening history yet, it falls back to the most recently added tracks (cold start) rather than an empty list. Each item carries a human-readable reason. Listening events are recorded server-side on track playback (GET /api/tracks/{id}/stream).
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [List<RecommendedTrackResponse>] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<List<RecommendedTrackResponse>>> recommendTracks({
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/recommendations/tracks';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{...?headers},
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {'type': 'http', 'scheme': 'bearer', 'name': 'bearerAuth'},
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    List<RecommendedTrackResponse>? _responseData;

    try {
      final rawData = _response.data;
      _responseData = rawData == null
          ? null
          : deserialize<
              List<RecommendedTrackResponse>,
              RecommendedTrackResponse
            >(rawData, 'List<RecommendedTrackResponse>', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<List<RecommendedTrackResponse>>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }
}
