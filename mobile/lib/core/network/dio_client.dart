import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import '../storage/secure_storage.dart';

class DioClient {
  DioClient(this._storage) {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Dio dédié au refresh : pas d'auth interceptor, évite la récursion sur 401.
    _refreshDio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.addAll([
      _authInterceptor(),
      _logInterceptor(),
    ]);
  }

  static const _retriedKey = '_retried';

  final SecureStorage _storage;
  late final Dio _dio;
  late final Dio _refreshDio;
  final _logger = Logger();


  Completer<bool>? _refreshing;

  Dio get dio => _dio;

  InterceptorsWrapper _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode != 401) {
          return handler.next(error);
        }

        final req = error.requestOptions;

        if (_isAuthEndpoint(req.path)) {
          return handler.next(error);
        }

        if (req.extra[_retriedKey] == true) {
          await _storage.clearTokens();
          return handler.next(error);
        }

        final ok = await _refreshTokensOnce();
        if (!ok) {
          await _storage.clearTokens();
          return handler.next(error);
        }

        try {
          final newToken = await _storage.getAccessToken();
          req.headers['Authorization'] = 'Bearer $newToken';
          req.extra[_retriedKey] = true;
          final retried = await _dio.fetch(req);
          return handler.resolve(retried);
        } on DioException catch (e) {
          return handler.next(e);
        }
      },
    );
  }

  bool _isAuthEndpoint(String path) {
    return path.endsWith(ApiConstants.refresh) ||
        path.endsWith(ApiConstants.login) ||
        path.endsWith(ApiConstants.logout) ||
        path.endsWith(ApiConstants.register);
  }

  /// Refresh sérialisé : si un refresh est déjà en cours, on attend son résultat.
  /// Renvoie true si la rotation a réussi.
  Future<bool> _refreshTokensOnce() async {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<bool>();
    _refreshing = completer;
    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null) {
        completer.complete(false);
        return false;
      }

      final resp = await _refreshDio.post<Map<String, dynamic>>(
        ApiConstants.refresh,
        data: {'refresh_token': refreshToken},
      );
      final body = resp.data;
      if (body == null) {
        completer.complete(false);
        return false;
      }
      final newAccess = body['access_token'] as String?;
      final newRefresh = body['refresh_token'] as String?;
      if (newAccess == null || newRefresh == null) {
        completer.complete(false);
        return false;
      }
      await _storage.saveAccessToken(newAccess);
      await _storage.saveRefreshToken(newRefresh);
      completer.complete(true);
      return true;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _refreshing = null;
    }
  }

  InterceptorsWrapper _logInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        assert(() {
          _logger.d('[HTTP] ${options.method} ${options.uri}');
          return true;
        }());
        handler.next(options);
      },
      onResponse: (response, handler) {
        assert(() {
          _logger.d('[HTTP] ${response.statusCode} ${response.requestOptions.uri}');
          return true;
        }());
        handler.next(response);
      },
      onError: (error, handler) {
        assert(() {
          _logger.e('[HTTP] Erreur : ${error.message}');
          return true;
        }());
        handler.next(error);
      },
    );
  }
}
