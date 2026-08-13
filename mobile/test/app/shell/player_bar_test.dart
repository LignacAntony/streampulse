import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:streampulse/app/shell/player_bar.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/widgets/queue_mini_player.dart';
import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';
import 'package:streampulse/features/streams/presentation/widgets/mini_player.dart';

import '../../support/fake_audio_playback_service.dart';
import '../../support/fake_queue_playback_service.dart';

const _now = NowPlaying(streamId: 's1', title: 'Radio Nova', broadcaster: 'DJ');

const _tracks = [
  Track(id: 't1', title: 'Midnight Drive', artist: 'Neon Lights', durationS: 214),
];

/// Reproduit le câblage croisé d'`app_providers` : démarrer une file arrête le
/// direct, et démarrer un direct abandonne la file.
({
  AudioPlayerController live,
  PlaylistQueueController queue,
}) _controllers(
  FakeAudioPlaybackService liveService,
  FakeQueuePlaybackService queueService,
) {
  final live = AudioPlayerController(service: liveService);
  final queue = PlaylistQueueController(
    service: queueService,
    token: ({bool forceRefresh = false}) async => 'jwt',
    stopLive: live.stop,
  );
  live.onTakeOver = queue.clear;
  addTearDown(live.dispose);
  addTearDown(queue.dispose);
  return (live: live, queue: queue);
}

Widget _host(AudioPlayerController live, PlaylistQueueController queue) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AudioPlayerController>.value(value: live),
      ChangeNotifierProvider<PlaylistQueueController>.value(value: queue),
    ],
    child: const MaterialApp(home: Scaffold(body: PlayerBar())),
  );
}

void main() {
  group('PlayerBar — un seul lecteur pour deux sources (US-05-04)', () {
    testWidgets('sans file active, la barre est celle du direct',
        (tester) async {
      final liveService = FakeAudioPlaybackService();
      final queueService = FakeQueuePlaybackService();
      addTearDown(liveService.dispose);
      addTearDown(queueService.dispose);
      final c = _controllers(liveService, queueService);

      await tester.pumpWidget(_host(c.live, c.queue));

      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.byType(QueueMiniPlayer), findsNothing);
    });

    testWidgets('lancer une playlist arrête le direct et bascule la barre',
        (tester) async {
      final liveService = FakeAudioPlaybackService();
      final queueService = FakeQueuePlaybackService();
      addTearDown(liveService.dispose);
      addTearDown(queueService.dispose);
      final c = _controllers(liveService, queueService);

      await c.live.load(_now);
      await c.queue.play(
        tracks: _tracks,
        sourceName: 'My Favorites',
        playlistId: 'p-1',
      );
      await tester.pumpWidget(_host(c.live, c.queue));

      expect(find.byType(QueueMiniPlayer), findsOneWidget);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(c.live.status, PlaybackStatus.idle);
    });

    testWidgets('reprendre un direct abandonne la file et rend la barre',
        (tester) async {
      final liveService = FakeAudioPlaybackService();
      final queueService = FakeQueuePlaybackService();
      addTearDown(liveService.dispose);
      addTearDown(queueService.dispose);
      final c = _controllers(liveService, queueService);

      await c.queue.play(
        tracks: _tracks,
        sourceName: 'My Favorites',
        playlistId: 'p-1',
      );
      await c.live.load(_now);
      await tester.pumpWidget(_host(c.live, c.queue));

      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.byType(QueueMiniPlayer), findsNothing);
      expect(c.queue.hasQueue, isFalse);
      // Le direct vient de charger la source partagée : la file l'abandonne
      // sans arrêter le lecteur, sinon elle couperait ce direct.
      expect(queueService.stopped, isFalse);
    });
  });
}
