import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/storage/secure_storage.dart';

abstract class ChatWebSocketSource {
  Stream<Map<String, dynamic>> connect(String streamId);
  void send(Map<String, dynamic> message);
  void disconnect();
}

class ChatWebSocketSourceImpl implements ChatWebSocketSource {
  ChatWebSocketSourceImpl(this._storage);

  final SecureStorage _storage;
  IOWebSocketChannel? _channel;

  @override
  Stream<Map<String, dynamic>> connect(String streamId) async* {
    final token = await _storage.getAccessToken();
    final url = ApiConstants.chatWebSocket(streamId);
    final uri = Uri.parse(url);

    // Connexion WebSocket via dart:io pour capturer le code HTTP en cas
    // de rejet (403 = banni, 409 = pas live) avant l'upgrade.
    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        url,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Host': uri.host,
        },
      );
    } on WebSocketException catch (_) {
      // dart:io ne remonte pas le code HTTP dans l'exception ; on fait
      // un GET classique pour le distinguer.
      final errorMsg = await _resolveError(uri, token);
      yield {'type': 'error', 'message': errorMsg};
      return;
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

  Future<String> _resolveError(Uri wsUri, String? token) async {
    // Convertir ws:// → http:// pour la sonde.
    final httpScheme = wsUri.scheme == 'wss' ? 'https' : 'http';
    final httpUri = wsUri.replace(scheme: httpScheme);
    final client = HttpClient();
    try {
      final req = await client.getUrl(httpUri);
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode == 403) return 'Vous êtes banni de ce chat';
      if (res.statusCode == 409) {
        return 'Le chat est indisponible (flux non en direct)';
      }
    } on Object {
      // Fallback si la sonde échoue aussi.
    } finally {
      client.close();
    }
    return 'Le chat est indisponible';
  }
}
