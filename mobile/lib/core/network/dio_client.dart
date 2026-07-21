import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:streampulse_api/streampulse_api.dart';

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

    _dio.interceptors.addAll([_authInterceptor(), _logInterceptor()]);

    // Les méthodes générées (ex. AuthApi.logout) émettent une métadonnée
    // `extra['secure']`, mais le client généré ne branche AUCUN intercepteur
    // d'auth : l'injection du `Bearer` repose entièrement sur `_authInterceptor`
    // ci-dessus. Ne pas se fier au mécanisme `secure` généré tant qu'un
    // HttpBearerAuth n'est pas explicitement configuré.
    _authApi = AuthApi(_dio);
    _refreshAuthApi = AuthApi(_refreshDio);
    _profileApi = ProfileApi(_dio);
    _broadcasterApi = BroadcasterApi(_dio);
    _streamingApi = StreamingApi(_dio);
    _adminApi = AdminApi(_dio);
  }

  static const _retriedKey = '_retried';

  final SecureStorage _storage;
  late final Dio _dio;
  late final Dio _refreshDio;
  late final AuthApi _authApi;
  late final AuthApi _refreshAuthApi;
  late final ProfileApi _profileApi;
  late final BroadcasterApi _broadcasterApi;
  late final StreamingApi _streamingApi;
  late final AdminApi _adminApi;
  final _logger = Logger();

  Completer<bool>? _refreshing;

  Dio get dio => _dio;
  AuthApi get authApi => _authApi;
  ProfileApi get profileApi => _profileApi;
  BroadcasterApi get broadcasterApi => _broadcasterApi;
  StreamingApi get streamingApi => _streamingApi;
  AdminApi get adminApi => _adminApi;

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

      final resp = await _refreshAuthApi.refreshToken(
        refreshRequest: RefreshRequest(refreshToken: refreshToken),
      );
      final pair = resp.data;
      if (pair == null) {
        completer.complete(false);
        return false;
      }
      await _storage.saveAccessToken(pair.accessToken);
      await _storage.saveRefreshToken(pair.refreshToken);
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
          _logger.d(
            '[HTTP] ${response.statusCode} ${response.requestOptions.uri}',
          );
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
