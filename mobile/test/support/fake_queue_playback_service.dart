import 'dart:async';

import 'package:just_audio/just_audio.dart' show PlayerState;
import 'package:streampulse/core/audio/queue_playback_service.dart';

/// Fake [QueuePlaybackService] pilotable, sans just_audio ni audio_service : les
/// flux d'état / d'index / d'erreur sont poussés manuellement et `loadQueue`
/// peut échouer à la demande. Rend testable le cœur de l'US-05-04 (enchaînement
/// suivi via `currentIndexStream`, saut de piste, reprise après token expiré).
class FakeQueuePlaybackService implements QueuePlaybackService {
  final _stateCtrl = StreamController<PlayerState>.broadcast();
  final _indexCtrl = StreamController<int?>.broadcast();
  final _errorCtrl = StreamController<Object>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferedCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration?>.broadcast();

  /// Déplacements demandés par l'application (STR-230).
  final List<Duration> seeks = [];

  /// Si non nul, [loadQueue] lève cette erreur (simule une source injoignable,
  /// typiquement un 401 sur un access token périmé).
  Object? loadError;

  int loadCalls = 0;
  int playCalls = 0;
  bool stopped = false;
  List<QueueItem> lastItems = const [];
  int? lastInitialIndex;
  Duration? lastInitialPosition;

  /// Position simulée du lecteur, relevée par le contrôleur avant une reprise.
  @override
  Duration position = Duration.zero;
  Map<String, String> lastHeaders = const {};
  final List<int> skips = [];
  bool _playing = false;

  bool shuffleEnabled = false;
  QueueRepeatMode repeatMode = QueueRepeatMode.off;

  /// Ordre rendu quand l'aléatoire est actif. Fixé (et non tiré au sort) pour
  /// que les tests décrivent un ordre précis ; à défaut, l'ordre inverse suffit
  /// à distinguer « mélangé » de « naturel ».
  List<int>? shuffledOrder;

  /// Ordre imposé au dernier [loadQueue] (`null` = nouveau tirage demandé).
  PlaybackOrder? lastOrder;

  /// Ordre effectivement conservé par le lecteur simulé, comme le vrai handler :
  /// un ordre imposé prime sur le tirage.
  List<int>? _keptOrder;

  void emitState(PlayerState state) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }

  void emitIndex(int? index) {
    if (!_indexCtrl.isClosed) _indexCtrl.add(index);
  }

  void emitError(Object error) {
    if (!_errorCtrl.isClosed) _errorCtrl.add(error);
  }

  /// Avancement simulé (STR-230). La durée est poussée séparément : le vrai
  /// lecteur ne la connaît qu'après avoir ouvert le fichier.
  void emitPosition(Duration position, {Duration? buffered}) {
    if (!_positionCtrl.isClosed) _positionCtrl.add(position);
    if (!_bufferedCtrl.isClosed) _bufferedCtrl.add(buffered ?? position);
  }

  void emitDuration(Duration? duration) {
    _duration = duration;
    if (!_durationCtrl.isClosed) _durationCtrl.add(duration);
  }

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;
  @override
  Stream<int?> get currentIndexStream => _indexCtrl.stream;
  @override
  Stream<Object> get playbackErrors => _errorCtrl.stream;
  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _bufferedCtrl.stream;

  /// Rejoue la dernière durée connue à chaque nouvel abonné, comme le
  /// `BehaviorSubject` de just_audio : sans ça, un widget monté après le
  /// chargement de la piste n'apprendrait jamais sa durée.
  @override
  Stream<Duration?> get durationStream async* {
    yield _duration;
    yield* _durationCtrl.stream;
  }

  Duration? _duration;
  @override
  bool get playing => _playing;

  final _volumeCtrl = StreamController<double>.broadcast();
  double _volume = 1;

  @override
  double get volume => _volume;
  @override
  Stream<double> get volumeStream => _volumeCtrl.stream;
  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (!_volumeCtrl.isClosed) _volumeCtrl.add(_volume);
  }

  @override
  Future<void> seek(Duration to) async {
    seeks.add(to);
    position = to;
    emitPosition(to);
  }

  @override
  Future<void> loadQueue(
    List<QueueItem> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    Map<String, String> headers = const {},
    PlaybackOrder? order,
  }) async {
    loadCalls++;
    lastItems = items;
    lastInitialIndex = initialIndex;
    lastInitialPosition = initialPosition;
    lastHeaders = headers;
    lastOrder = order;
    _keptOrder = order == null ? null : List.of(order.indices);
    final err = loadError;
    if (err != null) throw err;
  }

  /// Ordre de lecture simulé : naturel, ou mélangé quand l'aléatoire est actif
  /// — comme le lecteur natif, qui tire son ordre au chargement.
  @override
  PlaybackOrder get playbackOrder {
    if (!shuffleEnabled) return PlaybackOrder.natural(lastItems.length);
    final kept = _keptOrder;
    if (kept != null) return PlaybackOrder(kept);
    return PlaybackOrder(
      shuffledOrder ??
          List.generate(lastItems.length, (i) => lastItems.length - 1 - i),
    );
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    shuffleEnabled = enabled;
    // Comme le vrai handler : activer l'aléatoire tire un ordre neuf.
    if (enabled) _keptOrder = null;
  }

  @override
  Future<void> setRepeat(QueueRepeatMode mode) async => repeatMode = mode;

  @override
  Future<void> skipToIndex(int index) async => skips.add(index);

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
  }

  @override
  Future<void> pause() async => _playing = false;

  @override
  Future<void> stop() async {
    stopped = true;
    _playing = false;
  }

  Future<void> dispose() async {
    await _stateCtrl.close();
    await _indexCtrl.close();
    await _errorCtrl.close();
    await _positionCtrl.close();
    await _bufferedCtrl.close();
    await _durationCtrl.close();
  }
}
