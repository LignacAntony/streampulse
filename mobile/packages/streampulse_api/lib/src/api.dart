//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'package:dio/dio.dart';
import 'package:streampulse_api/src/auth/api_key_auth.dart';
import 'package:streampulse_api/src/auth/basic_auth.dart';
import 'package:streampulse_api/src/auth/bearer_auth.dart';
import 'package:streampulse_api/src/auth/oauth.dart';
import 'package:streampulse_api/src/api/admin_api.dart';
import 'package:streampulse_api/src/api/auth_api.dart';
import 'package:streampulse_api/src/api/broadcaster_api.dart';
import 'package:streampulse_api/src/api/chat_api.dart';
import 'package:streampulse_api/src/api/health_api.dart';
import 'package:streampulse_api/src/api/metrics_api.dart';
import 'package:streampulse_api/src/api/playlist_api.dart';
import 'package:streampulse_api/src/api/profile_api.dart';
import 'package:streampulse_api/src/api/streaming_api.dart';
import 'package:streampulse_api/src/api/track_api.dart';

class StreampulseApi {
  static const String basePath = r'http://localhost';

  final Dio dio;
  StreampulseApi({
    Dio? dio,
    String? basePathOverride,
    List<Interceptor>? interceptors,
  }) : this.dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: basePathOverride ?? basePath,
               connectTimeout: const Duration(milliseconds: 5000),
               receiveTimeout: const Duration(milliseconds: 3000),
             ),
           ) {
    if (interceptors == null) {
      this.dio.interceptors.addAll([
        OAuthInterceptor(),
        BasicAuthInterceptor(),
        BearerAuthInterceptor(),
        ApiKeyAuthInterceptor(),
      ]);
    } else {
      this.dio.interceptors.addAll(interceptors);
    }
  }

  void setOAuthToken(String name, String token) {
    if (this.dio.interceptors.any((i) => i is OAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is OAuthInterceptor)
                  as OAuthInterceptor)
              .tokens[name] =
          token;
    }
  }

  /// Removes the OAuth token associated with the given [name].
  ///
  /// If no [OAuthInterceptor] is registered or no token exists for the given
  /// [name], this method has no effect.
  void removeOAuthToken(String name) {
    if (this.dio.interceptors.any((i) => i is OAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is OAuthInterceptor)
              as OAuthInterceptor)
          .tokens
          .remove(name);
    }
  }

  void setBearerAuth(String name, String token) {
    if (this.dio.interceptors.any((i) => i is BearerAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BearerAuthInterceptor)
                  as BearerAuthInterceptor)
              .tokens[name] =
          token;
    }
  }

  /// Removes the bearer authentication token associated with the given [name].
  ///
  /// If no [BearerAuthInterceptor] is registered or no token exists for the
  /// given [name], this method has no effect.
  void removeBearerAuth(String name) {
    if (this.dio.interceptors.any((i) => i is BearerAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BearerAuthInterceptor)
              as BearerAuthInterceptor)
          .tokens
          .remove(name);
    }
  }

  void setBasicAuth(String name, String username, String password) {
    if (this.dio.interceptors.any((i) => i is BasicAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BasicAuthInterceptor)
              as BasicAuthInterceptor)
          .authInfo[name] = BasicAuthInfo(
        username,
        password,
      );
    }
  }

  /// Removes the basic authentication credentials associated with the given [name].
  ///
  /// If no [BasicAuthInterceptor] is registered or no credentials exist for the
  /// given [name], this method has no effect.
  void removeBasicAuth(String name) {
    if (this.dio.interceptors.any((i) => i is BasicAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BasicAuthInterceptor)
              as BasicAuthInterceptor)
          .authInfo
          .remove(name);
    }
  }

  void setApiKey(String name, String apiKey) {
    if (this.dio.interceptors.any((i) => i is ApiKeyAuthInterceptor)) {
      (this.dio.interceptors.firstWhere(
                    (element) => element is ApiKeyAuthInterceptor,
                  )
                  as ApiKeyAuthInterceptor)
              .apiKeys[name] =
          apiKey;
    }
  }

  /// Removes the API key associated with the given [name].
  ///
  /// If no [ApiKeyAuthInterceptor] is registered or no API key exists for the
  /// given [name], this method has no effect.
  void removeApiKey(String name) {
    if (this.dio.interceptors.any((i) => i is ApiKeyAuthInterceptor)) {
      (this.dio.interceptors.firstWhere(
                (element) => element is ApiKeyAuthInterceptor,
              )
              as ApiKeyAuthInterceptor)
          .apiKeys
          .remove(name);
    }
  }

  /// Get AdminApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  AdminApi getAdminApi() {
    return AdminApi(dio);
  }

  /// Get AuthApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  AuthApi getAuthApi() {
    return AuthApi(dio);
  }

  /// Get BroadcasterApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  BroadcasterApi getBroadcasterApi() {
    return BroadcasterApi(dio);
  }

  /// Get ChatApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  ChatApi getChatApi() {
    return ChatApi(dio);
  }

  /// Get HealthApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  HealthApi getHealthApi() {
    return HealthApi(dio);
  }

  /// Get MetricsApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  MetricsApi getMetricsApi() {
    return MetricsApi(dio);
  }

  /// Get PlaylistApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  PlaylistApi getPlaylistApi() {
    return PlaylistApi(dio);
  }

  /// Get ProfileApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  ProfileApi getProfileApi() {
    return ProfileApi(dio);
  }

  /// Get StreamingApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  StreamingApi getStreamingApi() {
    return StreamingApi(dio);
  }

  /// Get TrackApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  TrackApi getTrackApi() {
    return TrackApi(dio);
  }
}
