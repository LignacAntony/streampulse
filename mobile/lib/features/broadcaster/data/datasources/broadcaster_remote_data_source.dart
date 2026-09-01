import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';

class BroadcasterRemoteDataSource {
  BroadcasterRemoteDataSource(this._api);

  final BroadcasterApi _api;

  Future<BroadcasterRequestResponse> create(String message) async {
    try {
      final response = await _api.createBroadcasterRequest(
        broadcasterRequestInput: BroadcasterRequestInput(message: message),
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      throw mapDioException(e, conflictMessage: 'Demande déjà en cours');
    }
  }

  Future<BroadcasterRequestResponse?> getMine() async {
    try {
      final response = await _api.getMyBroadcasterRequest();
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw mapDioException(e);
    }
  }

  /// Revue admin (routes `/api/admin/broadcaster-requests`).
  Future<List<BroadcasterRequestAdmin>> listAdmin({String? status}) async {
    try {
      final response = await _api.listBroadcasterRequests(status: status);
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body.requests;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<BroadcasterRequestResponse> approve(String id, String? note) async {
    try {
      final response = await _api.approveBroadcasterRequest(
        id: id,
        reviewRequestInput:
            note == null ? null : ReviewRequestInput(reviewNote: note),
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      throw mapDioException(e, conflictMessage: 'Demande déjà traitée');
    }
  }

  Future<BroadcasterRequestResponse> reject(String id, String? note) async {
    try {
      final response = await _api.rejectBroadcasterRequest(
        id: id,
        reviewRequestInput:
            note == null ? null : ReviewRequestInput(reviewNote: note),
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      throw mapDioException(e, conflictMessage: 'Demande déjà traitée');
    }
  }
}
