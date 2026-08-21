import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_playback_service.dart';
import 'interruption_policy.dart';
import 'queue_playback_service.dart';
import 'volume_level.dart';

/// Implémentation de [AudioPlaybackService] et [QueuePlaybackService] via
/// `audio_service` + `just_audio` (STR-109/US-05-04, cf. ADR 031, 033 et 034).
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
  // `handleInterruptions: false` : c'est [InterruptionPolicy] qui arbitre les
  // appels entrants et le débranchement du casque (STR-110), pas just_audio.
  StreamAudioHandler({AudioPlayer? player})
    : _player = player ?? AudioPlayer(handleInterruptions: false) {
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
  final _interruptions = InterruptionPolicy();

  /// Réglage de l'auditeur et atténuation en cours (STR-244). La règle qui les
  /// combine vit dans [VolumeLevel], objet pur — le handler ne fait que
  /// l'appliquer au lecteur.
  VolumeLevel _volumeLevel = const VolumeLevel();

  final _volumes = StreamController<double>.broadcast();

  /// File d'attente courante, vide en lecture de direct. Sert à choisir les
  /// contrôles de la notification (précédent/suivant n'ont de sens qu'ici) et à
  /// republier le `MediaItem` à chaque changement de piste.
  List<MediaItem> _queueItems = const [];

  @override
  double get volume => _volumeLevel.user;

  @override
  Stream<double> get volumeStream => _volumes.stream;

  @override
  Future<void> setVolume(double volume) async {
    final next = _volumeLevel.withUser(volume);
    if (next == _volumeLevel) return;
    _volumeLevel = next;
    // Le niveau publié est celui de l'auditeur, le niveau appliqué tient compte
    // d'une atténuation en cours : régler le volume pendant une notification
    // doit s'entendre tout de suite, sans annuler l'atténuation.
    _volumes.add(next.user);
    await _player.setVolume(next.effective);
  }

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  @override
  Stream<Object> get playbackErrors => _errors.stream;
  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  @override
  Duration get position => _player.position;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  bool get playing => _player.playing;

  /// Ordre de lecture effectif tel que le lecteur natif le tient (US-05-05).
  /// `effectiveIndices` vaut `null` tant qu'aucune source n'est chargée : on
  /// rend alors l'ordre naturel plutôt que rien, pour que l'appelant n'ait pas
  /// de cas nul à traiter avant le premier chargement.
  @override
  PlaybackOrder get playbackOrder {
    final indices = _player.effectiveIndices;
    if (indices == null) return PlaybackOrder.natural(_queueItems.length);
    return PlaybackOrder(List.unmodifiable(indices));
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    // `shuffle()` **avant** l'activation : il tire l'ordre à partir de la piste
    // courante et la place en tête, si bien qu'activer l'aléatoire ne coupe pas
    // ce qui joue. Sans source chargée il n'y a rien à mélanger — le prochain
    // `loadQueue` s'en chargera.
    if (enabled && _hasSource) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
  }

  /// Applique le mode de répétition au lecteur natif.
  ///
  /// Nommée `setRepeat` et non `setRepeatMode` : `BaseAudioHandler` réserve
  /// déjà ce nom pour la commande système (`AudioServiceRepeatMode`), qui n'est
  /// pas le même vocabulaire.
  @override
  Future<void> setRepeat(QueueRepeatMode mode) => _player.setLoopMode(
    const {
      QueueRepeatMode.off: LoopMode.off,
      QueueRepeatMode.one: LoopMode.one,
      QueueRepeatMode.all: LoopMode.all,
    }[mode]!,
  );

  @override
  Future<void> loadUri(String url, {required NowPlaying now}) async {
    // Un direct n'a ni file ni fin : les modes hérités d'une écoute de playlist
    // n'ont plus de sens ici (et `LoopMode.one` rejouerait un segment).
    await _player.setShuffleModeEnabled(false);
    await _player.setLoopMode(LoopMode.off);
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
    Duration initialPosition = Duration.zero,
    Map<String, String> headers = const {},
    PlaybackOrder? order,
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

    // Ordre imposé (rechargement subi) : le lecteur le reçoit tel quel et ne
    // tire rien. Le vérifier ici plutôt que de faire confiance à l'appelant —
    // un ordre qui ne couvre pas exactement la file désordonnerait la lecture.
    final keep = order != null && _coversQueue(order, items.length)
        ? _FixedShuffleOrder(order.indices)
        : null;

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
        shuffleOrder: keep,
      ),
      initialIndex: start,
      initialPosition: initialPosition,
    );

    // Chaque source neuve arrive avec un ordre de mélange neuf, donc naturel :
    // sans ce tirage, relancer une playlist en mode aléatoire la rejouerait
    // dans l'ordre. `shuffle()` garde la piste de départ en tête. Sauté quand un
    // ordre est imposé, sinon il l'écraserait aussitôt.
    if (_player.shuffleModeEnabled && keep == null) await _player.shuffle();
  }

  /// Un ordre n'est réutilisable que s'il est une permutation exacte de la file
  /// à charger : à un élément près, il laisserait des pistes injouables ou
  /// pointerait hors de la file.
  static bool _coversQueue(PlaybackOrder order, int length) {
    if (order.indices.length != length) return false;
    final seen = List.filled(length, false);
    for (final index in order.indices) {
      if (index < 0 || index >= length || seen[index]) return false;
      seen[index] = true;
    }
    return true;
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
  Future<void> skipToNext() => _skipRelative(1);

  @override
  Future<void> skipToPrevious() => _skipRelative(-1);

  /// Saut manuel d'un rang dans l'**ordre de lecture** (mélangé ou non).
  ///
  /// Volontairement pas `_player.seekToNext()` : sous `LoopMode.one`, just_audio
  /// y renvoie la piste courante, et le bouton « suivant » de la notification
  /// ne ferait que la redémarrer. La répétition d'une piste ne concerne que
  /// l'enchaînement automatique — d'où le passage par [PlaybackOrder], partagé
  /// avec les boutons de l'application.
  Future<void> _skipRelative(int offset) async {
    if (!_hasSource) return;
    final current = _player.currentIndex;
    if (current == null) return;
    final target = playbackOrder.relative(
      current,
      offset,
      wrap: _player.loopMode == LoopMode.all,
    );
    if (target == null) return;
    await _player.seek(Duration.zero, index: target);
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
        _restoreVolumeIfDucked(); // défensif : un `unduck` a pu se perdre
        // Volontairement `play()` du handler et non `_player.play()` : la
        // fin d'une interruption ne doit pas ressusciter une source que
        // l'application a abandonnée entre-temps (garde `_hasSource`).
        unawaited(play());
      case InterruptionAction.duck:
        _volumeLevel = _volumeLevel.withDucked(true);
        unawaited(_player.setVolume(_volumeLevel.effective));
      case InterruptionAction.unduck:
        _restoreVolumeIfDucked();
      case InterruptionAction.none:
        break;
    }
  }

  /// Lève l'atténuation en revenant au niveau **choisi par l'auditeur**, et non
  /// à un niveau capturé avant le duck : si le curseur a bougé entre-temps,
  /// c'est le nouveau réglage qui doit survivre à l'interruption.
  ///
  /// Ne fait rien hors d'un duck, pour ne pas réécrire le volume sans raison.
  void _restoreVolumeIfDucked() {
    if (!_volumeLevel.ducked) return;
    _volumeLevel = _volumeLevel.withDucked(false);
    unawaited(_player.setVolume(_volumeLevel.effective));
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
      processingState:
          const {
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

/// Ordre de lecture **imposé** : rend la permutation qu'on lui donne et ignore
/// les demandes de mélange.
///
/// Sert aux rechargements subis (reprise après erreur) : le lecteur repart d'une
/// source neuve, mais la suite annoncée à l'auditeur ne doit pas changer parce
/// que le réseau a hoqueté.
///
/// `ConcatenatingAudioSource` appelle `insert(0, n)` depuis son constructeur
/// pour déclarer ses enfants : c'est là qu'on pose la permutation. Les autres
/// mutations n'arrivent pas dans cette application (une file n'est jamais
/// modifiée en place, elle est rechargée entière) ; elles sont quand même
/// traitées, en ordre naturel, plutôt que de laisser des index incohérents.
class _FixedShuffleOrder extends ShuffleOrder {
  _FixedShuffleOrder(this._fixed);

  final List<int> _fixed;

  @override
  final indices = <int>[];

  @override
  void shuffle({int? initialIndex}) {}

  @override
  void insert(int index, int count) {
    if (index == 0 && indices.isEmpty && count == _fixed.length) {
      indices.addAll(_fixed);
      return;
    }
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += count;
    }
    indices.insertAll(index, List.generate(count, (i) => index + i));
  }

  @override
  void removeRange(int start, int end) {
    final count = end - start;
    indices.removeWhere((i) => i >= start && i < end);
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= end) indices[i] -= count;
    }
  }

  @override
  void clear() => indices.clear();
}
