import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/app/app.dart';
import 'package:streampulse/app/app_providers.dart';

import 'support/fake_audio_playback_service.dart';
import 'support/fake_queue_playback_service.dart';

void main() {
  testWidgets('App démarre sans erreur', (WidgetTester tester) async {
    final audioService = FakeAudioPlaybackService();
    final queueService = FakeQueuePlaybackService();
    addTearDown(audioService.dispose);
    addTearDown(queueService.dispose);

    await tester.pumpWidget(
      StreamPulseApp(
        audioService: audioService,
        queueService: queueService,
        child: const App(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
