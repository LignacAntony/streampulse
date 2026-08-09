import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';

/// Encapsule le `TrackApi` généré pour l'upload multipart (US-05-01) et traduit
/// les `DioException` en exceptions typées (cf. `mapDioException`).
///
/// La méthode générée `uploadTrack` porte déjà `MultipartFile` + `onSendProgress`
/// (la route est déclarée `multipart/form-data` dans la spec OpenAPI) : le Bearer
/// est injecté par l'intercepteur du `DioClient`, inutile de descendre au Dio brut.
class TrackRemoteDataSource {
  TrackRemoteDataSource(this._api);

  final TrackApi _api;

  Future<TrackResponse> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final file = await MultipartFile.fromFile(filePath, filename: filename);
      final response = await _api.uploadTrack(
        file: file,
        title: title,
        artist: artist,
        durationS: durationS,
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
}
