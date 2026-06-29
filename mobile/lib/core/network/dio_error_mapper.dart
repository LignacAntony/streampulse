import 'package:dio/dio.dart';

import '../errors/exceptions.dart';

Exception mapDioException(DioException e, {String? conflictMessage}) {
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
      return _mapHttpStatus(e, conflictMessage);
  }
}

Exception _mapHttpStatus(DioException e, String? conflictMessage) {
  final status = e.response?.statusCode;
  final serverMessage = _serverErrorMessage(e.response?.data);

  switch (status) {
    case 400:
      return ValidationException(serverMessage ?? 'Champs invalides');
    case 401:
      return const AuthException();
    case 409:
      return ConflictException(
        serverMessage ?? conflictMessage ?? 'Conflit avec une ressource existante',
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
