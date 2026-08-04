import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/features/broadcast/data/services/audio_capture.dart';
import 'package:streampulse/features/broadcast/data/services/audio_ingest_client.dart';
import 'package:streampulse/features/broadcast/data/services/dio_audio_ingest_client.dart';
import 'package:streampulse/features/broadcast/data/services/microphone_audio_publisher.dart';
import 'package:streampulse/features/broadcast/domain/services/broadcast_audio_publisher.dart';

class _FakeCapture implements AudioCapture {
  bool permission = true;
  bool supported = true;
  Object? startError;
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  StreamController<Uint8List>? current;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> supportsAacAdts() async => supported;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    if (startError != null) throw startError!;
    current = StreamController<Uint8List>();
    return current!.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    final controller = current;
    current = null;
    if (controller != null && !controller.isClosed) await controller.close();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeIngest implements AudioIngestClient {
  int pushes = 0;
  int cancels = 0;
  Uri? sourceUrl;
  Completer<void>? current;
  StreamSubscription<List<int>>? audioSubscription;

  @override
  Future<void> push(Uri sourceUrl, Stream<List<int>> audio) {
    pushes++;
    this.sourceUrl = sourceUrl;
    audioSubscription = audio.listen((_) {});
    current = Completer<void>();
    return current!.future;
  }

  void fail() => current!.completeError(const SocketException('coupure'));

  @override
  Future<void> cancel() async {
    cancels++;
    await audioSubscription?.cancel();
    audioSubscription = null;
    final request = current;
    current = null;
    if (request != null && !request.isCompleted) request.complete();
  }
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

void main() {
  group('MicrophoneAudioPublisher', () {
    test('refuse de démarrer sans permission microphone', () async {
      final capture = _FakeCapture()..permission = false;
      final publisher = MicrophoneAudioPublisher(
        capture: capture,
        ingest: _FakeIngest(),
      );

      await expectLater(
        publisher.prepare(),
        throwsA(isA<MicrophonePermissionException>()),
      );
      expect(capture.starts, 0);

      await publisher.dispose();
    });

    test('refuse un appareil qui ne sait pas streamer l\'AAC/ADTS', () async {
      final capture = _FakeCapture()..supported = false;
      final publisher = MicrophoneAudioPublisher(
        capture: capture,
        ingest: _FakeIngest(),
      );

      await expectLater(
        publisher.prepare(),
        throwsA(isA<AudioEncoderUnsupportedException>()),
      );

      await publisher.dispose();
    });

    test(
      'pousse le micro et reprend sur une nouvelle requête après coupure',
      () async {
        final capture = _FakeCapture();
        final ingest = _FakeIngest();
        final publisher = MicrophoneAudioPublisher(
          capture: capture,
          ingest: ingest,
          backoff: (_) => Duration.zero,
        );
        final states = <BroadcastAudioState>[];
        final subscription = publisher.states.listen(states.add);
        final endpoint = Uri.parse('https://api.test/ingest/secret');

        await publisher.prepare();
        await publisher.start(endpoint);
        expect(ingest.pushes, 1);
        expect(ingest.sourceUrl, endpoint);
        expect(publisher.state, BroadcastAudioState.live);

        ingest.fail();
        await _pumpUntil(() => ingest.pushes == 2);

        expect(capture.starts, 2);
        expect(states, contains(BroadcastAudioState.reconnecting));
        expect(publisher.state, BroadcastAudioState.live);

        await publisher.stop();
        expect(publisher.state, BroadcastAudioState.idle);
        expect(capture.stops, greaterThanOrEqualTo(2));

        await subscription.cancel();
        await publisher.dispose();
        expect(capture.disposed, isTrue);
      },
    );

    test('relaie un échec de capture initial sans lancer de push', () async {
      final capture = _FakeCapture()..startError = StateError('micro occupé');
      final ingest = _FakeIngest();
      final publisher = MicrophoneAudioPublisher(
        capture: capture,
        ingest: ingest,
      );

      await expectLater(
        publisher.start(Uri.parse('https://api.test/ingest/secret')),
        throwsStateError,
      );
      expect(ingest.pushes, 0);
      expect(publisher.state, BroadcastAudioState.idle);

      await publisher.dispose();
    });
  });

  test(
    'DioAudioIngestClient envoie le flux brut en HTTP chunked audio/aac',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received =
          Completer<({List<int> bytes, String? contentType, int length})>();
      final serverFuture = server.first.then((request) async {
        final bytes = await request.fold<List<int>>(<int>[], (all, chunk) {
          all.addAll(chunk);
          return all;
        });
        received.complete((
          bytes: bytes,
          contentType: request.headers.contentType?.mimeType,
          length: request.contentLength,
        ));
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      final audio = StreamController<List<int>>();
      final client = DioAudioIngestClient();
      final push = client.push(
        Uri.parse('http://127.0.0.1:${server.port}/ingest/secret'),
        audio.stream,
      );

      audio.add([0xff, 0xf1, 0x50]);
      audio.add([0x80, 0x00]);
      await audio.close();
      await push;

      final request = await received.future;
      expect(request.bytes, [0xff, 0xf1, 0x50, 0x80, 0x00]);
      expect(request.contentType, 'audio/aac');
      expect(request.length, -1); // absence de Content-Length => chunked

      await serverFuture;
      await server.close(force: true);
    },
  );
}
