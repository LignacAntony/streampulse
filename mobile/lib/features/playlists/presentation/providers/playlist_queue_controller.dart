import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;

import '../../../../core/audio/playback_auth.dart';
import '../../../../core/audio/queue_playback_service.dart';
import '../../../../core/constants/api_constants.dart';
import '../../domain/entities/playlist_track.dart';

export '../../../../core/audio/queue_playback_service.dart' show PlaybackStatus;

/// Lecture d'une playlist avec file d'attente (US-05-04), hissée au niveau
/// application comme le lecteur de direct : la file survit à la navigation et à
/// la mise en arrière-plan (cf. ADR 031/033).
///
/// L'enchaînement des pistes n'est **pas** piloté ici : il est délégué au
/// lecteur natif, qui précharge la piste suivante. Ce contrôleur suit
/// `currentIndexStream` pour savoir où en est la file — une seule source de
/// vérité, donc pas de dérive possible entre ce que l'utilisateur entend et ce
/// que la file d'attente affiche, y compris quand le saut vient des boutons de
/// la notification.
class PlaylistQueueController extends ChangeNotifier {
  PlaylistQueueController({
    required QueuePlaybackService service,
    required PlaybackTokenProvider token,
    Future<void> Function()? stopLive,
  })  : _service = service,
        _token = token,
        _stopLive = stopLive {
    _stateSub = _service.playerStateStream.listen(_onPlayerState);
    _indexSub = _service.currentIndexStream.listen(_onIndexChanged);
    _errorSub = _service.playbackErrors.listen(_onError);
  }

  final QueuePlaybackService _service;
  final PlaybackTokenProvider _token;

  /// Arrête le direct avant de prendre le lecteur partagé. Sans ça, le
  /// mini-player continuerait d'annoncer un flux qui ne joue plus.
  final Future<void> Function()? _stopLive;

  /// Nombre de reprises automatiques avant d'abandonner, avec backoff 1/2/4 s
  /// (même discipline que le direct, STR-118).
  static const int _maxAutoRetries = 3;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<Object>? _errorSub;
  Timer? _retryTimer;

  List<PlaylistTrack> _tracks = const [];
  String? _playlistId;
  String? _playlistName;
  int _index = 0;
  PlaybackStatus _status = PlaybackStatus.idle;
  bool _disposed = false;

  /// Reprises déjà tentées sur la piste courante.
  ///
  /// Remis à zéro sur une **action utilisateur** (lancement, saut) et sur un
  /// **changement de piste** — c'est-à-dire quand la file a réellement avancé.
  /// Volontairement pas à chaque `ready` : une piste qui s'ouvre puis
  /// re-échoue en boucle (réseau instable) rearmerait indéfiniment le compteur,
  /// et l'auditeur verrait la même piste repartir sans fin au lieu d'une erreur
  /// franche qu'il peut relancer lui-même.
  int _retryCount = 0;

  /// Numéro de la file courante. Un chargement asynchrone dont le numéro n'est
  /// plus le bon (l'utilisateur a lancé une autre playlist entre-temps) est
  /// abandonné plutôt que d'écraser l'état de la nouvelle.
  int _generation = 0;

  List<PlaylistTrack> get tracks => _tracks;
  String? get playlistId => _playlistId;
  String? get playlistName => _playlistName;
  int get currentIndex => _index;
  PlaybackStatus get status => _status;

  /// La file est-elle active ? Faux à l'arrêt : le mini-player s'efface et rend
  /// la place au direct.
  bool get hasQueue =>
      _tracks.isNotEmpty && _status != PlaybackStatus.idle;

  PlaylistTrack? get currentTrack =>
      _index >= 0 && _index < _tracks.length ? _tracks[_index] : null;

  bool get isPlaying => _status == PlaybackStatus.playing;
  bool get isBusy =>
      _status == PlaybackStatus.loading || _status == PlaybackStatus.buffering;
  bool get hasError => _status == PlaybackStatus.error;
  bool get isEnded => _status == PlaybackStatus.ended;
  bool get isReconnecting => _status == PlaybackStatus.reconnecting;
  bool get hasNext => _index < _tracks.length - 1;
  bool get hasPrevious => _index > 0;

  /// Lance [tracks] à partir de [startIndex] et démarre la lecture.
  Future<void> play({
    required String playlistId,
    required String playlistName,
    required List<PlaylistTrack> tracks,
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;

    // Générations : arrêter le direct est asynchrone, et la file peut être
    // abandonnée entre-temps (clear/stop). Sans ce jeton, une playlist annulée
    // pendant la bascule se remettrait à jouer.
    final generation = ++_generation;
    // Statut posé **avant** d'arrêter le direct : `stopLive` fait émettre un
    // `idle` au lecteur partagé alors que la file précédente est encore
    // affichée. Sans ce `loading`, `hasQueue` passerait à false le temps d'un
    // battement et le mini-player clignoterait à chaque relancement.
    _setStatus(PlaybackStatus.loading);
    await _stopLive?.call();
    if (_disposed || generation != _generation) return;

    _tracks = List.unmodifiable(tracks);
    _playlistId = playlistId;
    _playlistName = playlistName;
    _index = startIndex.clamp(0, tracks.length - 1);
    _retryCount = 0;
    await _load(fromIndex: _index);
  }

  /// Saute à la piste [index] de la file (« sauter à n'importe quelle piste »).
  Future<void> skipTo(int index) async {
    if (_tracks.isEmpty || index < 0 || index >= _tracks.length) return;
    // Après la fin de la file (ou un échec), la source native n'est plus
    // exploitable : on la recharge à la piste demandée plutôt que d'y sauter.
    if (isEnded || hasError) {
      _index = index;
      _retryCount = 0;
      await _load(fromIndex: index);
      return;
    }
    _retryCount = 0; // action utilisateur : on réarme les reprises
    _retryTimer?.cancel();
    _setIndex(index);
    await _service.skipToIndex(index);
    await _service.play();
  }

  Future<void> next() => hasNext ? skipTo(_index + 1) : Future.value();
  Future<void> previous() => hasPrevious ? skipTo(_index - 1) : Future.value();

  /// Bascule lecture/pause ; relance la file si elle est terminée ou en erreur.
  Future<void> togglePlayPause() async {
    if (_tracks.isEmpty) return;
    if (isEnded || hasError) {
      _retryCount = 0;
      await _load(fromIndex: isEnded ? 0 : _index);
      return;
    }
    if (isBusy || isReconnecting) return;
    if (_service.playing) {
      await _service.pause();
    } else {
      await _service.play();
    }
  }

  /// Arrête la lecture et vide la file (croix du mini-player).
  Future<void> stop() async {
    _reset();
    await _service.stop();
  }

  /// Abandonne la file **sans toucher au lecteur** : le direct vient de prendre
  /// la main sur la source partagée, l'arrêter ici couperait sa lecture.
  void clear() {
    if (_tracks.isEmpty && _status == PlaybackStatus.idle) {
      // Rien à effacer à l'écran, mais un lancement peut être en vol : il doit
      // être invalidé lui aussi, sinon il prendrait le lecteur au direct.
      _generation++;
      return;
    }
    _reset();
  }

  /// (Re)charge la file dans le lecteur à partir de [fromIndex], à [position]
  /// dans cette piste. [refreshToken] force une rotation de l'access token
  /// (première reprise après échec).
  Future<void> _load({
    required int fromIndex,
    Duration position = Duration.zero,
    bool refreshToken = false,
  }) async {
    final generation = ++_generation;
    _setStatus(PlaybackStatus.loading);
    try {
      final token = await _token(forceRefresh: refreshToken);
      if (_disposed || generation != _generation) return;

      await _service.loadQueue(
        [
          for (final track in _tracks)
            QueueItem(
              id: track.id,
              url: ApiConstants.trackStream(track.id),
              title: track.title,
              artist: track.artist,
              duration: track.durationS == null
                  ? null
                  : Duration(seconds: track.durationS!),
            ),
        ],
        initialIndex: fromIndex,
        initialPosition: position,
        headers: token == null ? const {} : {'Authorization': 'Bearer $token'},
      );
      if (_disposed || generation != _generation) return;
      await _service.play();
    } catch (e) {
      if (generation != _generation) return;
      _onError(e);
    }
  }

  void _onPlayerState(PlayerState state) {
    if (_tracks.isEmpty) return;
    // États décidés par le contrôleur, pas par le lecteur : `error` et `ended`
    // sont terminaux, `reconnecting` est une transition qu'une reprise en cours
    // pilote. Un événement résiduel du lecteur ne doit repeindre aucun des
    // trois — sinon un `idle` arrivant juste après `completed` ferait
    // disparaître le mini-player « File d'attente terminée », et avec lui le
    // bouton de relance.
    if (_status == PlaybackStatus.error ||
        _status == PlaybackStatus.ended ||
        _status == PlaybackStatus.reconnecting) {
      return;
    }
    // Pendant un (re)chargement, l'`idle` émis par le lecteur en libérant sa
    // source précédente n'est pas un état à afficher.
    if (_status == PlaybackStatus.loading &&
        state.processingState == ProcessingState.idle) {
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
        _setStatus(
          state.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        );
      case ProcessingState.completed:
        // Fin de la **dernière** piste : l'enchaînement intermédiaire ne passe
        // pas par `completed`.
        _setStatus(PlaybackStatus.ended);
    }
  }

  /// Le lecteur a changé de piste (enchaînement automatique, boutons de la
  /// notification, ou saut demandé ici) : la file d'attente affichée suit.
  void _onIndexChanged(int? index) {
    if (index == null || _tracks.isEmpty) return;
    if (index < 0 || index >= _tracks.length) return;
    // La file a réellement avancé : les reprises consommées sur la piste
    // précédente ne doivent pas peser sur la suivante.
    if (index != _index) _retryCount = 0;
    _setIndex(index);
  }

  /// Échec de lecture : reprise automatique **bornée**, backoff 1/2/4 s, en
  /// repartant de la position atteinte dans la piste courante — une coupure
  /// réseau brève ne doit pas faire recommencer le morceau.
  ///
  /// Seule la **première** tentative force une rotation de l'access token :
  /// c'est le remède à une expiration en cours de file (15 min), et si une
  /// rotation n'a pas suffi, en enchaîner d'autres ne changera rien. Tentatives
  /// épuisées → état d'erreur, que l'utilisateur relance explicitement.
  void _onError(Object error) {
    if (_disposed || _tracks.isEmpty) return;
    if (kDebugMode) {
      debugPrint('PlaylistQueueController: erreur de lecture: $error');
    }
    if (_retryCount >= _maxAutoRetries) {
      _setStatus(PlaybackStatus.error);
      return;
    }

    // Position relevée maintenant : après le délai, le lecteur aura pu être
    // réinitialisé et l'aurait perdue.
    final resumeAt = _service.position;
    final refreshToken = _retryCount == 0;
    _retryCount++;
    _setStatus(PlaybackStatus.reconnecting);

    final delay = Duration(seconds: 1 << (_retryCount - 1));
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_disposed || _tracks.isEmpty) return;
      unawaited(_load(
        fromIndex: _index,
        position: resumeAt,
        refreshToken: refreshToken,
      ));
    });
  }

  /// Vide la file et repasse à `idle`. Le `_generation++` invalide un chargement
  /// encore en vol : sans lui, une file arrêtée pourrait se remettre à jouer.
  void _reset() {
    _retryTimer?.cancel();
    _tracks = const [];
    _playlistId = null;
    _playlistName = null;
    _index = 0;
    _retryCount = 0;
    _generation++;
    _status = PlaybackStatus.idle;
    if (!_disposed) notifyListeners();
  }

  void _setIndex(int index) {
    if (_disposed || _index == index) return;
    _index = index;
    notifyListeners();
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
    _indexSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
