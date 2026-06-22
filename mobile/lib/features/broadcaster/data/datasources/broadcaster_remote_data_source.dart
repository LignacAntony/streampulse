import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';

/// Accès réseau aux endpoints « demande de rôle diffuseur ».
///
/// Le `Bearer` est injecté par l'intercepteur de `DioClient` (refresh 401
/// transparent) — `BroadcasterApi` est branché sur ce `Dio`.
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
      throw _mapDioException(e);
    }
  }

  /// Retourne `null` sur 404 : l'utilisateur n'a jamais soumis de demande.
  Future<BroadcasterRequestResponse?> getMine() async {
    try {
      final response = await _api.getMyBroadcasterRequest();
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _mapDioException(e);
    }
  }

  Exception _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return const NetworkException();
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        return _mapHttpStatus(e);
    }
  }

  Exception _mapHttpStatus(DioException e) {
    final status = e.response?.statusCode;
    final serverMessage = _serverErrorMessage(e.response?.data);

    switch (status) {
      case 400:
        return ValidationException(serverMessage ?? 'Champs invalides');
      case 401:
        return const AuthException();
      case 409:
        return ConflictException(serverMessage ?? 'Demande déjà en cours');
      case null:
        return const NetworkException();
      default:
        return ServerException(serverMessage ?? 'Erreur serveur ($status)');
    }
  }

  String? _serverErrorMessage(Object? body) {
    if (body is! Map<String, dynamic>) return null;
    final value = body['error'];
    if (value is String && value.isNotEmpty) return value;
    if (value is Map<String, dynamic>) {
      final msg = value['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    return null;
  }
}
