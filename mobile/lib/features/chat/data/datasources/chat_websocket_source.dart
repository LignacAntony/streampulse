import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
  WebSocketChannel? _channel;

  @override
  Stream<Map<String, dynamic>> connect(String streamId) async* {
    final token = await _storage.getAccessToken();
    final url = ApiConstants.chatWebSocket(streamId);

    // Pre-check : requête HTTP pour détecter 403 (banni) ou 409 (pas live)
    // avant de tenter l'upgrade WebSocket (qui ne remonte pas le code HTTP).
    final preCheckError = await _preCheck(streamId, token);
    if (preCheckError != null) {
      yield {'type': 'error', 'message': preCheckError};
      return;
    }

    _channel = IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    try {
      await _channel!.ready;
    } on WebSocketChannelException catch (_) {
      _channel = null;
      yield {
        'type': 'error',
        'message': 'Le chat est indisponible (flux non en direct)',
      };
      return;
    }

    yield* _channel!.stream.map((raw) {
      if (raw is String) {
        return json.decode(raw) as Map<String, dynamic>;
      }
      return <String, dynamic>{};
    });
  }

  Future<String?> _preCheck(String streamId, String? token) async {
    final httpUrl = '${ApiConstants.baseUrl}/ws/streams/$streamId/chat';
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(httpUrl));
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode == 403) {
        return 'Vous êtes banni de ce chat';
      }
      if (response.statusCode == 409) {
        return 'Le chat est indisponible (flux non en direct)';
      }
      // 101 ou autre : on laisse le WebSocket tenter normalement
      return null;
    } on Object {
      return null;
    } finally {
      client.close();
    }
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
}
