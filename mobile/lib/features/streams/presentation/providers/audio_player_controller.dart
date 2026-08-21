import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;

import '../../../../core/audio/audio_playback_service.dart';
import '../../../../core/constants/api_constants.dart';

export '../../../../core/audio/audio_playback_service.dart'
    show NowPlaying, PlaybackStatus;

/// Abstraction du lecteur exposée à l'UI (Dependency Inversion) : les écrans et
/// le mini-player dépendent de cette interface, jamais directement de
/// just_audio / audio_service — ce qui permet de la remplacer par un fake dans
/// les widget tests. Implémentée par [AudioPlayerController].
abstract class PlaybackController extends ChangeNotifier {
  PlaybackStatus get status;
  bool get isPlaying;
  bool get isBusy;
  bool get isReconnecting;
  bool get hasError;
  bool get isEnded;

  /// Flux en cours (titre + diffuseur), ou `null` si rien ne joue. Alimente le
  /// mini-player et l'affichage plein écran.
  NowPlaying? get nowPlaying;

  Future<void> load(NowPlaying now);
  Future<void> togglePlayPause();

  /// Arrête la lecture et repasse à l'état `idle` (fermeture du mini-player).
  Future<void> stop();
}

/// Sonde le manifeste HLS **public** : `true` s'il n'est plus servi (404/409),
/// `false` sinon (200 en direct, ou réseau indéterminé). Le 409 étant ambigu
/// (fin de direct **ou** démarrage pas encore prêt), le contrôleur ne conclut
/// « terminé » qu'en le combinant à [_hasPlayed] (STR-118/109).
typedef ManifestUnavailableProbe = Future<bool> Function(String streamId);

/// Contrôleur du lecteur audio HLS, **hissé au niveau application** (STR-109,
/// cf. [ADR 031]). Pilote un [AudioPlaybackService] partagé (service de premier
/// plan `audio_service`) : la lecture survit à la navigation et à la mise en
/// arrière-plan. Expose un état applicatif simple + play/pause, et gère les
/// erreurs (STR-118) par une **reconnexion automatique bornée** (perte réseau)
/// puis un état d'erreur clair (flux indisponible).
///
/// Le **volume ne passe pas par ce contrôleur** (STR-245) : il vit sur le
/// transport, et le curseur s'y abonne directement. Un glissement émet des
/// dizaines de valeurs par seconde ; les faire transiter par un `notifyListeners`
/// app-level reconstruirait tout l'arbre sous ce contrôleur à cette cadence.
class AudioPlayerController extends PlaybackController {
  AudioPlayerController({
    required AudioPlaybackService service,
    ManifestUnavailableProbe? isManifestUnavailable,
  })  : _service = service,
        _isManifestUnavailable = isManifestUnavailable {
    _stateSub = _service.playerStateStream.listen(_onPlayerState);
    // Les erreurs de lecture (perte réseau, flux terminé → manifeste 404/409)
    // arrivent via un flux dédié, pas via playerStateStream.
    _errorSub = _service.playbackErrors.listen(_fail);
  }

  /// Nombre de reconnexions automatiques avant d'abandonner (STR-118). Couvre
  /// aussi la fenêtre de démarrage du manifeste (~10 s, segments HLS de 10 s) :
  /// backoff 1+2+4+8 = 15 s avant de conclure sur un flux qui n'a jamais démarré.
  static const int _maxAutoRetries = 4;

  final AudioPlaybackService _service;
  final ManifestUnavailableProbe? _isManifestUnavailable;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Object>? _errorSub;
  Timer? _retryTimer;

  NowPlaying? _nowPlaying;
  int _retryCount = 0;
  bool _recovering = false;
  bool _disposed = false;
  // La lecture a-t-elle déjà atteint `ready` sur ce flux ? Sert à lever
  // l'ambiguïté du 409 : si oui, un manifeste qui disparaît = fin de direct ; si
  // non, c'est probablement la fenêtre de démarrage (manifeste pas encore prêt).
  bool _hasPlayed = false;
  PlaybackStatus _status = PlaybackStatus.idle;
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
  NowPlaying? get nowPlaying => _nowPlaying;
  Object? get error => _error;

  /// Appelé **avant** que le direct ne reprenne le lecteur partagé, pour que la
  /// file d'attente d'une playlist (US-05-04) libère son état : les deux
  /// sources se partagent un unique lecteur natif, celle qui perd la main doit
  /// cesser de prétendre jouer. Posé après construction (le contrôleur de file
  /// est créé plus tard dans l'arbre de providers).
  void Function()? onTakeOver;

  /// Charge le flux [now] et démarre la lecture (autoplay, STR-108). Réinitialise
  /// le compteur de reconnexions (action utilisateur).
  @override
  Future<void> load(NowPlaying now) async {
    onTakeOver?.call();
    _nowPlaying = now;
    _retryCount = 0;
    _hasPlayed = false;
    await _start();
  }

  /// (Re)démarre effectivement la lecture du flux courant — partagé par [load],
  /// le retry automatique et [retry] (manuel). Ne touche pas au compteur.
  Future<void> _start() async {
    if (_disposed) return;
    final now = _nowPlaying;
    if (now == null) return;
    _retryTimer?.cancel();
    _error = null;
    _setStatus(PlaybackStatus.loading);
    try {
      await _service.loadUri(ApiConstants.hlsPlaylist(now.streamId), now: now);
      if (_disposed) return;
      await _service.play();
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
    if (_service.playing) {
      await _service.pause();
    } else {
      await _service.play();
    }
  }

  @override
  Future<void> stop() async {
    _retryTimer?.cancel();
    _retryCount = 0;
    _hasPlayed = false;
    _nowPlaying = null;
    _error = null;
    await _service.stop();
    _setStatus(PlaybackStatus.idle);
  }

  /// Relance le flux courant à la demande de l'utilisateur (bouton « réessayer »),
  /// en réarmant les reconnexions automatiques.
  Future<void> retry() async {
    if (_nowPlaying == null) return;
    _retryCount = 0;
    await _start();
  }

  void _onPlayerState(PlayerState state) {
    // Aucun flux chargé : les états reçus décrivent une **autre** source (la
    // file d'attente d'une playlist joue sur le même lecteur natif, US-05-04).
    // Sans ce garde, ce contrôleur se croirait en lecture alors qu'il n'a rien
    // à jouer.
    if (_nowPlaying == null) return;
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
        _hasPlayed = true; // le manifeste a été servi au moins une fois
        _setStatus(
          state.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        );
      case ProcessingState.completed:
        _setStatus(PlaybackStatus.ended);
    }
  }

  /// Échec de lecture : déclenche la reprise (au plus une à la fois). STR-118.
  void _fail(Object e) {
    // Même raison que dans [_onPlayerState] : sans flux chargé, l'erreur vient
    // de l'autre source du lecteur partagé et ne nous concerne pas.
    if (_disposed || _nowPlaying == null) return;
    _error = e;
    if (kDebugMode) {
      debugPrint('AudioPlayerController: erreur de lecture: $e');
    }
    _recover();
  }

  /// Décide de la suite après un échec (STR-118/109).
  ///
  /// On ne sonde le manifeste que lorsque c'est **décisif** : soit la lecture
  /// avait démarré (sa disparition = fin de direct → `ended` immédiat), soit les
  /// reconnexions sont épuisées (verdict final). Pendant la fenêtre de démarrage
  /// (jamais joué, manifeste pas encore prêt → 409, comme une fin de direct) on
  /// **reconnecte d'abord** plutôt que de conclure à tort « terminé ».
  Future<void> _recover() async {
    if (_recovering) return; // une seule reprise à la fois (échecs en rafale)
    _recovering = true;
    try {
      final id = _nowPlaying?.streamId;
      if (id == null) {
        _setStatus(PlaybackStatus.error);
        return;
      }
      final retriesExhausted = _retryCount >= _maxAutoRetries;
      final probe = _isManifestUnavailable;
      final manifestGone = probe != null &&
          (_hasPlayed || retriesExhausted) &&
          await probe(id);
      // La sonde est asynchrone : si entre-temps l'utilisateur a fermé le
      // lecteur (`stop()`) ou lancé un autre flux, cette reprise est caduque.
      if (_disposed || _nowPlaying?.streamId != id) return;

      // La lecture avait démarré et le manifeste a disparu → fin de direct.
      if (manifestGone && _hasPlayed) {
        _setStatus(PlaybackStatus.ended);
        await _service.stop(); // retire la notification (le direct est fini)
        return;
      }
      // Reconnexion automatique bornée (coupure réseau, ou manifeste pas encore
      // prêt au démarrage) avec backoff 1, 2, 4, 8 s.
      if (!retriesExhausted) {
        _retryCount++;
        _setStatus(PlaybackStatus.reconnecting);
        final delay = Duration(seconds: 1 << (_retryCount - 1));
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, () {
          if (!_disposed) _start();
        });
        return;
      }
      // Tentatives épuisées : manifeste jamais servi = flux terminé / pas live ;
      // sinon indisponibilité réseau.
      _setStatus(manifestGone ? PlaybackStatus.ended : PlaybackStatus.error);
      await _service.stop(); // notification retirée
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
    // Contrôleur app-level : on libère nos abonnements, mais **pas** le service
    // partagé (sa durée de vie est celle d'`audio_service`, gérée à part).
    _disposed = true;
    _retryTimer?.cancel();
    _stateSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
