import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';

/// Fake AudioPlayer just_audio : n'implémente que les membres utilisés par
/// [AudioPlayerController] (les autres passent par [noSuchMethod], jamais
/// appelé ici). Permet de piloter les échecs de lecture sans plateforme ni
/// device — la sonde [StreamEndedProbe] étant injectable, tout le cœur de
/// STR-118 (`_recover`) devient testable unitairement.
class _FakeAudioPlayer implements AudioPlayer {
  final _stateCtrl = StreamController<PlayerState>.broadcast();
  final _eventCtrl = StreamController<PlaybackEvent>.broadcast();

  /// Si non nul, [setAudioSource] lève cette erreur (simule une source error).
  Object? setAudioSourceError;
  int setAudioSourceCalls = 0;
  bool disposed = false;
  bool _playing = false;

  void emitState(PlayerState state) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => _eventCtrl.stream;
  @override
  bool get playing => _playing;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    setAudioSourceCalls++;
    final err = setAudioSourceError;
    if (err != null) throw err;
    return null;
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _stateCtrl.close();
    await _eventCtrl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('AudioPlayerController._recover (STR-118)', () {
    test('sonde vraie (fin de direct) → ended, aucun retry armé', () async {
      final player = _FakeAudioPlayer()..setAudioSourceError = Exception('404');
      final controller = AudioPlayerController(
        player: player,
        isStreamEnded: (_) async => true,
      );
      addTearDown(controller.dispose);

      await controller.load('s1');
      await pumpEventQueue(); // laisse _recover attendre la sonde puis poser l'état

      expect(controller.status, PlaybackStatus.ended);
      expect(controller.isEnded, isTrue);
      // Fin de direct : on ne réarme pas de tentative → une seule source posée.
      expect(player.setAudioSourceCalls, 1);
    });

    test(
        'sonde vraie posée, puis état résiduel du player → ended non écrasé',
        () async {
      final player = _FakeAudioPlayer()..setAudioSourceError = Exception('409');
      final controller = AudioPlayerController(
        player: player,
        isStreamEnded: (_) async => true,
      );
      addTearDown(controller.dispose);

      await controller.load('s1');
      await pumpEventQueue();
      expect(controller.status, PlaybackStatus.ended);

      // ExoPlayer émet un `idle` résiduel après la source error : ne doit pas
      // faire régresser « terminé » en « en pause » (garde dans _onPlayerState).
      player.emitState(PlayerState(false, ProcessingState.idle));
      await pumpEventQueue();
      expect(controller.status, PlaybackStatus.ended);
    });

    test(
        'sonde fausse (coupure réseau) → reconnecting, puis error après 3 tentatives',
        () {
      fakeAsync((async) {
        final player = _FakeAudioPlayer()
          ..setAudioSourceError = Exception('network');
        final controller = AudioPlayerController(
          player: player,
          isStreamEnded: (_) async => false,
        );

        controller.load('s1');
        async.flushMicrotasks();
        // 1re tentative initiale échouée → reconnexion programmée.
        expect(controller.status, PlaybackStatus.reconnecting);
        expect(player.setAudioSourceCalls, 1);

        // Backoff 1s, 2s, 4s : chaque réveil relance _start (qui échoue encore).
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(player.setAudioSourceCalls, 2);
        expect(controller.status, PlaybackStatus.reconnecting);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(player.setAudioSourceCalls, 3);
        expect(controller.status, PlaybackStatus.reconnecting);

        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        // 4e échec : tentatives épuisées → erreur définitive, plus de timer.
        expect(player.setAudioSourceCalls, 4);
        expect(controller.status, PlaybackStatus.error);

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(player.setAudioSourceCalls, 4); // aucun timer résiduel

        controller.dispose();
      });
    });

    test(
        'dispose() pendant l\'attente de la sonde → aucune notification, aucun timer résiduel',
        () async {
      final player = _FakeAudioPlayer()..setAudioSourceError = Exception('x');
      final probe = Completer<bool>();
      final controller = AudioPlayerController(
        player: player,
        isStreamEnded: (_) => probe.future,
      );

      var notificationsAfterDispose = 0;
      var disposed = false;
      controller.addListener(() {
        if (disposed) notificationsAfterDispose++;
      });

      await controller.load('s1');
      await pumpEventQueue(); // _recover est maintenant bloqué sur la sonde

      disposed = true;
      controller.dispose();

      // La sonde se résout après coup : le contrôleur détruit ne doit ni
      // notifier ni armer de timer (garde _disposed).
      probe.complete(true);
      await pumpEventQueue();

      expect(notificationsAfterDispose, 0);
      expect(player.disposed, isTrue);
    });
  });
}
