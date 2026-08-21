import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/network/dio_client.dart';
import 'package:streampulse/core/network/trace_context.dart';
import 'package:streampulse/core/storage/secure_storage.dart';

/// Adaptateur qui n'atteint jamais le réseau : il capture les en-têtes envoyés
/// et rend une réponse vide.
class _CapturingAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> captured = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(Map<String, dynamic>.from(options.headers));
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CapturingAdapter adapter;
  late DioClient client;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    adapter = _CapturingAdapter();
    client = DioClient(
      SecureStorage(),
      traceContext: TraceContext(random: Random(99)),
    );
    client.dio.httpClientAdapter = adapter;
  });

  test('chaque requête sortante porte un traceparent W3C', () async {
    await client.dio.get('/api/streams');

    expect(adapter.captured, hasLength(1));
    final value = adapter.captured.single[TraceContext.header] as String;
    expect(value, matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-0[01]$')));
  });

  // Deux requêtes qui partageraient un identifiant se confondraient dans Tempo :
  // la seconde apparaîtrait comme un span de la première.
  test('deux requêtes ne partagent pas le même identifiant', () async {
    await client.dio.get('/api/streams');
    await client.dio.get('/api/tracks');

    final values = adapter.captured
        .map((headers) => headers[TraceContext.header] as String)
        .toSet();
    expect(values, hasLength(2));
  });
}
