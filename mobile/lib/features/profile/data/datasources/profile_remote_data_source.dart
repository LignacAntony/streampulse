import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../models/user_profile_model.dart';

/// Le token JWT est injecté automatiquement par l'intercepteur de [DioClient]
/// (refresh sur 401 transparent) — aucune gestion manuelle ici.
class ProfileRemoteDataSource {
  ProfileRemoteDataSource(this._dioClient);

  final DioClient _dioClient;

  Future<UserProfileModel> getMe() async {
    try {
      final response = await _dioClient.dio.get<Map<String, dynamic>>(
        ApiConstants.me,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return UserProfileModel.fromJson(body);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<UserProfileModel> update(UserProfileModel profile) async {
    try {
      final response = await _dioClient.dio.put<Map<String, dynamic>>(
        ApiConstants.me,
        data: profile.toUpdateJson(),
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return UserProfileModel.fromJson(body);
    } on DioException catch (e) {
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
