import 'dart:async';

import 'package:just_audio/just_audio.dart' show PlayerState;
import 'package:streampulse/core/audio/audio_playback_service.dart';

/// Fake [AudioPlaybackService] pilotable, sans just_audio ni audio_service : les
/// flux d'état / d'erreur sont poussés manuellement, `loadUri` peut échouer à la
/// demande. Rend le cœur de STR-118 (`_recover`) et le démarrage app-level
/// testables unitairement (STR-109).
class FakeAudioPlaybackService implements AudioPlaybackService {
  final _stateCtrl = StreamController<PlayerState>.broadcast();
  final _errorCtrl = StreamController<Object>.broadcast();

  /// Si non nul, [loadUri] lève cette erreur (simule une source error).
  Object? loadError;
  int loadCalls = 0;
  bool stopped = false;
  NowPlaying? lastNow;
  bool _playing = false;

  void emitState(PlayerState state) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }

  void emitError(Object error) {
    if (!_errorCtrl.isClosed) _errorCtrl.add(error);
  }

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;
  @override
  Stream<Object> get playbackErrors => _errorCtrl.stream;
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
  Future<void> loadUri(String url, {required NowPlaying now}) async {
    loadCalls++;
    lastNow = now;
    final err = loadError;
    if (err != null) throw err;
  }

  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;

  @override
  Future<void> stop() async {
    stopped = true;
    _playing = false;
  }

  Future<void> dispose() async {
    await _stateCtrl.close();
    await _errorCtrl.close();
  }
}
