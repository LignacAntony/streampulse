import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_error_mapper.dart';
import '../../domain/entities/manifest_status.dart';

class StreamRemoteDataSource {
  StreamRemoteDataSource(this._api, this._dio);

  final StreamingApi _api;

  /// Le Dio sous-jacent, pour la seule sonde de manifeste — cf. [manifestStatus]
  /// pour la raison. Même instance que celle de [_api] : aucun second chemin
  /// d'authentification n'est introduit.
  final Dio _dio;

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

  /// Sonde le manifeste HLS **public** du flux et rend le verdict du serveur.
  ///
  /// `validateStatus` accepte les <500 pour que 404/409 reviennent en réponse
  /// normale (pas d'exception → pas de log d'erreur parasite ; STR-109).
  ///
  /// ⚠️ **Volontairement hors du client généré**, contrairement au reste de ce
  /// fichier. `StreamingApi.streamPlaylist` est typé `Response<String>` pour le
  /// chemin nominal (le `.m3u8`), et sa désérialisation traverse un `case
  /// 'String': return '$value'` : un corps d'erreur JSON en ressort **stringifié
  /// à la Dart** (`{error: {code: stream_not_live}}`, sans guillemets), donc
  /// illisible par `jsonDecode`. Or c'est précisément ce corps qu'on vient
  /// chercher ici. Le Dio brut est le même instance que celui du client généré —
  /// mêmes intercepteurs (trace, auth, log), même `baseUrl` : la lecture
  /// propriétaire d'un flux privé continue de porter son `Bearer`.
  Future<ManifestStatus> manifestStatus(String streamId) async {
    try {
      final response = await _dio.get<dynamic>(
        ApiConstants.playlistPath(streamId),
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      switch (response.statusCode) {
        case 200:
          return ManifestStatus.available;
        // Flux absent, archivé, ou devenu privé : pour un auditeur, c'est fini.
        case 404:
          return ManifestStatus.ended;
        case 409:
          // Seule la fin de direct est un verdict définitif, et elle doit donc
          // être reconnue **explicitement**. Tout autre 409 — y compris un code
          // inconnu, face à un backend plus ancien que cette version — retombe
          // sur « pas encore prêt » : au pire l'auditeur attend le temps des
          // reconnexions bornées, alors que l'erreur inverse couperait un direct
          // en train de démarrer. C'est exactement le bug que STR-229 corrige,
          // on ne le réintroduit pas par le défaut.
          return _errorCode(response.data) == _codeStreamNotLive
              ? ManifestStatus.ended
              : ManifestStatus.notReady;
        default:
          return ManifestStatus.unknown; // 503 (capacité), 4xx inattendu…
      }
    } on DioException {
      return ManifestStatus.unknown; // réseau indéterminé → on ne conclut pas
    }
  }

  /// Code publié par le backend pour « aucune session live » (STR-229). Les
  /// deux valeurs sont documentées sur la réponse 409 de `openapi.yaml` ; seule
  /// celle-ci est décisive côté client, l'autre est le défaut.
  static const _codeStreamNotLive = 'stream_not_live';

  /// Extrait `error.code` d'un corps d'erreur, ou `null` si la forme n'est pas
  /// celle attendue. Tolérant par construction : un corps inattendu doit mener
  /// au défaut prudent, jamais à une exception dans une sonde de reprise.
  static String? _errorCode(dynamic data) {
    if (data is! Map) return null;
    final error = data['error'];
    if (error is! Map) return null;
    final code = error['code'];
    return code is String ? code : null;
  }
}
