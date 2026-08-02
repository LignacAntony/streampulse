import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/core/network/sse_client.dart';
import 'package:streampulse/core/storage/secure_storage.dart';

/// Évite le canal de plateforme `flutter_secure_storage` : seul le jeton
/// compte ici, et il est injecté en dur.
class _FakeSecureStorage extends SecureStorage {
  _FakeSecureStorage([this.token = 'jeton-test']);

  final String? token;

  @override
  Future<String?> getAccessToken() async => token;
}

/// Adaptateur qui rejoue un corps SSE fourni par le test, sans réseau.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.statusCode = 200});

  final Stream<Uint8List> body;
  final int statusCode;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Stream<Uint8List> _chunks(List<String> parts) =>
    Stream.fromIterable(parts.map((p) => Uint8List.fromList(utf8.encode(p))));

void main() {
  group('SseClient', () {
    test('décode une trame event/data complète', () async {
      final adapter = _FakeAdapter(
        _chunks(['event: ended\ndata: {"type":"ended"}\n\n']),
      );
      final client = SseClient(_FakeSecureStorage(), dio: _dioWith(adapter));

      final events = await client.connect('/api/streams/a/events').toList();

      expect(events, hasLength(1));
      expect(events.single.name, 'ended');
      expect(events.single.data, '{"type":"ended"}');
    });

    test('ignore les commentaires de keep-alive', () async {
      final adapter = _FakeAdapter(
        _chunks([': keepalive\n\n', ': keepalive\n\n', 'data: utile\n\n']),
      );
      final client = SseClient(_FakeSecureStorage(), dio: _dioWith(adapter));

      final events = await client.connect('/api/streams/a/events').toList();

      expect(events, hasLength(1));
      expect(events.single.data, 'utile');
    });

    test('nomme `message` une trame sans champ event', () async {
      final adapter = _FakeAdapter(_chunks(['data: bonjour\n\n']));
      final client = SseClient(_FakeSecureStorage(), dio: _dioWith(adapter));

      final events = await client.connect('/api/streams/a/events').toList();

      expect(events.single.name, 'message');
    });

    test('concatène les champs data multiples d\'une même trame', () async {
      final adapter = _FakeAdapter(
        _chunks(['data: ligne1\ndata: ligne2\n\n']),
      );
      final client = SseClient(_FakeSecureStorage(), dio: _dioWith(adapter));

      final events = await client.connect('/api/streams/a/events').toList();

      expect(events.single.data, 'ligne1\nligne2');
    });

    test('recompose une trame arrivée en plusieurs morceaux', () async {
      final adapter = _FakeAdapter(
        _chunks(['event: en', 'ded\ndata: x', '\n\n']),
      );
      final client = SseClient(_FakeSecureStorage(), dio: _dioWith(adapter));

      final events = await client.connect('/api/streams/a/events').toList();

      expect(events.single.name, 'ended');
      expect(events.single.data, 'x');
    });

    test('envoie le Bearer et les en-têtes SSE', () async {
      final adapter = _FakeAdapter(_chunks(['data: x\n\n']));
      final client = SseClient(_FakeSecureStorage('abc'), dio: _dioWith(adapter));

      await client.connect('/api/streams/a/events').toList();

      final headers = adapter.lastRequest!.headers;
      expect(headers['Authorization'], 'Bearer abc');
      expect(headers['Accept'], 'text/event-stream');
      expect(adapter.lastRequest!.responseType, ResponseType.stream);
    });

    test('un 401 est traduit en AuthException', () async {
      final adapter = _FakeAdapter(_chunks([]), statusCode: 401);
      final client = SseClient(_FakeSecureStorage(), dio: _dioWith(adapter));

      await expectLater(
        client.connect('/api/streams/a/events'),
        emitsError(isA<AuthException>()),
      );
    });

    test('une panne de transport est traduite en NetworkException', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
      dio.httpClientAdapter = _ThrowingAdapter();
      final client = SseClient(_FakeSecureStorage(), dio: dio);

      await expectLater(
        client.connect('/api/streams/a/events'),
        emitsError(isA<NetworkException>()),
      );
    });

    test('le flux se termine quand le serveur ferme la connexion', () async {
      final controller = StreamController<Uint8List>();
      final adapter = _FakeAdapter(controller.stream);
      final client = SseClient(_FakeSecureStorage(), dio: _dioWith(adapter));

      final done = Completer<void>();
      client
          .connect('/api/streams/a/events')
          .listen(null, onDone: done.complete);

      await Future<void>.delayed(Duration.zero);
      await controller.close();

      await done.future.timeout(const Duration(seconds: 1));
    });
  });
}

/// Simule une coupure réseau au moment de l'établissement.
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'connexion refusée',
    );
  }

  @override
  void close({bool force = false}) {}
}
