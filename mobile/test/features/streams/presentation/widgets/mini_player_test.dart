import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:provider/provider.dart';

import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';
import 'package:streampulse/features/streams/presentation/widgets/mini_player.dart';

import '../../../../support/fake_audio_playback_service.dart';

Widget _host(AudioPlayerController controller) {
  return ChangeNotifierProvider<AudioPlayerController>.value(
    value: controller,
    child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
  );
}

const _now = NowPlaying(streamId: 's1', title: 'Radio Nova', broadcaster: 'DJ Qa');

void main() {
  testWidgets('masqué quand rien ne joue (idle)', (tester) async {
    final service = FakeAudioPlaybackService();
    final controller = AudioPlayerController(service: service);
    addTearDown(controller.dispose);
    addTearDown(service.dispose);

    await tester.pumpWidget(_host(controller));

    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('affiche titre + diffuseur et le bouton pause en lecture',
      (tester) async {
    final service = FakeAudioPlaybackService();
    final controller = AudioPlayerController(service: service);
    addTearDown(controller.dispose);
    addTearDown(service.dispose);

    await controller.load(_now);
    service.emitState(PlayerState(true, ProcessingState.ready)); // → playing
    await tester.pumpWidget(_host(controller));
    await tester.pump();

    expect(find.text('Radio Nova'), findsOneWidget);
    expect(find.text('DJ Qa'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('la croix arrête la lecture et masque le mini-player',
      (tester) async {
    final service = FakeAudioPlaybackService();
    final controller = AudioPlayerController(service: service);
    addTearDown(controller.dispose);
    addTearDown(service.dispose);

    await controller.load(_now);
    service.emitState(PlayerState(true, ProcessingState.ready));
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    expect(find.text('Radio Nova'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(service.stopped, isTrue);
    expect(find.text('Radio Nova'), findsNothing); // idle → masqué
  });
}
