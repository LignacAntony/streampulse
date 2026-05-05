import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import '../storage/secure_storage.dart';

// Principe D : SecureStorage est injecté via le constructeur, pas instancié ici.
// Principe S : DioClient gère uniquement le transport HTTP.
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

    _dio.interceptors.addAll([
      _authInterceptor(),
      _logInterceptor(),
    ]);
  }

  final SecureStorage _storage;
  late final Dio _dio;
  final _logger = Logger();

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
        // La logique de refresh token sera complétée en US-02-02.
        if (error.response?.statusCode == 401) {
          await _storage.clearTokens();
        }
        handler.next(error);
      },
    );
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
