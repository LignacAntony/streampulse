import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../models/token_pair_model.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dioClient);

  final DioClient _dioClient;

  Future<UserModel> register({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dioClient.dio.post<Map<String, dynamic>>(
        ApiConstants.register,
        data: {
          'email': email,
          'username': username,
          'password': password,
        },
      );

      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return UserModel.fromJson(body);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<TokenPairModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dioClient.dio.post<Map<String, dynamic>>(
        ApiConstants.login,
        data: {
          'email': email,
          'password': password,
        },
      );

      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return TokenPairModel.fromJson(body);
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
        return AuthException(
          serverMessage ?? 'Email ou mot de passe incorrect',
        );
      case 409:
        return DuplicateAccountException(
          serverMessage ?? 'Email ou pseudo déjà utilisé',
        );
      case null:
        return const NetworkException();
      default:
        return ServerException(serverMessage ?? 'Erreur serveur ($status)');
    }
  }

  String? _serverErrorMessage(Object? body) {
    if (body is Map<String, dynamic>) {
      final value = body['error'];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
