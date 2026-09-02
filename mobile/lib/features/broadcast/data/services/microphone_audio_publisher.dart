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
    int maxSilentAttempts = _defaultMaxSilentAttempts,
  }) : _capture = capture ?? RecordAudioCapture(),
       _ingest = ingest ?? DioAudioIngestClient(),
       _backoff = backoff ?? cappedExponentialBackoff,
       _maxSilentAttempts = maxSilentAttempts;

  /// Nombre de tentatives consécutives n'ayant transmis aucun octet avant
  /// d'abandonner. Toutes les pannes ne sont pas des coupures réseau : une
  /// permission révoquée en cours de direct, un micro capté par une autre
  /// application ou un encodeur en échec ne guériront pas d'eux-mêmes, et une
  /// reprise sans borne laisserait la carte figée sur « Reconnexion audio… ».
  ///
  /// Six tentatives couvrent la rampe complète du backoff
  /// (1 + 2 + 4 + 8 + 16 = 31 s d'attente), soit plus que le plus long délai
  /// utile côté client et moins que le bail d'ingest du serveur, qui prendrait
  /// de toute façon le relais (`INGEST_RECONNECT_GRACE_SECONDS` > 30 s).
  static const int _defaultMaxSilentAttempts = 6;

  final AudioCapture _capture;
  final AudioIngestClient _ingest;
  final Duration Function(int attempt) _backoff;
  final int _maxSilentAttempts;
  final StreamController<BroadcastAudioState> _states =
      StreamController<BroadcastAudioState>.broadcast();

  BroadcastAudioState _state = BroadcastAudioState.idle;
  bool _desired = false;
  bool _disposed = false;
  Future<void>? _runFuture;
  Completer<void>? _retryGate;

  @override
  bool get isSupported => true;

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
      // Seul le schéma est rapporté : l'URL d'ingest porte le `stream_key` en
      // clair, et le message d'une exception finit facilement dans un log ou
      // un rapport de crash.
      throw ArgumentError.value(
        sourceUrl.scheme,
        'sourceUrl.scheme',
        'URL HTTP(S) attendue',
      );
    }

    _desired = true;
    final firstAttempt = Completer<void>();
    _runFuture = _run(sourceUrl, firstAttempt);
    await firstAttempt.future;
  }

  Future<void> _run(Uri sourceUrl, Completer<void> firstAttempt) async {
    var started = false;
    var silentAttempts = 0;
    var gaveUp = false;
    // Une autre source a pris l'ingest pendant que nous tentions de nous
    // reconnecter. État terminal, mais qui n'est pas une panne : le direct vit,
    // alimenté par quelqu'un d'autre.
    var superseded = false;
    Object? initialError;
    StackTrace? initialStackTrace;
    try {
      while (_desired) {
        _emit(
          started
              ? BroadcastAudioState.reconnecting
              : BroadcastAudioState.connecting,
        );
        var pushedBytes = false;
        try {
          final audio = await _capture.start();
          if (!_desired) break;

          started = true;
          if (!firstAttempt.isCompleted) firstAttempt.complete();
          // `live` n'est émis qu'au premier octet réellement poussé : le
          // signaler dès l'ouverture du micro ferait clignoter la carte entre
          // « Microphone diffusé » et « Reconnexion audio… » à chaque cycle de
          // backoff sur une connexion qui n'aboutit jamais.
          await _ingest.push(
            sourceUrl,
            audio.map((chunk) {
              if (!pushedBytes && chunk.isNotEmpty) {
                pushedBytes = true;
                _emit(BroadcastAudioState.live);
              }
              return chunk;
            }),
          );
        } catch (error, stackTrace) {
          // Une autre source alimente déjà ce direct : il n'y a rien à
          // reprendre, et insister mènerait à `failed`, donc à l'arrêt du
          // direct de cette autre source. On sort de la boucle sans panne.
          if (error is IngestConflictException) {
            _desired = false;
            if (firstAttempt.isCompleted) {
              // Conflit survenu APRÈS le démarrage : nous diffusions, la
              // connexion a lâché, et une autre source a pris la clé avant
              // notre reconnexion. Sortir sur `idle` laisserait la tuile
              // afficher « en direct » avec un micro mort et sans un mot —
              // une désynchronisation silencieuse (revue PR #382).
              superseded = true;
            } else {
              initialError = error;
              initialStackTrace = stackTrace;
            }
            continue;
          }
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
        // Une tentative qui a transmis de l'audio prouve que la chaîne est
        // saine : le compteur d'abandon ET la rampe de backoff repartent de
        // zéro, sinon un direct de plusieurs heures finirait par attendre 30 s
        // à la moindre micro-coupure.
        if (pushedBytes) {
          silentAttempts = 0;
        } else if (++silentAttempts >= _maxSilentAttempts) {
          gaveUp = true;
          _desired = false;
          break;
        }
        _emit(BroadcastAudioState.reconnecting);
        await _waitForRetry(
          _backoff(silentAttempts == 0 ? 0 : silentAttempts - 1),
        );
      }
    } finally {
      _emit(
        gaveUp
            ? BroadcastAudioState.failed
            : superseded
                ? BroadcastAudioState.superseded
                : BroadcastAudioState.idle,
      );
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
