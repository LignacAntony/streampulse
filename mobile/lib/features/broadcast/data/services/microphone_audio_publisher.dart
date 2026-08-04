import 'dart:async';

import '../../../../core/utils/retry_backoff.dart';
import '../../domain/services/broadcast_audio_publisher.dart';
import 'audio_capture.dart';
import 'audio_ingest_client.dart';
import 'dio_audio_ingest_client.dart';
import 'record_audio_capture.dart';

/// Orchestre capture, push et reconnexion sans jamais mettre les octets audio
/// en tampon. Une nouvelle tentative redémarre l'encodeur afin que le serveur
/// reçoive un flux AAC/ADTS autonome après chaque coupure.
class MicrophoneAudioPublisher implements BroadcastAudioPublisher {
  MicrophoneAudioPublisher({
    AudioCapture? capture,
    AudioIngestClient? ingest,
    Duration Function(int attempt)? backoff,
  }) : _capture = capture ?? RecordAudioCapture(),
       _ingest = ingest ?? DioAudioIngestClient(),
       _backoff = backoff ?? cappedExponentialBackoff;

  final AudioCapture _capture;
  final AudioIngestClient _ingest;
  final Duration Function(int attempt) _backoff;
  final StreamController<BroadcastAudioState> _states =
      StreamController<BroadcastAudioState>.broadcast();

  BroadcastAudioState _state = BroadcastAudioState.idle;
  bool _desired = false;
  bool _disposed = false;
  Future<void>? _runFuture;
  Completer<void>? _retryGate;

  @override
  BroadcastAudioState get state => _state;

  @override
  Stream<BroadcastAudioState> get states => _states.stream;

  @override
  Future<void> prepare() async {
    if (!await _capture.hasPermission()) {
      throw const MicrophonePermissionException();
    }
    if (!await _capture.supportsAacAdts()) {
      throw const AudioEncoderUnsupportedException();
    }
  }

  @override
  Future<void> start(Uri sourceUrl) async {
    if (_disposed) throw StateError('Diffuseur audio déjà libéré');
    if (_desired) return;
    if (sourceUrl.scheme != 'http' && sourceUrl.scheme != 'https') {
      throw ArgumentError.value(sourceUrl, 'sourceUrl', 'URL HTTP(S) attendue');
    }

    _desired = true;
    final firstAttempt = Completer<void>();
    _runFuture = _run(sourceUrl, firstAttempt);
    await firstAttempt.future;
  }

  Future<void> _run(Uri sourceUrl, Completer<void> firstAttempt) async {
    var attempt = 0;
    Object? initialError;
    StackTrace? initialStackTrace;
    try {
      while (_desired) {
        _emit(
          attempt == 0
              ? BroadcastAudioState.connecting
              : BroadcastAudioState.reconnecting,
        );
        try {
          final audio = await _capture.start();
          if (!_desired) break;

          _emit(BroadcastAudioState.live);
          if (!firstAttempt.isCompleted) firstAttempt.complete();
          await _ingest.push(sourceUrl, audio);
        } catch (error, stackTrace) {
          // Une erreur avant même l'obtention du flux micro est un échec de
          // démarrage. Une coupure après démarrage, elle, est transitoire et
          // déclenche la reprise ci-dessous.
          if (!firstAttempt.isCompleted) {
            _desired = false;
            initialError = error;
            initialStackTrace = stackTrace;
          }
        } finally {
          await _closeAttempt();
        }

        if (!_desired) break;
        _emit(BroadcastAudioState.reconnecting);
        await _waitForRetry(_backoff(attempt));
        attempt++;
      }
    } finally {
      _emit(BroadcastAudioState.idle);
      if (initialError != null && !firstAttempt.isCompleted) {
        firstAttempt.completeError(initialError, initialStackTrace!);
      } else if (!firstAttempt.isCompleted) {
        firstAttempt.completeError(StateError('Démarrage audio interrompu'));
      }
    }
  }

  Future<void> _closeAttempt() async {
    try {
      await _ingest.cancel();
    } catch (_) {
      // La requête est déjà cassée : son annulation ne doit pas tuer la boucle
      // de reconnexion.
    }
    try {
      await _capture.stop();
    } catch (_) {
      // Certaines plateformes signalent une erreur si l'enregistreur s'est
      // déjà arrêté lors d'une interruption audio. La tentative suivante
      // recrée malgré tout un stream propre.
    }
  }

  Future<void> _waitForRetry(Duration duration) async {
    final gate = Completer<void>();
    _retryGate = gate;
    await Future.any([Future<void>.delayed(duration), gate.future]);
    if (identical(_retryGate, gate)) _retryGate = null;
  }

  @override
  Future<void> stop() async {
    _desired = false;
    final gate = _retryGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await _closeAttempt();
    await _runFuture;
    _runFuture = null;
    _emit(BroadcastAudioState.idle);
  }

  void _emit(BroadcastAudioState state) {
    if (_state == state) return;
    _state = state;
    if (!_disposed) _states.add(state);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _capture.dispose();
    await _states.close();
  }
}
