import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';

abstract class ChatWebSocketSource {
  Stream<Map<String, dynamic>> connect(String streamId);
  void send(Map<String, dynamic> message);
  void disconnect();
}

class ChatWebSocketSourceImpl implements ChatWebSocketSource {
  ChatWebSocketSourceImpl(this._storage, this._client);

  final SecureStorage _storage;
  final DioClient _client;
  IOWebSocketChannel? _channel;

  @override
  Stream<Map<String, dynamic>> connect(String streamId) async* {
    final token = await _storage.getAccessToken();
    final url = ApiConstants.chatWebSocket(streamId);
    final uri = Uri.parse(url);

    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        url,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
    } on WebSocketException catch (_) {
      final result = await _resolveError(uri, token);
      if (result == _ErrorResult.unauthorized) {
        await _client.refreshTokens();
        final freshToken = await _storage.getAccessToken();
        try {
          ws = await WebSocket.connect(
            url,
            headers: {
              if (freshToken != null) 'Authorization': 'Bearer $freshToken',
            },
          );
        } on Object catch (_) {
          yield {'type': 'error', 'message': 'Session expirée'};
          return;
        }
      } else {
        yield {'type': 'error', 'message': result.message};
        return;
      }
    } on SocketException catch (_) {
      yield {
        'type': 'error',
        'message': 'Impossible de se connecter au serveur',
      };
      return;
    }

    _channel = IOWebSocketChannel(ws);

    yield* _channel!.stream.map((raw) {
      if (raw is String) {
        return json.decode(raw) as Map<String, dynamic>;
      }
      return <String, dynamic>{};
    });
  }

  @override
  void send(Map<String, dynamic> message) {
    _channel?.sink.add(json.encode(message));
  }

  @override
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  Future<_ErrorResult> _resolveError(Uri wsUri, String? token) async {
    final httpScheme = wsUri.scheme == 'wss' ? 'https' : 'http';
    final httpUri = wsUri.replace(scheme: httpScheme);
    final client = HttpClient();
    try {
      final req = await client.getUrl(httpUri);
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode == 401) return _ErrorResult.unauthorized;
      if (res.statusCode == 403) return _ErrorResult.banned;
      if (res.statusCode == 409) return _ErrorResult.notLive;
    } on Object {
      // Fallback si la sonde échoue aussi.
    } finally {
      client.close();
    }
    return _ErrorResult.unknown;
  }
}

enum _ErrorResult {
  unauthorized('Session expirée'),
  banned('Vous êtes banni de ce chat'),
  notLive('Le chat est indisponible (flux non en direct)'),
  unknown('Le chat est indisponible');

  const _ErrorResult(this.message);
  final String message;
}
