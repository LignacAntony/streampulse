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

  /// Sonde le manifeste HLS **public** du flux : `true` si le manifeste n'est
  /// plus servi (404/409), `false` sinon (200 en direct, ou réseau indéterminé).
  ///
  /// ⚠️ Le 409 est **ambigu** côté backend : il couvre aussi bien un flux
  /// terminé qu'un flux live dont le manifeste n'est **pas encore prêt** (fenêtre
  /// de démarrage ~10 s). L'appelant ([AudioPlayerController]) lève cette
  /// ambiguïté en ne concluant « terminé » que si la lecture avait démarré.
  ///
  /// `validateStatus` accepte les <500 pour que 404/409 reviennent en réponse
  /// normale (pas d'exception → pas de log d'erreur parasite ; STR-109).
  Future<bool> isManifestUnavailable(String streamId) async {
    try {
      final response = await _api.streamPlaylist(
        id: streamId,
        validateStatus: (status) => status != null && status < 500,
      );
      final code = response.statusCode;
      return code == 404 || code == 409;
    } on DioException {
      return false; // réseau indéterminé → on ne conclut pas
    }
  }
}
