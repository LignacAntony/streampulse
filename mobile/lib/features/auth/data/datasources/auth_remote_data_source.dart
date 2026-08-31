import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/exceptions.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._authApi, this._dio);

  final AuthApi _authApi;

  /// Dio sous-jacent (mêmes intercepteurs auth/trace que le client généré).
  /// Utilisé pour la connexion Google, écrite à la main plutôt que via le client
  /// généré, comme les autres endpoints bonus (reco, sonde de manifeste).
  final Dio _dio;

  Future<UserResponse> register({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _authApi.register(
        registerRequest: RegisterRequest(
          email: email,
          username: username,
          password: password,
        ),
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

  Future<void> requestPasswordReset({required String email}) async {
    try {
      await _authApi.forgotPassword(
        forgotPasswordRequest: ForgotPasswordRequest(email: email),
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _authApi.resetPassword(
        resetPasswordRequest: ResetPasswordRequest(
          token: token,
          password: newPassword,
        ),
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<void> logout({required String refreshToken}) async {
    try {
      await _authApi.logout(
        logoutRequest: LogoutRequest(refreshToken: refreshToken),
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<void> deleteAccount({required String password}) async {
    try {
      await _authApi.deleteAccount(
        deleteAccountRequest: DeleteAccountRequest(password: password),
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<TokenPairResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _authApi.login(
        loginRequest: LoginRequest(email: email, password: password),
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

  Future<TokenPairResponse> loginWithGoogle({required String idToken}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.googleLogin,
        data: {'id_token': idToken},
      );

      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return TokenPairResponse.fromJson(body);
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
        return const AuthException('Email ou mot de passe incorrect');
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
