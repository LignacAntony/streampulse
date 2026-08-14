import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import '../errors/exceptions.dart';
import '../storage/secure_storage.dart';

/// Un évènement Server-Sent Events reçu du backend.
class SseEvent {
  const SseEvent({required this.name, required this.data});

  /// Valeur du champ `event:` ; `message` par défaut, comme le veut la
  /// spécification SSE lorsque le champ est absent.
  final String name;

  /// Concaténation des champs `data:` de la trame.
  final String data;

  @override
  String toString() => 'SseEvent($name, $data)';
}

/// Abstraction d'une souscription SSE, pour que les contrôleurs de
/// présentation dépendent d'un contrat et non de Dio (principe D). Les tests
/// injectent un connecteur factice piloté à la main.
abstract class SseConnector {
  /// Ouvre **une** connexion et émet ses évènements. Le flux se termine quand
  /// le serveur ferme la connexion, et émet une erreur si la connexion échoue.
  ///
  /// Aucune reconnexion n'est tentée ici : la politique de reprise (backoff,
  /// resynchronisation) appartient à l'appelant, qui seul sait ce qu'il faut
  /// resynchroniser. Annuler la souscription ferme la requête HTTP.
  Stream<SseEvent> connect(String path);
}

/// Client SSE sur Dio, séparé de `DioClient` à dessein (principe S).
///
/// `DioClient` borne ses réponses par `AppConstants.receiveTimeout` (10 s),
/// ce qui tuerait toute souscription SSE : le backend n'envoie un commentaire
/// de keep-alive que toutes les 15 s (`sseKeepAliveInterval`). Cette instance
/// laisse donc `receiveTimeout` à null (aucune borne) et conserve un
/// `connectTimeout`, qui lui ne s'applique qu'à l'établissement.
///
/// Le `Bearer` est lu à chaque connexion plutôt qu'injecté par un
/// intercepteur : l'authentification n'est vérifiée qu'à l'ouverture côté
/// serveur, une souscription déjà établie survit donc à l'expiration du token.
class SseClient implements SseConnector {
  SseClient(this._storage, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                connectTimeout: AppConstants.connectTimeout,
              ),
            );

  final SecureStorage _storage;
  final Dio _dio;

  @override
  Stream<SseEvent> connect(String path) {
    final cancelToken = CancelToken();
    StreamSubscription<String>? lines;
    late final StreamController<SseEvent> controller;

    Future<void> open() async {
      try {
        final token = await _storage.getAccessToken();
        final response = await _dio.get<ResponseBody>(
          path,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          ),
          cancelToken: cancelToken,
        );

        final body = response.data;
        if (body == null) {
          await controller.close();
          return;
        }

        var eventName = _defaultEventName;
        final data = <String>[];

        lines = body.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            // Ligne vide = fin de trame : on émet ce qui a été accumulé.
            if (line.isEmpty) {
              if (data.isNotEmpty) {
                controller.add(
                  SseEvent(name: eventName, data: data.join('\n')),
                );
              }
              eventName = _defaultEventName;
              data.clear();
              return;
            }
            // Un commentaire (`: keepalive`) ne sert qu'à maintenir la
            // connexion ouverte : rien à remonter à l'appelant.
            if (line.startsWith(':')) return;

            final separator = line.indexOf(':');
            if (separator == -1) return; // champ sans valeur : ignoré
            final field = line.substring(0, separator);
            // La spécification autorise un unique espace après le deux-points.
            var value = line.substring(separator + 1);
            if (value.startsWith(' ')) value = value.substring(1);

            if (field == 'event') {
              eventName = value;
            } else if (field == 'data') {
              data.add(value);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            controller.addError(_mapError(error), stackTrace);
            controller.close();
          },
          onDone: controller.close,
          cancelOnError: true,
        );
      } catch (error, stackTrace) {
        // Annulation volontaire (l'appelant s'est désabonné) : ce n'est pas
        // une panne, on ferme le flux sans propager d'erreur.
        if (error is DioException && CancelToken.isCancel(error)) {
          await controller.close();
          return;
        }
        controller.addError(_mapError(error), stackTrace);
        await controller.close();
      }
    }

    controller = StreamController<SseEvent>(
      onListen: open,
      onCancel: () async {
        if (!cancelToken.isCancelled) cancelToken.cancel();
        await lines?.cancel();
      },
    );

    return controller.stream;
  }

  static const String _defaultEventName = 'message';

  /// Traduit une erreur de transport vers les exceptions partagées de l'app,
  /// pour que l'appelant n'ait pas à connaître Dio.
  Object _mapError(Object error) {
    if (error is! DioException) return error;

    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const AuthException();
    }
    if (status != null) {
      return ServerException('Erreur serveur ($status)');
    }
    return const NetworkException();
  }
}
