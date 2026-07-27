import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/constants/api_constants.dart';

/// État applicatif du lecteur, mappé depuis just_audio et exposé à l'UI.
enum PlaybackStatus { idle, loading, buffering, playing, paused, ended, error }

/// Abstraction du lecteur exposée à l'UI (Dependency Inversion) : l'écran dépend
/// de cette interface, jamais directement de just_audio — ce qui permet de la
/// remplacer par un fake dans les widget tests. Implémentée par
/// [AudioPlayerController].
abstract class PlaybackController extends ChangeNotifier {
  PlaybackStatus get status;
  bool get isPlaying;
  bool get isBusy;
  bool get hasError;
  bool get isEnded;
  double get volume;

  Future<void> load(String streamId);
  Future<void> togglePlayPause();
  Future<void> setVolume(double value);
}

/// Contrôleur du lecteur audio HLS (STR-116, cf. [ADR 022]). Enveloppe un
/// [AudioPlayer] just_audio branché sur le manifeste **public** d'un flux et
/// expose un état simple + play/pause/volume. Scopé à l'écran player : appeler
/// [dispose] à la sortie (le partage inter-écrans = lecture arrière-plan, STR-109).
class AudioPlayerController extends PlaybackController {
  AudioPlayerController({AudioPlayer? player})
      : _player = player ?? AudioPlayer() {
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
    // Les erreurs de lecture (perte réseau, flux terminé → manifeste 404/409)
    // arrivent via le flux d'événements, pas via playerStateStream.
    _eventSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace _) => _fail(e),
    );
  }

  final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlaybackEvent>? _eventSub;

  String? _streamId;
  PlaybackStatus _status = PlaybackStatus.idle;
  double _volume = 1;
  Object? _error;

  @override
  PlaybackStatus get status => _status;
  @override
  bool get isPlaying => _status == PlaybackStatus.playing;
  @override
  bool get isBusy =>
      _status == PlaybackStatus.loading || _status == PlaybackStatus.buffering;
  @override
  bool get hasError => _status == PlaybackStatus.error;
  @override
  bool get isEnded => _status == PlaybackStatus.ended;
  @override
  double get volume => _volume;
  Object? get error => _error;

  /// Charge le flux [streamId] (URL du manifeste public) et démarre la lecture
  /// automatiquement (autoplay, STR-108).
  @override
  Future<void> load(String streamId) async {
    _streamId = streamId;
    _error = null;
    _setStatus(PlaybackStatus.loading);
    try {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(ApiConstants.hlsPlaylist(streamId))),
      );
      await _player.setVolume(_volume);
      await _player.play();
    } catch (e) {
      _fail(e);
    }
  }

  /// Bascule lecture/pause ; relance le flux si on est en erreur ou terminé.
  @override
  Future<void> togglePlayPause() async {
    if (hasError || isEnded) {
      await retry();
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(_volume);
    notifyListeners();
  }

  /// Recharge le flux courant (bouton « réessayer »).
  Future<void> retry() async {
    final id = _streamId;
    if (id != null) await load(id);
  }

  void _onPlayerState(PlayerState state) {
    // Une erreur reste « collante » jusqu'à un retry explicite.
    if (_status == PlaybackStatus.error) return;
    switch (state.processingState) {
      case ProcessingState.idle:
        _setStatus(PlaybackStatus.idle);
      case ProcessingState.loading:
        _setStatus(PlaybackStatus.loading);
      case ProcessingState.buffering:
        _setStatus(PlaybackStatus.buffering);
      case ProcessingState.ready:
        _setStatus(
          state.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        );
      case ProcessingState.completed:
        _setStatus(PlaybackStatus.ended);
    }
  }

  void _fail(Object e) {
    _error = e;
    if (kDebugMode) {
      debugPrint('AudioPlayerController: erreur de lecture: $e');
    }
    _setStatus(PlaybackStatus.error);
  }

  void _setStatus(PlaybackStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _eventSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
