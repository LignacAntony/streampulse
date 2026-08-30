import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';

class TrackRemoteDataSource {
  TrackRemoteDataSource(this._api);

  final TrackApi _api;

  Future<TrackResponse> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    bool isPublic = false,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final file = await MultipartFile.fromFile(filePath, filename: filename);
      final response = await _api.uploadTrack(
        file: file,
        title: title,
        artist: artist,
        durationS: durationS,
        isPublic: isPublic,
        onSendProgress: onSendProgress,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<List<PublicTrackResponse>> listPublicTracks({int? limit}) async {
    try {
      final response = await _api.listPublicTracks(limit: limit);
      return response.data ?? [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> deleteTrack(String id) async {
    try {
      await _api.deleteTrack(id: id);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> updateVisibility(String id, {required bool isPublic}) async {
    try {
      await _api.updateTrackVisibility(
        id: id,
        updateTrackVisibilityRequest: UpdateTrackVisibilityRequest(
          isPublic: isPublic,
        ),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
