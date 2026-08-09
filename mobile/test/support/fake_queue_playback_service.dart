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

  /// Si non nul, [loadQueue] lève cette erreur (simule une source injoignable,
  /// typiquement un 401 sur un access token périmé).
  Object? loadError;

  int loadCalls = 0;
  int playCalls = 0;
  bool stopped = false;
  List<QueueItem> lastItems = const [];
  int? lastInitialIndex;
  Map<String, String> lastHeaders = const {};
  final List<int> skips = [];
  bool _playing = false;

  void emitState(PlayerState state) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }

  void emitIndex(int? index) {
    if (!_indexCtrl.isClosed) _indexCtrl.add(index);
  }

  void emitError(Object error) {
    if (!_errorCtrl.isClosed) _errorCtrl.add(error);
  }

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;
  @override
  Stream<int?> get currentIndexStream => _indexCtrl.stream;
  @override
  Stream<Object> get playbackErrors => _errorCtrl.stream;
  @override
  bool get playing => _playing;

  @override
  Future<void> loadQueue(
    List<QueueItem> items, {
    int initialIndex = 0,
    Map<String, String> headers = const {},
  }) async {
    loadCalls++;
    lastItems = items;
    lastInitialIndex = initialIndex;
    lastHeaders = headers;
    final err = loadError;
    if (err != null) throw err;
  }

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
  }
}
