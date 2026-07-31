import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/constants/api_constants.dart';

/// État applicatif du lecteur, mappé depuis just_audio et exposé à l'UI.
/// `reconnecting` = une erreur transitoire est en cours de reprise automatique
/// (STR-118) ; `error` = échec définitif (après épuisement des tentatives).
enum PlaybackStatus {
  idle,
  loading,
  buffering,
  playing,
  paused,
  reconnecting,
  ended,
  error,
}

/// Abstraction du lecteur exposée à l'UI (Dependency Inversion) : l'écran dépend
/// de cette interface, jamais directement de just_audio — ce qui permet de la
/// remplacer par un fake dans les widget tests. Implémentée par
/// [AudioPlayerController].
abstract class PlaybackController extends ChangeNotifier {
  PlaybackStatus get status;
  bool get isPlaying;
  bool get isBusy;
  bool get isReconnecting;
  bool get hasError;
  bool get isEnded;
  double get volume;

  Future<void> load(String streamId);
  Future<void> togglePlayPause();
  Future<void> setVolume(double value);
}

/// Sonde l'état d'un flux à partir de son manifeste HLS **public** : renvoie
/// `true` si le direct est terminé (manifeste 404/409), `false` sinon (200 ou
/// erreur réseau indéterminée). Injectée dans [AudioPlayerController] pour
/// distinguer « le direct est terminé » d'une simple coupure réseau (STR-118).
typedef StreamEndedProbe = Future<bool> Function(String streamId);

/// Contrôleur du lecteur audio HLS (STR-116/118, cf. [ADR 023]). Enveloppe un
/// [AudioPlayer] just_audio branché sur le manifeste **public** d'un flux et
/// expose un état simple + play/pause/volume. Gère les erreurs (STR-118) par une
/// **reconnexion automatique bornée** (perte réseau) puis un état d'erreur clair
/// (flux indisponible). Scopé à l'écran player : appeler [dispose] à la sortie.
class AudioPlayerController extends PlaybackController {
  AudioPlayerController({AudioPlayer? player, StreamEndedProbe? isStreamEnded})
      : _player = player ?? AudioPlayer(),
        _isStreamEnded = isStreamEnded {
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
    // Les erreurs de lecture (perte réseau, flux terminé → manifeste 404/409)
    // arrivent via le flux d'événements, pas via playerStateStream.
    _eventSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace _) => _fail(e),
    );
  }

  /// Nombre de reconnexions automatiques avant d'abandonner (STR-118).
  static const int _maxAutoRetries = 3;

  final AudioPlayer _player;
  final StreamEndedProbe? _isStreamEnded;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlaybackEvent>? _eventSub;
  Timer? _retryTimer;

  String? _streamId;
  int _retryCount = 0;
  bool _recovering = false;
  bool _disposed = false;
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
  bool get isReconnecting => _status == PlaybackStatus.reconnecting;
  @override
  bool get hasError => _status == PlaybackStatus.error;
  @override
  bool get isEnded => _status == PlaybackStatus.ended;
  @override
  double get volume => _volume;
  Object? get error => _error;

  /// Charge le flux [streamId] et démarre la lecture (autoplay, STR-108).
  /// Réinitialise le compteur de reconnexions (action utilisateur).
  @override
  Future<void> load(String streamId) async {
    _streamId = streamId;
    _retryCount = 0;
    await _start(streamId);
  }

  /// (Re)démarre effectivement la lecture du flux — partagé par [load], le
  /// retry automatique et [retry] (manuel). Ne touche pas au compteur.
  Future<void> _start(String streamId) async {
    if (_disposed) return;
    _retryTimer?.cancel();
    _error = null;
    _setStatus(PlaybackStatus.loading);
    try {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(ApiConstants.hlsPlaylist(streamId))),
      );
      if (_disposed) return;
      await _player.setVolume(_volume);
      await _player.play();
    } catch (e) {
      _fail(e);
    }
  }

  /// Bascule lecture/pause ; relance le flux si on est en erreur ou terminé, et
  /// ignore les taps pendant une transition (chargement / reconnexion).
  @override
  Future<void> togglePlayPause() async {
    if (hasError || isEnded) {
      await retry();
      return;
    }
    if (isBusy || isReconnecting) return;
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

  /// Relance le flux courant à la demande de l'utilisateur (bouton « réessayer »),
  /// en réarmant les reconnexions automatiques.
  Future<void> retry() async {
    final id = _streamId;
    if (id == null) return;
    _retryCount = 0;
    await _start(id);
  }

  void _onPlayerState(PlayerState state) {
    // États applicatifs terminaux/transitoires : on n'écrase pas avec un état
    // résiduel du player. `ended` en fait partie car _recover() est asynchrone
    // (attente de la sonde HTTP) et le player peut émettre un `idle` juste après
    // que la sonde a posé `ended` — sans ce garde, « Le direct est terminé »
    // régresserait en « En pause » (course, non systématique).
    if (_status == PlaybackStatus.reconnecting ||
        _status == PlaybackStatus.error ||
        _status == PlaybackStatus.ended) {
      return;
    }
    switch (state.processingState) {
      case ProcessingState.idle:
        _setStatus(PlaybackStatus.idle);
      case ProcessingState.loading:
        _setStatus(PlaybackStatus.loading);
      case ProcessingState.buffering:
        _setStatus(PlaybackStatus.buffering);
      case ProcessingState.ready:
        _retryCount = 0; // lecture rétablie : on réarme les reconnexions futures
        _setStatus(
          state.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        );
      case ProcessingState.completed:
        _setStatus(PlaybackStatus.ended);
    }
  }

  /// Échec de lecture : déclenche la reprise (au plus une à la fois). STR-118.
  void _fail(Object e) {
    if (_disposed) return;
    _error = e;
    if (kDebugMode) {
      debugPrint('AudioPlayerController: erreur de lecture: $e');
    }
    _recover();
  }

  /// Décide de la suite après un échec : d'abord distinguer une **fin de direct**
  /// (manifeste 404/409) d'une coupure réseau via la sonde, puis, si le flux est
  /// toujours là, tenter une **reconnexion automatique bornée** avec backoff
  /// (perte réseau), sinon basculer en erreur définitive (flux indisponible).
  Future<void> _recover() async {
    if (_recovering) return; // une seule reprise à la fois (échecs en rafale)
    _recovering = true;
    try {
      final id = _streamId;
      if (id == null) {
        _setStatus(PlaybackStatus.error);
        return;
      }
      // Fin de direct : le manifeste n'est plus servi (404/409) → pas de retry.
      final probe = _isStreamEnded;
      if (probe != null && await probe(id)) {
        if (_disposed) return;
        _setStatus(PlaybackStatus.ended);
        return;
      }
      if (_disposed) return;
      // Coupure réseau : reconnexion automatique bornée avec backoff (1, 2, 4 s).
      if (_retryCount < _maxAutoRetries) {
        _retryCount++;
        _setStatus(PlaybackStatus.reconnecting);
        final delay = Duration(seconds: 1 << (_retryCount - 1));
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, () {
          if (!_disposed) _start(id);
        });
      } else {
        _setStatus(PlaybackStatus.error);
      }
    } finally {
      _recovering = false;
    }
  }

  void _setStatus(PlaybackStatus status) {
    if (_disposed || _status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _stateSub?.cancel();
    _eventSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
