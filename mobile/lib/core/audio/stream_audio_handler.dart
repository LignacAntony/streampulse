import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_playback_service.dart';
import 'queue_playback_service.dart';

/// Implémentation de [AudioPlaybackService] et [QueuePlaybackService] via
/// `audio_service` + `just_audio` (STR-109/US-05-04, cf. ADR 031 et 033).
/// Enveloppe **un seul** [AudioPlayer] hébergé par le service de premier plan
/// `audio_service` : la lecture survit à la mise en arrière-plan / au
/// verrouillage, et les transitions du lecteur alimentent la notification et les
/// contrôles écran verrouillé.
///
/// Les deux usages — direct HLS et file d'attente d'une playlist — passent par
/// ce même lecteur : charger l'un remplace l'autre, ce qui est exactement le
/// comportement attendu (on n'écoute pas deux sources à la fois). Les
/// contrôleurs applicatifs se chargent d'aligner leur état sur cette bascule.
///
/// Ce handler reste « bête » sur les erreurs : il les **transmet** au contrôleur
/// (via [playbackErrors]) sans décider lui-même de la reprise — l'arbitrage
/// sonde → `ended` versus reconnexion appartient au [AudioPlayerController]
/// (STR-118), qui pilote ensuite `play`/`stop`.
class StreamAudioHandler extends BaseAudioHandler
    implements AudioPlaybackService, QueuePlaybackService {
  StreamAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    // Chaque événement du lecteur → un PlaybackState pour la notification. Les
    // erreurs sont routées vers [playbackErrors] (le contrôleur les gère), et
    // ne cassent pas le flux de la notification. Le handler vit aussi longtemps
    // qu'`audio_service` : ces abonnements n'ont pas à être annulés.
    _player.playbackEventStream.listen(
      (event) => playbackState.add(_transform(event)),
      onError: (Object e, StackTrace _) => _errors.add(e),
    );
    // La piste courante change (enchaînement automatique ou saut) : la
    // notification doit suivre, sinon l'écran verrouillé annonce encore la
    // piste précédente.
    _player.currentIndexStream.listen(_onIndexChanged);
  }

  final AudioPlayer _player;
  final _errors = StreamController<Object>.broadcast();

  /// File d'attente courante, vide en lecture de direct. Sert à choisir les
  /// contrôles de la notification (précédent/suivant n'ont de sens qu'ici) et à
  /// republier le `MediaItem` à chaque changement de piste.
  List<MediaItem> _queueItems = const [];

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  @override
  Stream<Object> get playbackErrors => _errors.stream;
  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  @override
  bool get playing => _player.playing;

  @override
  Future<void> loadUri(String url, {required NowPlaying now}) async {
    // Métadonnées de l'écran verrouillé / notification. Un flux live n'a pas de
    // durée : `isLive` masque la barre de progression côté OS.
    _queueItems = const [];
    queue.add(const []);
    mediaItem.add(
      MediaItem(
        id: now.streamId,
        title: now.title,
        artist: now.broadcaster,
        isLive: true,
      ),
    );
    _hasSource = true;
    await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
  }

  @override
  Future<void> loadQueue(
    List<QueueItem> items, {
    int initialIndex = 0,
    Map<String, String> headers = const {},
  }) async {
    if (items.isEmpty) {
      await stop();
      return;
    }
    // Borne défensive : un index hors file ferait lever setAudioSource et
    // laisserait la notification décrire une piste qu'on ne joue pas.
    final start = initialIndex.clamp(0, items.length - 1);

    _queueItems = [for (final item in items) _toMediaItem(item)];
    queue.add(_queueItems);
    mediaItem.add(_queueItems[start]);
    _hasSource = true;

    await _player.setAudioSource(
      // L'enchaînement piste → piste suivante est délégué au lecteur natif :
      // c'est lui qui préchargera la suivante, sans blanc entre les deux.
      ConcatenatingAudioSource(
        children: [
          for (final item in items)
            AudioSource.uri(
              Uri.parse(item.url),
              headers: headers.isEmpty ? null : headers,
            ),
        ],
      ),
      initialIndex: start,
      initialPosition: Duration.zero,
    );
  }

  @override
  Future<void> skipToIndex(int index) async {
    if (!_hasSource || index < 0 || index >= _queueItems.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  /// Refuse les commandes de transport quand plus rien n'est chargé.
  ///
  /// Android garde une carte média (« reprise ») après l'arrêt, et son bouton
  /// lecture rejoue le dernier `MediaItem` : sans ce garde, appuyer dessus
  /// relancerait la piste alors que l'application a **déjà** vidé sa file et
  /// masqué son lecteur — l'OS jouerait ce que l'app dit ne pas jouer.
  bool _hasSource = false;

  @override
  Future<void> play() async {
    if (!_hasSource) return;
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _hasSource = false;
    await _player.stop();
    _queueItems = const [];
    queue.add(const []);
    mediaItem.add(null); // retire la notification
    // État terminal publié explicitement : le dernier événement du lecteur peut
    // arriver après coup, et `audio_service` ne retire sa notification qu'en
    // voyant un état `idle` sans contrôle.
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const [],
        systemActions: const {},
      ),
    );
    await super.stop();
  }

  /// Contrôles système de la file d'attente (boutons de la notification, casque
  /// Bluetooth, écran verrouillé). Ils pilotent le lecteur directement : le
  /// contrôleur applicatif suit ensuite via `currentIndexStream`, ce qui évite
  /// deux sources de vérité sur la position dans la file.
  @override
  Future<void> skipToNext() async {
    if (!_hasSource) return;
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (!_hasSource) return;
    await _player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) => skipToIndex(index);

  @override
  Future<void> seek(Duration position) async {
    if (!_hasSource) return;
    await _player.seek(position);
  }

  MediaItem _toMediaItem(QueueItem item) => MediaItem(
        id: item.id,
        title: item.title,
        artist: item.artist,
        duration: item.duration,
      );

  /// Republie le `MediaItem` de la piste atteinte. Ne fait rien hors file
  /// d'attente : en direct, l'unique `MediaItem` est posé par [loadUri].
  void _onIndexChanged(int? index) {
    if (_queueItems.isEmpty || index == null) return;
    if (index < 0 || index >= _queueItems.length) return;
    mediaItem.add(_queueItems[index]);
  }

  /// Mappe un événement just_audio vers l'état `audio_service` qui pilote la
  /// notification. Les contrôles dépendent de la source : en direct, play/pause
  /// + stop ; en file d'attente, on ajoute précédent/suivant et l'action `seek`
  /// (une piste a une durée, contrairement à un live).
  PlaybackState _transform(PlaybackEvent event) {
    final playing = _player.playing;
    final hasQueue = _queueItems.length > 1;
    return PlaybackState(
      controls: [
        if (hasQueue) MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        if (hasQueue) MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        if (hasQueue) ...{
          MediaAction.seek,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
      },
      // Les indices compacts pointent les contrôles à garder sur la
      // notification repliée : précédent/lecture/suivant avec une file, sinon
      // lecture/stop comme en direct.
      androidCompactActionIndices: hasQueue ? const [0, 1, 2] : const [0, 1],
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
      queueIndex: _player.currentIndex,
    );
  }
}
