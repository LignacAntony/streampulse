import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';
import '../mappers/broadcast_dto_mappers.dart';

/// Appels HTTP du tableau de bord diffuseur (STR-153), via le client généré
/// depuis la spec OpenAPI.
class BroadcastRemoteDataSource {
  BroadcastRemoteDataSource(this._api);

  final StreamingApi _api;

  /// Le contrat OpenAPI garantit un `StreamResponse` sur les mutations : un
  /// corps vide signale un backend hors contrat, pas un cas métier.
  static const String _emptyBody = 'Réponse serveur inattendue';

  /// `GET /api/users/me/streams` — seule liste qui porte les secrets du
  /// propriétaire. Un utilisateur sans flux reçoit `[]`, pas une erreur.
  Future<List<StreamResponse>> listMyStreams() async {
    try {
      final response = await _api.listMyStreams();
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<StreamResponse> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) async {
    try {
      final response = await _api.createStream(
        createStreamRequest: CreateStreamRequest(
          title: title,
          isPublic: isPublic,
          description: description,
          category: streamCategoryToDto(category),
        ),
      );
      return response.data ?? (throw const ServerException(_emptyBody));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Le 409 remonte tel quel : c'est l'écran qui décide du message, pour ne pas
  /// relayer la formulation anglaise du serveur (« you already have a live
  /// stream ») dans une interface française.
  Future<StreamResponse> startStream(String id) async {
    try {
      final response = await _api.startStream(id: id);
      return response.data ?? (throw const ServerException(_emptyBody));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<StreamResponse> stopStream(String id) async {
    try {
      final response = await _api.stopStream(id: id);
      return response.data ?? (throw const ServerException(_emptyBody));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `DELETE /api/streams/{id}` — 204 sans corps.
  Future<void> deleteStream(String id) async {
    try {
      await _api.deleteStream(id: id);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
