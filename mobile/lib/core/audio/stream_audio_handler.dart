import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_playback_service.dart';
import 'interruption_policy.dart';

/// Implémentation de [AudioPlaybackService] via `audio_service` + `just_audio`
/// (STR-109, cf. ADR 031). Enveloppe **un seul** [AudioPlayer] hébergé par le
/// service de premier plan `audio_service` : la lecture survit à la mise en
/// arrière-plan / au verrouillage, et les transitions du lecteur alimentent la
/// notification et les contrôles écran verrouillé (play/pause/stop).
///
/// Ce handler reste « bête » sur les erreurs : il les **transmet** au contrôleur
/// (via [playbackErrors]) sans décider lui-même de la reprise — l'arbitrage
/// sonde → `ended` versus reconnexion appartient au [AudioPlayerController]
/// (STR-118), qui pilote ensuite `play`/`stop`.
class StreamAudioHandler extends BaseAudioHandler
    implements AudioPlaybackService {
  StreamAudioHandler({AudioPlayer? player})
    : _player = player ?? AudioPlayer(handleInterruptions: false) {
    // Chaque événement du lecteur → un PlaybackState pour la notification. Les
    // erreurs sont routées vers [playbackErrors] (le contrôleur les gère), et
    // ne cassent pas le flux de la notification. Le handler vit aussi longtemps
    // qu'`audio_service` : cet abonnement n'a pas à être annulé.
    _player.playbackEventStream.listen(
      (event) => playbackState.add(_transform(event)),
      onError: (Object e, StackTrace _) => _errors.add(e),
    );
  }

  final AudioPlayer _player;
  final _errors = StreamController<Object>.broadcast();
  final _interruptions = InterruptionPolicy();

  /// Volume appliqué pendant l'atténuation (ducking) d'une interruption
  /// transitoire (notification).
  static const double _duckVolume = 0.4;

  /// Volume à restaurer après un ducking (capturé juste avant, pour ne pas
  /// écraser un réglage éventuel plutôt que de remettre 1.0 en dur).
  double _preDuckVolume = 1;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  @override
  Stream<Object> get playbackErrors => _errors.stream;
  @override
  bool get playing => _player.playing;

  @override
  Future<void> loadUri(String url, {required NowPlaying now}) async {
    // Métadonnées de l'écran verrouillé / notification. Un flux live n'a pas de
    // durée : `isLive` masque la barre de progression côté OS.
    mediaItem.add(
      MediaItem(
        id: now.streamId,
        title: now.title,
        artist: now.broadcaster,
        isLive: true,
      ),
    );
    await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    mediaItem.add(null); // retire la notification
    await super.stop();
  }

  /// Configure la session audio (catégorie `music`) et branche la gestion des
  /// interruptions (STR-110). Le player est en `handleInterruptions: false` :
  /// c'est [InterruptionPolicy] qui décide, ici on ne fait que traduire.
  ///
  /// **Public et appelé explicitement depuis `main()`** (pas dans le
  /// constructeur) : effet de bord plateforme à ordonner et dont l'erreur doit
  /// être rattrapée par l'appelant.
  Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // Appel entrant / autre app (pause ou ducking) + fin d'interruption.
    session.interruptionEventStream.listen((event) {
      _apply(
        _interruptions.onInterruption(
          begin: event.begin,
          isDuck: event.type == AudioInterruptionType.duck,
          canResume: event.type == AudioInterruptionType.pause,
          isPlaying: _player.playing,
        ),
      );
    });
    // Casque / sortie audio débranché.
    session.becomingNoisyEventStream.listen((_) {
      _apply(_interruptions.onBecomingNoisy(isPlaying: _player.playing));
    });
  }

  void _apply(InterruptionAction action) {
    switch (action) {
      case InterruptionAction.pause:
        unawaited(_player.pause());
      case InterruptionAction.resume:
        // Défensif : si un `unduck` s'était perdu, on ne reprend pas à 0.4.
        unawaited(_player.setVolume(_preDuckVolume));
        unawaited(_player.play());
      case InterruptionAction.duck:
        _preDuckVolume = _player.volume; // capture avant d'atténuer
        unawaited(_player.setVolume(_duckVolume));
      case InterruptionAction.unduck:
        unawaited(_player.setVolume(_preDuckVolume));
      case InterruptionAction.none:
        break;
    }
  }

  /// Mappe un événement just_audio vers l'état `audio_service` qui pilote la
  /// notification (contrôles contextuels play/pause + stop).
  PlaybackState _transform(PlaybackEvent event) {
    final playing = _player.playing;
    return PlaybackState(
      controls: [
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1],
      // `?? idle` : une valeur d'enum ajoutée par une future version de
      // just_audio ne doit pas lever dans ce listener (ça tuerait le flux de
      // playbackState → notification figée).
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState] ??
          AudioProcessingState.idle,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
    );
  }
}
